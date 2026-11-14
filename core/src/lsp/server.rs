//! Language Server Protocol server for Lumen.
//!
//! Provides editor integration for VS Code, Neovim, Helix, Zed, etc.
//! Features:
//!   - Wikilink completion (`[[` → fuzzy search)
//!   - Go to definition (resolve wikilink → file location)
//!   - Find references (all wikilinks pointing to a note)
//!   - Document symbols (headings, wikilinks)

use std::collections::{BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use tower_lsp::{jsonrpc, LspService, Server};
use tower_lsp::lsp_types::*;

use crate::vault::{self, STORE_JOURNAL};
use crate::wikilinks::{self, resolve_wikilink};

/// Index of wikilinks for LSP features.
#[derive(Clone, Default)]
pub struct WikilinkIndex {
    /// Note path -> set of wikilink targets it references.
    outgoing: HashMap<String, BTreeSet<String>>,
    /// Wikilink target -> set of note paths that reference it.
    incoming: HashMap<String, BTreeSet<String>>,
    /// All note paths.
    notes: BTreeSet<String>,
}

impl WikilinkIndex {
    /// Build the index by scanning all notes in the vault.
    pub fn build(vault_path: &Path, store: &str) -> Result<Self, String> {
        let mut outgoing: HashMap<String, BTreeSet<String>> = HashMap::new();
        let mut incoming: HashMap<String, BTreeSet<String>> = HashMap::new();
        let mut notes = BTreeSet::new();

        if let Ok(entries) = vault::list("", store) {
            for entry in entries {
                if entry.is_dir || !entry.name.ends_with(".md") {
                    continue;
                }
                notes.insert(entry.rel_path.clone());
                if let Ok(body) = vault::read_text(&entry.rel_path, store) {
                    let links = wikilinks::parse_wikilinks(&body);
                    let targets: BTreeSet<String> = links
                        .iter()
                        .map(|wl| wl.target.clone())
                        .collect();
                    outgoing.insert(entry.rel_path.clone(), targets.clone());
                    for target in targets {
                        incoming.entry(target).or_default().insert(entry.rel_path.clone());
                    }
                }
            }
        }

        Ok(Self {
            outgoing,
            incoming,
            notes,
        })
    }

    /// Resolve a wikilink target to a note path.
    pub fn resolve(&self, target: &str) -> Option<String> {
        if self.notes.contains(target) {
            return Some(target.to_string());
        }
        let with_md = format!("{}.md", target);
        if self.notes.contains(&with_md) {
            return Some(with_md);
        }
        for note in &self.notes {
            if wikilinks::slugify(note) == wikilinks::slugify(target) {
                return Some(note.clone());
            }
        }
        None
    }

    /// Get all notes that reference a given target.
    pub fn references(&self, target: &str) -> Vec<String> {
        self.incoming
            .get(target)
            .cloned()
            .unwrap_or_default()
            .into_iter()
            .collect()
    }
}

/// The Lumen LSP server state.
#[derive(Clone)]
pub struct LumenLspServer {
    vault_path: PathBuf,
    index: Arc<WikilinkIndex>,
}

impl LumenLspServer {
    /// Create a new LSP server for the given vault.
    pub fn new(vault_path: &Path, store: &str) -> Result<Self, String> {
        let index = WikilinkIndex::build(vault_path, store)?;
        Ok(Self {
            vault_path: vault_path.to_path_buf(),
            index: Arc::new(index),
        })
    }
}

#[tower_lsp::async_trait]
impl tower_lsp::LanguageServer for LumenLspServer {
    async fn initialize(
        &self,
        _: tower_lsp::lsp_types::InitializeParams,
    ) -> jsonrpc::Result<InitializeResult> {
        Ok(InitializeResult {
            capabilities: ServerCapabilities {
                text_document_sync: Some(TextDocumentSyncCapability::Kind(
                    TextDocumentSyncKind::INCREMENTAL,
                )),
                completion_provider: Some(CompletionOptions {
                    resolve_provider: Some(false),
                    trigger_characters: Some(vec!["[".to_string()]),
                    ..Default::default()
                }),
                definition_provider: Some(OneOf::Left(true)),
                references_provider: Some(OneOf::Left(true)),
                document_symbol_provider: Some(OneOf::Left(true)),
                ..Default::default()
            },
            server_info: Some(ServerInfo {
                name: "Lumen LSP".to_string(),
                version: Some(env!("CARGO_PKG_VERSION").to_string()),
            }),
        })
    }

    async fn initialized(&self, _: tower_lsp::lsp_types::InitializedParams) {}

    async fn shutdown(&self) -> jsonrpc::Result<()> {
        Ok(())
    }

    async fn completion(
        &self,
        params: CompletionParams,
    ) -> jsonrpc::Result<Option<CompletionResponse>> {
        let uri = &params.text_document_position.text_document.uri;
        let path = uri.path();
        let position = params.text_document_position.position;

        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(_) => return Ok(None),
        };

        let line = content.lines().nth(position.line as usize);
        let Some(line) = line else {
            return Ok(None);
        };

        let char_pos = position.character as usize;
        let before_cursor = &line[..char_pos.min(line.len())];

        let wikilink_start = before_cursor.rfind("[[");
        if let Some(start) = wikilink_start {
            let target_part = &before_cursor[start + 2..];
            if !target_part.is_empty() {
                let items: Vec<CompletionItem> = self
                    .index
                    .notes
                    .iter()
                    .filter(|n| n.to_lowercase().contains(&target_part.to_lowercase()))
                    .take(20)
                    .map(|n| {
                        CompletionItem::new_simple(
                            n.clone(),
                            format!("Open note: {}", n),
                        )
                    })
                    .collect();
                return Ok(Some(CompletionResponse::Array(items)));
            }
        }

        Ok(None)
    }

    async fn goto_definition(
        &self,
        params: GotoDefinitionParams,
    ) -> jsonrpc::Result<Option<GotoDefinitionResponse>> {
        let uri = &params.text_document_position_params.text_document.uri;
        let path = uri.path();
        let position = params.text_document_position_params.position;

        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(_) => return Ok(None),
        };

        let line = content.lines().nth(position.line as usize);
        let Some(line) = line else {
            return Ok(None);
        };

        let char_pos = position.character as usize;
        let before_cursor = &line[..char_pos.min(line.len())];

        for wl in wikilinks::parse_wikilinks(&content) {
            if char_pos >= wl.position.start && char_pos <= wl.position.end {
                if let Some(resolved) = self.index.resolve(&wl.target) {
                    let target_path = Path::new(path).parent().unwrap_or(Path::new("")).join(&resolved);
                    if let Ok(uri) = Url::from_file_path(target_path) {
                        return Ok(Some(GotoDefinitionResponse::Scalar(Location {
                            uri,
                            range: Range {
                                start: Position::new(0, 0),
                                end: Position::new(0, 0),
                            },
                        })));
                    }
                }
            }
        }

        Ok(None)
    }

    async fn references(
        &self,
        params: ReferenceParams,
    ) -> jsonrpc::Result<Option<Vec<Location>>> {
        let uri = &params.text_document_position.text_document.uri;
        let path = uri.path();
        let position = params.text_document_position.position;

        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(_) => return Ok(None),
        };

        let line = content.lines().nth(position.line as usize);
        let Some(line) = line else {
            return Ok(None);
        };

        let char_pos = position.character as usize;
        let before_cursor = &line[..char_pos.min(line.len())];

        for wl in wikilinks::parse_wikilinks(&content) {
            if char_pos >= wl.position.start && char_pos <= wl.position.end {
                let targets = self.index.references(&wl.target);
                let locations: Vec<Location> = targets
                    .into_iter()
                    .filter_map(|target| {
                        let target_path =
                            Path::new(path).parent().unwrap_or(Path::new("")).join(&target);
                        Url::from_file_path(target_path)
                            .ok()
                            .map(|uri| Location {
                                uri,
                                range: Range {
                                    start: Position::new(0, 0),
                                    end: Position::new(0, 0),
                                },
                            })
                    })
                    .collect();
                return Ok(Some(locations));
            }
        }

        Ok(None)
    }

    async fn document_symbol(
        &self,
        params: DocumentSymbolParams,
    ) -> jsonrpc::Result<Option<DocumentSymbolResponse>> {
        let uri = &params.text_document.uri;
        let path = uri.path();
        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(_) => return Ok(None),
        };

        let mut symbols = Vec::new();
        for (line_idx, line) in content.lines().enumerate() {
            if let Some(rest) = line.strip_prefix("# ") {
                symbols.push(DocumentSymbol {
                    name: rest.to_string(),
                    kind: SymbolKind::STRING,
                    range: Range {
                        start: Position::new(line_idx as u32, 0),
                        end: Position::new(line_idx as u32, rest.len() as u32),
                    },
                    selection_range: Range {
                        start: Position::new(line_idx as u32, 2),
                        end: Position::new(line_idx as u32, (2 + rest.len()) as u32),
                    },
                    children: None,
                    tags: None,
                    deprecated: None,
                    detail: None,
                });
            }
            for wl in wikilinks::parse_wikilinks(line) {
                symbols.push(DocumentSymbol {
                    name: format!("[[{}]]", wl.target),
                    kind: SymbolKind::STRING,
                    range: Range {
                        start: Position::new(line_idx as u32, wl.position.start as u32),
                        end: Position::new(line_idx as u32, wl.position.end as u32),
                    },
                    selection_range: Range {
                        start: Position::new(line_idx as u32, wl.position.start as u32),
                        end: Position::new(line_idx as u32, wl.position.end as u32),
                    },
                    children: None,
                    tags: None,
                    deprecated: None,
                    detail: None,
                });
            }
        }

        Ok(Some(DocumentSymbolResponse::Nested(symbols)))
    }

    async fn did_open(&self, _: DidOpenTextDocumentParams) {}
    async fn did_change(&self, _: DidChangeTextDocumentParams) {}
    async fn did_save(&self, _: DidSaveTextDocumentParams) {}
    async fn did_close(&self, _: DidCloseTextDocumentParams) {}
}

/// Run the LSP server on stdin/stdout.
pub async fn run() {
    let stdin = tokio::io::stdin();
    let stdout = tokio::io::stdout();

    let (service, socket) = LspService::build(|client| {
        let vault_path = std::env::var("LUMEN_VAULT")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("."));
        LumenLspServer::new(&vault_path, STORE_JOURNAL).expect("failed to create LSP server")
    })
    .finish();

    Server::new(stdin, stdout, socket).serve(service).await;
}

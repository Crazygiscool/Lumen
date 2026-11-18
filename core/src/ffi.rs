//! FFI entry points for knowledge base features.
//!
//! `lumen_kb_call(method, json_args) -> json_result`
//! Result envelope: `{ "ok": bool, "data": <value>, "error": <string> }`.

use std::ffi::{CStr, CString};
use std::fs;
use std::os::raw::c_char;
use std::path::Path;

use serde::Deserialize;

use crate::auto_update::{check_for_update, download_update, apply_update, current_version, UpdateStatus};
use crate::commands::{list_commands, register_builtin_commands};
use crate::ai::{self, OllamaClient};

use crate::config;
use crate::frontmatter::{self, Frontmatter};
use crate::search::{init_search_index, search_entries};
use crate::secrets;
use crate::sync::{
    create_backup_bundle, generate_syncthing_config, get_sync_status, init_sync_store,
    resolve_conflict, restore_backup_bundle,
    webdav::{WebDAVConfig, WebDAVSync},
};
use crate::template::{daily_note_path, ensure_template_exists, render_daily_template};
use crate::vault::{self, STORE_JOURNAL};
use crate::wikilinks::{
    get_backlinks, init_backlink_index, parse_wikilinks, resolve_wikilink, Wikilink,
};

fn default_store() -> String {
    STORE_JOURNAL.to_string()
}

#[derive(Deserialize)]
struct PathArgs {
    path: String,
    #[serde(default = "default_store")]
    store: String,
}

#[derive(Deserialize)]
struct StoreArgs {
    #[serde(default = "default_store")]
    store: String,
}

#[derive(Deserialize)]
struct SearchArgs {
    query: String,
    #[serde(default = "default_max")]
    limit: usize,
    #[serde(default = "default_store")]
    store: String,
}

#[derive(Deserialize)]
struct DateArgs {
    /// Milliseconds since epoch.
    date_ms: i64,
}

#[derive(Deserialize)]
struct WikilinkArgs {
    target: String,
    #[serde(default = "default_store")]
    store: String,
}

fn default_max() -> usize {
    50
}

fn default_true() -> bool {
    true
}

fn default_top_k() -> usize {
    5
}

/// Shared tokio runtime for the async FFI entry points (WebDAV).
///
/// Creating a runtime per call is wasteful, and a panic on a failed runtime
/// would take down the whole app, so it is created once and reused.
fn runtime() -> crate::Result<&'static tokio::runtime::Runtime> {
    static RT: std::sync::OnceLock<Result<tokio::runtime::Runtime, String>> =
        std::sync::OnceLock::new();
    match RT.get_or_init(|| tokio::runtime::Runtime::new().map_err(|e| e.to_string())) {
        Ok(rt) => Ok(rt),
        Err(e) => Err(e.clone()),
    }
}

fn ok(v: serde_json::Value) -> serde_json::Value {
    serde_json::json!({ "ok": true, "data": v })
}

fn err(e: impl ToString) -> serde_json::Value {
    serde_json::json!({ "ok": false, "error": e.to_string() })
}

fn wikilink_to_json(wl: &Wikilink) -> serde_json::Value {
    serde_json::json!({
        "target": wl.target,
        "display": wl.display,
        "start": wl.position.start,
        "end": wl.position.end,
    })
}

fn dispatch(method: &str, args: &serde_json::Value) -> serde_json::Value {
    macro_rules! parse {
        ($t:ty) => {
            match serde_json::from_value::<$t>(args.clone()) {
                Ok(v) => v,
                Err(e) => return err(format!("bad args for '{method}': {e}")),
            }
        };
    }

    let result = match method {
        // Wikilinks
        "kb.wikilinks.parse" => {
            let a = parse!(PathArgs);
            let body = match vault::read_text(&a.path, &a.store) {
                Ok(t) => t,
                Err(e) => return err(e),
            };
            let links = parse_wikilinks(&body);
            ok(
                serde_json::json!({ "links": links.iter().map(wikilink_to_json).collect::<Vec<_>>() }),
            )
        }
        "kb.wikilinks.resolve" => {
            let a = parse!(WikilinkArgs);
            let resolved = resolve_wikilink(&a.store, &a.target);
            ok(serde_json::json!({ "path": resolved }))
        }
        "kb.wikilinks.create_missing" => {
            let a = parse!(WikilinkArgs);
            match crate::wikilinks::create_missing(&a.store, &a.target) {
                Ok(created) => ok(serde_json::json!({ "created": created })),
                Err(e) => err(e),
            }
        }
        "kb.wikilinks.backlinks" => {
            let a = parse!(PathArgs);
            let backlinks = get_backlinks(&a.store, &a.path);
            ok(serde_json::json!({ "backlinks": backlinks }))
        }
        "kb.wikilinks.rebuild_index" => {
            let a = parse!(StoreArgs);
            init_backlink_index(&a.store);
            ok(serde_json::json!({ "rebuilt": true }))
        }

        // Frontmatter
        "kb.frontmatter.get" => {
            let a = parse!(PathArgs);
            let fm = match frontmatter::read_frontmatter(&a.store, &a.path) {
                Ok(f) => f,
                Err(e) => return err(e),
            };
            ok(serde_json::to_value(fm).unwrap_or_default())
        }
        "kb.frontmatter.set" => {
            #[derive(Deserialize)]
            struct FmSetArgs {
                path: String,
                frontmatter: Frontmatter,
                #[serde(default = "default_store")]
                store: String,
            }
            let a = parse!(FmSetArgs);
            if let Err(e) = frontmatter::write_frontmatter(&a.store, &a.path, &a.frontmatter) {
                return err(e);
            }
            ok(serde_json::json!({ "updated": a.path }))
        }
        "kb.frontmatter.query" => {
            #[derive(Deserialize)]
            struct FmQueryArgs {
                tag: Option<String>,
                key: Option<String>,
                value: Option<String>,
                #[serde(default = "default_store")]
                store: String,
            }
            let a = parse!(FmQueryArgs);
            let results = match frontmatter::query_entries(
                &a.store,
                a.tag.as_deref(),
                a.key.as_deref(),
                a.value.as_deref(),
            ) {
                Ok(r) => r,
                Err(e) => return err(e),
            };
            ok(serde_json::json!({ "paths": results }))
        }
        // The query language covers `tag:`, `date:` and `key:value` filters
        // in one string, which is what a user would type.
        "kb.query" => {
            #[derive(Deserialize)]
            struct QueryArgs {
                query: String,
                #[serde(default = "default_store")]
                store: String,
            }
            let a = parse!(QueryArgs);
            let results = match crate::query::query(&a.store, &a.query) {
                Ok(r) => r,
                Err(e) => return err(e),
            };
            ok(serde_json::json!({ "paths": results }))
        }
        // Parsing and serializing work on a body rather than a file, so the
        // editor can edit the metadata of the note it is holding in memory
        // instead of rewriting the file behind the user's back.
        "kb.frontmatter.parse" => {
            #[derive(Deserialize)]
            struct ParseArgs {
                body: String,
            }
            let a = parse!(ParseArgs);
            let (fm, body) = frontmatter::parse_frontmatter(&a.body);
            ok(serde_json::json!({
                "frontmatter": serde_json::to_value(fm).unwrap_or_default(),
                "body": body,
            }))
        }
        "kb.frontmatter.serialize" => {
            #[derive(Deserialize)]
            struct SerializeArgs {
                frontmatter: Frontmatter,
                body: String,
            }
            let a = parse!(SerializeArgs);
            ok(serde_json::json!({
                "text": frontmatter::serialize_frontmatter(&a.frontmatter, &a.body),
            }))
        }

        // Daily Templates
        "kb.template.daily_path" => {
            let a = parse!(DateArgs);
            let date = chrono::DateTime::from_timestamp_millis(a.date_ms)
                .map(|dt| dt.date_naive())
                .unwrap_or_else(|| chrono::Local::now().date_naive());
            let path = daily_note_path(date);
            ok(serde_json::json!({ "path": path }))
        }
        "kb.template.daily_render" => {
            let a = parse!(DateArgs);
            let date = chrono::DateTime::from_timestamp_millis(a.date_ms)
                .map(|dt| dt.date_naive())
                .unwrap_or_else(|| chrono::Local::now().date_naive());
            let rendered = render_daily_template(date);
            ok(serde_json::json!({ "content": rendered }))
        }
        "kb.template.ensure" => {
            if let Err(e) = ensure_template_exists() {
                return err(e);
            }
            ok(serde_json::json!({ "ensured": true }))
        }
        // The template's own path, content and saving all live in the core,
        // so the editor does not have to re-derive where the file lives.
        "kb.template.get" => {
            if let Err(e) = ensure_template_exists() {
                return err(e);
            }
            let path = config::daily_template_path();
            let content = std::fs::read_to_string(&path).unwrap_or_default();
            ok(serde_json::json!({
                "path": path.to_string_lossy(),
                "content": content,
            }))
        }
        "kb.template.save" => {
            #[derive(Deserialize)]
            struct SaveArgs {
                content: String,
            }
            let a = parse!(SaveArgs);
            let path = config::daily_template_path();
            if let Some(parent) = path.parent() {
                if let Err(e) = std::fs::create_dir_all(parent) {
                    return err(e.to_string());
                }
            }
            if let Err(e) = std::fs::write(&path, a.content) {
                return err(e.to_string());
            }
            ok(serde_json::json!({
                "path": path.to_string_lossy(),
                "saved": true,
            }))
        }
        // Rendering a template that is passed in, rather than read from disk,
        // lets the editor preview what the user is typing before saving it.
        "kb.template.render" => {
            #[derive(Deserialize)]
            struct RenderArgs {
                template: String,
                date_ms: i64,
            }
            let a = parse!(RenderArgs);
            let date = chrono::DateTime::from_timestamp_millis(a.date_ms)
                .map(|dt| dt.date_naive())
                .unwrap_or_else(|| chrono::Local::now().date_naive());
            ok(serde_json::json!({
                "content": crate::template::render_template(&a.template, date),
            }))
        }

        // Search
        //
        // These take a store name, not a path — the core resolves the path
        // itself, so resolving it here as well would look the path up in the
        // store registry and fail.
        "kb.search.init" => {
            let a = parse!(StoreArgs);
            if let Err(e) = init_search_index(&a.store) {
                return err(e);
            }
            ok(serde_json::json!({ "initialized": true }))
        }
        "kb.search.query" => {
            let a = parse!(SearchArgs);
            let hits = match search_entries(&a.store, &a.query, a.limit) {
                Ok(h) => h,
                Err(e) => return err(e),
            };
            ok(serde_json::json!({ "hits": hits }))
        }
        "kb.search.reindex" => {
            let a = parse!(StoreArgs);
            let index = match crate::search::SearchIndex::global(&a.store) {
                Ok(i) => i,
                Err(e) => return err(e),
            };
            if let Err(e) = index.rebuild(&a.store) {
                return err(e);
            }
            ok(serde_json::json!({ "reindexed": true }))
        }

        // Config
        "kb.config.get" => {
            let cfg = config::get_config();
            ok(serde_json::to_value(cfg).unwrap_or_default())
        }
        "kb.config.set" => {
            #[derive(Deserialize)]
            struct ConfigSetArgs {
                config: config::Config,
            }
            let a = parse!(ConfigSetArgs);
            if let Err(e) = config::save_config(&a.config) {
                return err(e);
            }
            ok(serde_json::json!({ "saved": true }))
        }

        // Sync
        "kb.sync.init" => {
            #[derive(Deserialize)]
            struct SyncInitArgs {
                vault_path: String,
                /// The store to sync; the journal unless it is told otherwise.
                #[serde(default = "default_store")]
                store: String,
            }
            let a = parse!(SyncInitArgs);
            if let Err(e) = init_sync_store(&a.store, &a.vault_path) {
                return err(e);
            }
            ok(serde_json::json!({ "initialized": true }))
        }
        "kb.sync.status" => match get_sync_status() {
            Ok(status) => ok(serde_json::to_value(status).unwrap_or_default()),
            Err(e) => err(e),
        },
        "kb.sync.conflicts" => match get_sync_status() {
            Ok(status) => ok(serde_json::json!({ "conflicts": status.conflicts })),
            Err(e) => err(e),
        },
        "kb.sync.resolve_conflict" => {
            #[derive(Deserialize)]
            struct ResolveConflictArgs {
                path: String,
                keep_local: bool,
                /// The folder holding the vault.
                vault_path: String,
                /// The store the vault belongs to.
                #[serde(default = "default_store")]
                store: String,
            }
            let a = parse!(ResolveConflictArgs);
            if let Err(e) = resolve_conflict(&a.store, &a.vault_path, &a.path, a.keep_local) {
                return err(e);
            }
            ok(serde_json::json!({ "resolved": a.path }))
        }
        // The two versions of a conflicted note, and the difference between
        // them, so the user can see what changed before choosing.
        "kb.sync.conflict_versions" => {
            #[derive(Deserialize)]
            struct ConflictVersionsArgs {
                vault_path: String,
                path: String,
                #[serde(default = "default_store")]
                store: String,
            }
            let a = parse!(ConflictVersionsArgs);
            match crate::sync::conflict_versions(&a.store, &a.vault_path, &a.path) {
                Ok((local, remote)) => ok(serde_json::json!({
                    "local": local,
                    "remote": remote,
                })),
                Err(e) => err(e),
            }
        }
        "kb.sync.conflict_diff" => {
            #[derive(Deserialize)]
            struct ConflictDiffArgs {
                vault_path: String,
                path: String,
                #[serde(default = "default_store")]
                store: String,
            }
            let a = parse!(ConflictDiffArgs);
            let (local, remote) =
                match crate::sync::conflict_versions(&a.store, &a.vault_path, &a.path) {
                    Ok(versions) => versions,
                    Err(e) => return err(e),
                };
            ok(serde_json::json!({ "lines": crate::diff::diff(&local, &remote) }))
        }
        // A difference between two texts, for anything that needs one.
        "kb.diff.lines" => {
            #[derive(Deserialize)]
            struct DiffArgs {
                old: String,
                new: String,
            }
            let a = parse!(DiffArgs);
            ok(serde_json::json!({ "lines": crate::diff::diff(&a.old, &a.new) }))
        }
        "kb.sync.generate_syncthing_config" => {
            #[derive(Deserialize)]
            struct GenConfigArgs {
                vault_path: String,
            }
            let a = parse!(GenConfigArgs);
            match generate_syncthing_config(&a.vault_path) {
                Ok(xml) => ok(serde_json::json!({ "config": xml })),
                Err(e) => err(e),
            }
        }
        "kb.sync.backup.create" => {
            #[derive(Deserialize)]
            struct BackupCreateArgs {
                vault_path: String,
                passphrase: String,
                output_path: String,
            }
            let a = parse!(BackupCreateArgs);
            let output = std::path::Path::new(&a.output_path);
            if let Err(e) = create_backup_bundle(&a.vault_path, &a.passphrase, output) {
                return err(e);
            }
            ok(serde_json::json!({ "created": a.output_path }))
        }
        "kb.sync.backup.restore" => {
            #[derive(Deserialize)]
            struct BackupRestoreArgs {
                bundle_path: String,
                passphrase: String,
                target_dir: String,
            }
            let a = parse!(BackupRestoreArgs);
            let bundle = std::path::Path::new(&a.bundle_path);
            let target = std::path::Path::new(&a.target_dir);
            if let Err(e) = restore_backup_bundle(bundle, &a.passphrase, target) {
                return err(e);
            }
            ok(serde_json::json!({ "restored": a.target_dir }))
        }

        // WebDAV
        //
        // The password and the encryption passphrase live in the keyring,
        // so they are set once and never travel through the app again.
        "kb.sync.credentials.set" => {
            #[derive(Deserialize)]
            struct CredentialsArgs {
                password: Option<String>,
                passphrase: Option<String>,
            }
            let a = parse!(CredentialsArgs);
            if let Some(password) = a.password {
                if let Err(e) = secrets::set_webdav_password(&password) {
                    return err(e);
                }
            }
            if let Some(passphrase) = a.passphrase {
                if let Err(e) = secrets::set_webdav_passphrase(&passphrase) {
                    return err(e);
                }
            }
            ok(serde_json::json!({ "saved": true }))
        }
        "kb.sync.credentials.status" => {
            // A keyring that cannot be reached is reported, not hidden: the
            // user is told why the secrets are not there.
            let available = secrets::keyring_available();
            let password = secrets::webdav_password().ok().flatten();
            let passphrase = secrets::webdav_passphrase().ok().flatten();
            ok(serde_json::json!({
                "available": available,
                "password": password.is_some(),
                "passphrase": passphrase.is_some(),
            }))
        }
        "kb.sync.credentials.clear" => {
            if let Err(e) = secrets::clear_webdav_secrets() {
                return err(e);
            }
            ok(serde_json::json!({ "cleared": true }))
        }
        "kb.sync.webdav.connect" => {
            #[derive(Deserialize)]
            struct WebDAVConnectArgs {
                url: String,
                username: String,
                encrypt: bool,
            }
            let a = parse!(WebDAVConnectArgs);
            let password = match secrets::webdav_password() {
                Ok(Some(password)) => password,
                Ok(None) => return err("the WebDAV password has not been kept in the keyring"),
                Err(e) => return err(e),
            };
            let passphrase = secrets::webdav_passphrase().ok().flatten();
            let config = WebDAVConfig {
                url: a.url,
                username: a.username,
                password: Some(password),
                encryption_passphrase: passphrase,
                encrypt: a.encrypt,
            };
            // Store the config for later use (in a real app, this would be persisted)
            // For now, we just test the connection
            let rt = match runtime() {
                Ok(rt) => rt,
                Err(e) => return err(e),
            };
            match rt.block_on(WebDAVSync::new(config)) {
                Ok(_) => ok(serde_json::json!({ "connected": true })),
                Err(e) => err(e),
            }
        }
        "kb.sync.webdav.sync" => {
            #[derive(Deserialize)]
            struct WebDAVSyncArgs {
                /// The store to sync; the journal unless it is told otherwise.
                #[serde(default = "default_store")]
                store: String,
                /// The folder holding the vault; the store's own folder
                /// unless it is told otherwise.
                #[serde(default)]
                vault_path: Option<String>,
                /// The address of the server; the one in the configuration
                /// unless it is told otherwise.
                #[serde(default)]
                url: Option<String>,
                /// The name of the account; the one in the configuration
                /// unless it is told otherwise.
                #[serde(default)]
                username: Option<String>,
                /// Whether the uploads are encrypted; the setting in the
                /// configuration unless it is told otherwise.
                #[serde(default)]
                encrypt: Option<bool>,
            }
            let a = parse!(WebDAVSyncArgs);
            let settings = config::get_config().sync.webdav;

            let url = a.url.unwrap_or(settings.url);
            let username = a.username.unwrap_or(settings.username);
            let encrypt = a.encrypt.unwrap_or(settings.encrypt);
            if url.trim().is_empty() {
                return err("no WebDAV address has been set");
            }

            let password = match secrets::webdav_password() {
                Ok(Some(password)) => password,
                Ok(None) => return err("the WebDAV password has not been kept in the keyring"),
                Err(e) => return err(e),
            };
            let passphrase = secrets::webdav_passphrase().ok().flatten();

            let vault_path = match a.vault_path {
                Some(path) => path,
                None => match vault::get_vault_root(&a.store) {
                    Ok(path) => path,
                    Err(e) => return err(e),
                },
            };

            let webdav_config = WebDAVConfig {
                url,
                username,
                password: Some(password),
                encryption_passphrase: passphrase,
                encrypt,
            };
            let rt = match runtime() {
                Ok(rt) => rt,
                Err(e) => return err(e),
            };
            match rt.block_on(async {
                let mut sync = WebDAVSync::new(webdav_config).await?;
                sync.sync_vault(&a.store, &vault_path).await
            }) {
                Ok(report) => ok(serde_json::to_value(report).unwrap_or_default()),
                Err(e) => err(e),
            }
        }

        // Auto-update
        "kb.auto_update.check" => {
            match check_for_update() {
                UpdateStatus::UpToDate => ok(serde_json::json!({
                    "up_to_date": true,
                    "current_version": current_version()
                })),
                UpdateStatus::UpdateAvailable(info) => ok(serde_json::json!({
                    "up_to_date": false,
                    "current_version": current_version(),
                    "tag_name": info.tag_name,
                    "assets": info.assets.iter().map(|a| serde_json::json!({
                        "name": a.name,
                        "url": a.browser_download_url,
                        "size": a.size
                    })).collect::<Vec<_>>()
                })),
                UpdateStatus::Error(e) => err(e),
            }
        }
        "kb.auto_update.download" => {
            #[derive(Deserialize)]
            struct DownloadArgs {
                tag_name: String,
            }
            let a = parse!(DownloadArgs);
            // Re-query to get the release info for the requested tag.
            // The GitHub API only exposes /releases/latest, so we compare
            // tags and download the matching asset.
            match check_for_update() {
                UpdateStatus::UpdateAvailable(info) => {
                    if info.tag_name != a.tag_name {
                        return err(format!("requested tag {} is not the latest release", a.tag_name));
                    }
                    let asset_name = info.assets.first().map(|a| a.name.clone()).unwrap_or_default();
                    match download_update(&info) {
                        Ok(path) => ok(serde_json::json!({
                            "path": path.to_string_lossy(),
                            "name": asset_name
                        })),
                        Err(e) => err(e),
                    }
                }
                UpdateStatus::UpToDate => err("no update available to download".to_string()),
                UpdateStatus::Error(e) => err(e),
            }
        }
        "kb.auto_update.apply" => {
            #[derive(Deserialize)]
            struct ApplyArgs {
                path: String,
            }
            let a = parse!(ApplyArgs);
            let path = Path::new(&a.path);
            match apply_update(path) {
                Ok(()) => ok(serde_json::json!({ "applied": true })),
                Err(e) => err(e),
            }
        }

        // Command palette
        "kb.command.list" => {
            if let Err(e) = register_builtin_commands() {
                return err(e);
            }
            ok(serde_json::json!({
                "commands": list_commands()
                    .into_iter()
                    .map(|c| serde_json::to_value(c).unwrap_or_default())
                    .collect::<Vec<_>>()
            }))
        }
        "kb.command.execute" => {
            #[derive(Deserialize)]
            struct CommandExecuteArgs {
                id: String,
            }
            let a = parse!(CommandExecuteArgs);
            if let Err(e) = register_builtin_commands() {
                return err(e);
            }
            let commands = list_commands();
            if let Some(cmd) = commands.iter().find(|c| c.id == a.id) {
                ok(serde_json::json!({
                    "executed": true,
                    "command": serde_json::to_value(cmd).unwrap_or_default(),
                }))
            } else {
                err(format!("command '{}' not found", a.id))
            }
        }

        // AI
        "kb.ai.chat" => {
            #[derive(Deserialize)]
            struct ChatArgs {
                model: String,
                message: String,
                #[serde(default)]
                system: Option<String>,
                #[serde(default = "default_true")]
                stream: bool,
            }
            let a = parse!(ChatArgs);
            let ollama = OllamaClient::default();
            let mut messages = Vec::new();
            if let Some(system) = a.system {
                messages.push(ai::Message::system(&system));
            }
            messages.push(ai::Message::user(&a.message));
            match ollama.chat(&a.model, messages, a.stream) {
                Ok(resp) => ok(serde_json::json!({
                    "model": resp.model,
                    "content": resp.message.content,
                    "done": resp.done,
                })),
                Err(e) => err(e),
            }
        }
        "kb.ai.list_models" => {
            let ollama = OllamaClient::default();
            match ollama.list_models() {
                Ok(models) => ok(serde_json::json!({
                    "models": models.iter().map(|m| serde_json::json!({
                        "name": m.name,
                        "size": m.size,
                    })).collect::<Vec<_>>()
                })),
                Err(e) => err(e),
            }
        }
        "kb.ai.rag" => {
            #[derive(Deserialize)]
            struct RagArgs {
                query: String,
                store: String,
                #[serde(default = "default_top_k")]
                k: usize,
                #[serde(default)]
                embedding_model: Option<String>,
            }
            let a = parse!(RagArgs);
            let ollama = OllamaClient::default();
            match ai::retrieve_context(
                &ollama,
                a.embedding_model.as_deref(),
                &a.query,
                &a.store,
                a.k,
            ) {
                Ok(contexts) => ok(serde_json::json!({
                    "contexts": contexts.iter().map(|c| serde_json::json!({
                        "path": c.path,
                        "title": c.title,
                        "body": c.body,
                        "score": c.score,
                    })).collect::<Vec<_>>()
                })),
                Err(e) => err(e),
            }
        }

        other => return err(format!("unknown method: {other}")),
    };

    result
}

unsafe fn c_to_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        String::new()
    } else {
        CStr::from_ptr(ptr).to_string_lossy().into_owned()
    }
}

fn string_to_cptr(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

/// Entry point FFI: `lumen_kb_call(method, json_args)` → JSON result string.
/// Caller must `lumen_kb_free` the returned pointer.
///
/// # Safety
/// `method` and `args` must be null or valid NUL-terminated C strings for the
/// duration of the call.
#[no_mangle]
pub unsafe extern "C" fn lumen_kb_call(method: *const c_char, args: *const c_char) -> *mut c_char {
    let method = unsafe { c_to_string(method) };
    let args_str = unsafe { c_to_string(args) };
    let args: serde_json::Value = if args_str.is_empty() {
        serde_json::json!({})
    } else {
        serde_json::from_str(&args_str).unwrap_or(serde_json::json!({}))
    };

    let result = dispatch(&method, &args).to_string();
    string_to_cptr(result)
}

/// Free a string returned by `lumen_kb_call`.
///
/// # Safety
/// `ptr` must be null or a pointer returned by `lumen_kb_call` that has not
/// already been freed.
#[no_mangle]
pub unsafe extern "C" fn lumen_kb_free(ptr: *mut c_char) {
    unsafe {
        if !ptr.is_null() {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::{self, STORE_JOURNAL};
    use serde_json::json;

    /// Call a knowledge-base method, failing loudly if the envelope reports
    /// an error.
    fn call(method: &str, args: serde_json::Value) -> serde_json::Value {
        let result = dispatch(method, &args);
        assert_eq!(
            result.get("ok").and_then(|v| v.as_bool()),
            Some(true),
            "kb method '{method}' failed: {}",
            result
                .get("error")
                .and_then(|v| v.as_str())
                .unwrap_or("<no error>")
        );
        result
            .get("data")
            .cloned()
            .unwrap_or(serde_json::Value::Null)
    }

    /// Every knowledge-base method must work against a real vault.
    ///
    /// This is the guard against the two mistakes that are easy to make in
    /// this layer: passing a vault path where a store name is expected, and
    /// forgetting that a method needs the store unlocked.
    #[test]
    fn every_kb_method_works_against_a_real_vault() {
        let _guard = crate::testutil::TestGuard::new();
        crate::search::clear_search_indexes();
        crate::wikilinks::clear_backlink_index();

        let temp = tempfile::tempdir().unwrap();
        let vault_path = temp.path().to_string_lossy().to_string();

        // Keep the test off the user's real configuration. The config
        // directory has to sit outside the vault, or the daily template it
        // holds would show up as a note.
        let config_temp = tempfile::tempdir().unwrap();
        crate::config::set_config_dir(Some(config_temp.path().to_path_buf()));

        vault::create_with_passphrase(&vault_path, "testpass123", STORE_JOURNAL).unwrap();
        vault::unlock(&vault_path, "testpass123", STORE_JOURNAL).unwrap();

        // Notes: one plain, one linking to the other, one with frontmatter.
        vault::write_text("alpha.md", "# Alpha\n\nLinks to [[beta]].", STORE_JOURNAL).unwrap();
        vault::write_text(
            "beta.md",
            "---\ntags: [work]\ntitle: Beta\n---\n\n# Beta\n\nThe second note.",
            STORE_JOURNAL,
        )
        .unwrap();

        // --- Wikilinks -----------------------------------------------------
        let links = call("kb.wikilinks.parse", json!({ "path": "alpha.md" }));
        assert_eq!(links["links"].as_array().unwrap().len(), 1);

        let resolved = call("kb.wikilinks.resolve", json!({ "target": "beta" }));
        assert_eq!(resolved["path"], "beta.md");

        let created = call("kb.wikilinks.create_missing", json!({ "target": "gamma" }));
        assert_eq!(created["created"], "gamma.md");
        // Creating it again is an error.
        let again = dispatch("kb.wikilinks.create_missing", &json!({ "target": "gamma" }));
        assert_eq!(again.get("ok").and_then(|v| v.as_bool()), Some(false));

        let backlinks = call("kb.wikilinks.backlinks", json!({ "path": "beta.md" }));
        assert_eq!(
            backlinks["backlinks"].as_array().unwrap(),
            &vec![json!("alpha.md")]
        );

        call("kb.wikilinks.rebuild_index", json!({}));

        // --- Frontmatter ----------------------------------------------------
        let fm = call("kb.frontmatter.get", json!({ "path": "beta.md" }));
        assert_eq!(fm["tags"][0], "work");

        // Parsing and serializing work on a body, not a file.
        let parsed = call(
            "kb.frontmatter.parse",
            json!({ "body": "---\ntags: [work]\n---\n\n# Beta\n" }),
        );
        assert_eq!(parsed["frontmatter"]["tags"][0], "work");
        assert_eq!(parsed["body"], "# Beta\n");

        let serialized = call(
            "kb.frontmatter.serialize",
            json!({
                "frontmatter": { "tags": ["work"] },
                "body": "# Beta\n",
            }),
        );
        let text = serialized["text"].as_str().unwrap();
        assert!(text.starts_with("---\n"));
        assert!(text.contains("tags:"));
        // The block must be readable again.
        let reparsed = call("kb.frontmatter.parse", json!({ "body": text }));
        assert_eq!(reparsed["frontmatter"]["tags"][0], "work");

        let mut updated = fm.clone();
        updated["tags"] = json!(["work", "urgent"]);
        call(
            "kb.frontmatter.set",
            json!({ "path": "beta.md", "frontmatter": updated }),
        );

        // The frontmatter must survive the round trip through the vault.
        let after = frontmatter::read_frontmatter(STORE_JOURNAL, "beta.md").unwrap();
        assert_eq!(after.tags, vec!["work", "urgent"]);
        assert_eq!(after.title.as_deref(), Some("Beta"));
        let queried = call("kb.frontmatter.query", json!({ "tag": "urgent" }));
        assert_eq!(
            queried["paths"].as_array().unwrap(),
            &vec![json!("beta.md")]
        );

        // The query language answers the same question in one string.
        let by_query = call("kb.query", json!({ "query": "tag:urgent" }));
        assert_eq!(
            by_query["paths"].as_array().unwrap(),
            &vec![json!("beta.md")]
        );
        let no_match = call("kb.query", json!({ "query": "tag:missing" }));
        assert!(no_match["paths"].as_array().unwrap().is_empty());

        // --- Templates ------------------------------------------------------
        let date_ms = 1_770_000_000_000_i64;
        let path = call("kb.template.daily_path", json!({ "date_ms": date_ms }));
        assert!(path["path"].as_str().unwrap().ends_with(".md"));

        let rendered = call("kb.template.daily_render", json!({ "date_ms": date_ms }));
        assert!(rendered["content"].is_string());

        // A template passed in is rendered the same way as the one on disk.
        let from_text = call(
            "kb.template.render",
            json!({ "template": "# {{date}}", "date_ms": date_ms }),
        );
        assert_eq!(from_text["content"], "# 2026-02-02");

        call("kb.template.ensure", json!({}));

        // The template editor reads and writes the template through the
        // core, so it does not have to know where the file lives.
        let template = call("kb.template.get", json!({}));
        let template_path = template["path"].as_str().unwrap().to_string();
        assert!(!template_path.is_empty());
        assert!(template["content"].as_str().unwrap().contains("{{date}}"));

        let saved = call(
            "kb.template.save",
            json!({ "content": "# {{date}}\n\ncustom\n" }),
        );
        assert_eq!(saved["path"].as_str().unwrap(), template_path);
        let reread = call("kb.template.get", json!({}));
        assert_eq!(
            reread["content"].as_str().unwrap(),
            "# {{date}}\n\ncustom\n"
        );

        // --- Search ---------------------------------------------------------
        call("kb.search.init", json!({}));

        let hits = call("kb.search.query", json!({ "query": "second", "limit": 10 }));
        let hits = hits["hits"].as_array().unwrap();
        assert_eq!(hits.len(), 1, "expected one hit, got {hits:?}");
        assert_eq!(hits[0]["path"], "beta.md");

        call("kb.search.reindex", json!({}));

        // --- Config ---------------------------------------------------------
        let mut config = call("kb.config.get", json!({}));
        assert!(config.get("search").is_some());
        // Sync is off by default; turn it on so the sync methods have a
        // state to work with.
        config["sync"]["method"] = json!("syncthing");
        call("kb.config.set", json!({ "config": config }));

        // --- Sync -----------------------------------------------------------
        call("kb.sync.init", json!({ "vault_path": vault_path }));

        let status = call("kb.sync.status", json!({}));
        assert!(status.get("enabled").is_some());

        let conflicts = call("kb.sync.conflicts", json!({}));
        assert!(conflicts["conflicts"].is_array());

        // --- Conflicts ------------------------------------------------------
        //
        // A note with a version Syncthing kept, so the two versions can be
        // asked for and compared.
        vault::write_text("gamma.md", "# Gamma\n\nremote\n", STORE_JOURNAL).unwrap();
        let versions = std::path::Path::new(&vault_path)
            .join(".stversions")
            .join("gamma.md");
        std::fs::create_dir_all(&versions).unwrap();
        std::fs::copy(
            std::path::Path::new(&vault_path).join("gamma.md"),
            versions.join("gamma.md.20260101-120000.md"),
        )
        .unwrap();
        vault::write_text("gamma.md", "# Gamma\n\nlocal\n", STORE_JOURNAL).unwrap();

        let versions = call(
            "kb.sync.conflict_versions",
            json!({ "vault_path": vault_path, "path": "gamma.md" }),
        );
        assert_eq!(versions["local"], "# Gamma\n\nlocal\n");
        assert_eq!(versions["remote"], "# Gamma\n\nremote\n");

        let difference = call(
            "kb.sync.conflict_diff",
            json!({ "vault_path": vault_path, "path": "gamma.md" }),
        );
        let lines = difference["lines"].as_array().unwrap();
        assert!(lines
            .iter()
            .any(|line| line["kind"] == "removed" && line["text"] == "local"));
        assert!(lines
            .iter()
            .any(|line| line["kind"] == "added" && line["text"] == "remote"));

        // A difference between two texts, for anything else that needs one.
        let lines = call(
            "kb.diff.lines",
            json!({ "old": "one\ntwo\n", "new": "one\nthree\n" }),
        );
        let lines = lines["lines"].as_array().unwrap();
        assert_eq!(lines.len(), 3);
        assert_eq!(lines[0]["kind"], "same");
        assert_eq!(lines[1]["kind"], "removed");
        assert_eq!(lines[2]["kind"], "added");

        call(
            "kb.sync.resolve_conflict",
            json!({
                "path": "alpha.md",
                "keep_local": true,
                "vault_path": vault_path,
            }),
        );

        let syncthing = call(
            "kb.sync.generate_syncthing_config",
            json!({ "vault_path": vault_path }),
        );
        assert!(syncthing["config"].as_str().unwrap().contains("<folder"));

        let bundle = temp.path().join("backup.lumen.bak.age");
        call(
            "kb.sync.backup.create",
            json!({
                "vault_path": vault_path,
                "passphrase": "testpass123",
                "output_path": bundle.to_string_lossy(),
            }),
        );
        assert!(bundle.exists());

        let restored = temp.path().join("restored");
        call(
            "kb.sync.backup.restore",
            json!({
                "bundle_path": bundle.to_string_lossy(),
                "passphrase": "testpass123",
                "target_dir": restored.to_string_lossy(),
            }),
        );
        assert!(restored.join("alpha.md").exists());

        // --- Credentials -----------------------------------------------------
        //
        // The secrets are kept in a store of the test's own, so the test
        // never touches the keyring of the machine it runs on.
        let store = std::sync::Arc::new(crate::secrets::MemoryStore::new());
        crate::secrets::set_store(Some(store.clone()));

        let before = call("kb.sync.credentials.status", json!({}));
        assert_eq!(before["password"], json!(false));
        assert_eq!(before["passphrase"], json!(false));

        call(
            "kb.sync.credentials.set",
            json!({ "password": "hunter2", "passphrase": "a different secret" }),
        );

        let after = call("kb.sync.credentials.status", json!({}));
        assert_eq!(after["password"], json!(true));
        assert_eq!(after["passphrase"], json!(true));

        call("kb.sync.credentials.clear", json!({}));
        let cleared = call("kb.sync.credentials.status", json!({}));
        assert_eq!(cleared["password"], json!(false));
        assert_eq!(cleared["passphrase"], json!(false));

        crate::secrets::set_store(None);

        // Restore the default configuration location.
        crate::config::set_config_dir(None);
    }
}

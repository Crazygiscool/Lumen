//! FFI entry points for knowledge base features.
//!
//! `lumen_kb_call(method, json_args) -> json_result`
//! Result envelope: `{ "ok": bool, "data": <value>, "error": <string> }`.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use serde::Deserialize;

use crate::config;
use crate::frontmatter::{self, Frontmatter};
use crate::graph::{build_graph_data, filter_graph_data, get_note_neighborhood};
use crate::search::{init_search_index, search_entries};
use crate::sync::{
    create_backup_bundle,
    generate_syncthing_config,
    get_sync_status,
    init_sync,
    resolve_conflict,
    restore_backup_bundle,
    webdav::{WebDAVConfig, WebDAVSync},
};
use crate::template::{render_daily_template, daily_note_path, ensure_template_exists};
use crate::vault::{self, STORE_JOURNAL};
use crate::wikilinks::{Wikilink, parse_wikilinks, get_backlinks, resolve_wikilink, init_backlink_index};

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

#[derive(Deserialize)]
struct GraphFilterArgs {
    #[serde(default)]
    tags: Vec<String>,
    query: Option<String>,
    #[serde(default = "default_store")]
    store: String,
}

#[derive(Deserialize)]
struct NeighborhoodArgs {
    center: String,
    depth: usize,
    #[serde(default = "default_store")]
    store: String,
}

fn default_max() -> usize {
    50
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
            ok(serde_json::json!({ "links": links.iter().map(wikilink_to_json).collect::<Vec<_>>() }))
        }
        "kb.wikilinks.resolve" => {
            let a = parse!(WikilinkArgs);
            let resolved = resolve_wikilink(&a.store, &a.target);
            ok(serde_json::json!({ "path": resolved }))
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

        // Graph
        "kb.graph.data" => {
            let a = parse!(StoreArgs);
            let graph = match build_graph_data(&a.store) {
                Ok(g) => g,
                Err(e) => return err(e),
            };
            ok(serde_json::to_value(graph).unwrap_or_default())
        }
        "kb.graph.filter" => {
            let a = parse!(GraphFilterArgs);
            let graph = match build_graph_data(&a.store) {
                Ok(g) => g,
                Err(e) => return err(e),
            };
            let filtered = filter_graph_data(graph, &a.tags, a.query.as_deref());
            ok(serde_json::to_value(filtered).unwrap_or_default())
        }
        "kb.graph.neighborhood" => {
            let a = parse!(NeighborhoodArgs);
            let graph = match get_note_neighborhood(&a.store, &a.center, a.depth) {
                Ok(g) => g,
                Err(e) => return err(e),
            };
            ok(serde_json::to_value(graph).unwrap_or_default())
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
            }
            let a = parse!(SyncInitArgs);
            if let Err(e) = init_sync(&a.vault_path) {
                return err(e);
            }
            ok(serde_json::json!({ "initialized": true }))
        }
        "kb.sync.status" => {
            match get_sync_status() {
                Ok(status) => ok(serde_json::to_value(status).unwrap_or_default()),
                Err(e) => err(e),
            }
        }
        "kb.sync.conflicts" => {
            match get_sync_status() {
                Ok(status) => ok(serde_json::json!({ "conflicts": status.conflicts })),
                Err(e) => err(e),
            }
        }
        "kb.sync.resolve_conflict" => {
            #[derive(Deserialize)]
            struct ResolveConflictArgs {
                path: String,
                keep_local: bool,
            }
            let a = parse!(ResolveConflictArgs);
            if let Err(e) = resolve_conflict(&a.path, a.keep_local) {
                return err(e);
            }
            ok(serde_json::json!({ "resolved": a.path }))
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
        "kb.sync.webdav.connect" => {
            #[derive(Deserialize)]
            struct WebDAVConnectArgs {
                url: String,
                username: String,
                password: String,
                encrypt: bool,
            }
            let a = parse!(WebDAVConnectArgs);
            let config = WebDAVConfig {
                url: a.url,
                username: a.username,
                password: Some(a.password),
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
                vault_path: String,
                url: String,
                username: String,
                password: String,
                encrypt: bool,
            }
            let a = parse!(WebDAVSyncArgs);
            let config = WebDAVConfig {
                url: a.url,
                username: a.username,
                password: Some(a.password),
                encrypt: a.encrypt,
            };
            let rt = match runtime() {
                Ok(rt) => rt,
                Err(e) => return err(e),
            };
            match rt.block_on(async {
                let mut sync = WebDAVSync::new(config).await?;
                sync.sync_to_webdav(&a.vault_path).await
            }) {
                Ok(_) => ok(serde_json::json!({ "synced": true })),
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
pub unsafe extern "C" fn lumen_kb_call(
    method: *const c_char,
    args: *const c_char,
) -> *mut c_char {
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
        result.get("data").cloned().unwrap_or(serde_json::Value::Null)
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
        assert_eq!(queried["paths"].as_array().unwrap(), &vec![json!("beta.md")]);

        // --- Templates ------------------------------------------------------
        let date_ms = 1_770_000_000_000_i64;
        let path = call("kb.template.daily_path", json!({ "date_ms": date_ms }));
        assert!(path["path"].as_str().unwrap().ends_with(".md"));

        let rendered = call("kb.template.daily_render", json!({ "date_ms": date_ms }));
        assert!(rendered["content"].is_string());

        call("kb.template.ensure", json!({}));

        // --- Search ---------------------------------------------------------
        call("kb.search.init", json!({}));

        let hits = call("kb.search.query", json!({ "query": "second", "limit": 10 }));
        let hits = hits["hits"].as_array().unwrap();
        assert_eq!(hits.len(), 1, "expected one hit, got {hits:?}");
        assert_eq!(hits[0]["path"], "beta.md");

        call("kb.search.reindex", json!({}));

        // --- Graph ----------------------------------------------------------
        let graph = call("kb.graph.data", json!({}));
        assert_eq!(graph["nodes"].as_array().unwrap().len(), 2);

        let filtered = call("kb.graph.filter", json!({ "tags": ["work"] }));
        assert_eq!(filtered["nodes"].as_array().unwrap().len(), 1);

        let neighborhood = call(
            "kb.graph.neighborhood",
            json!({ "center": "alpha.md", "depth": 1 }),
        );
        assert!(!neighborhood["nodes"].as_array().unwrap().is_empty());

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

        call(
            "kb.sync.resolve_conflict",
            json!({ "path": "alpha.md", "keep_local": true }),
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

        // Restore the default configuration location.
        crate::config::set_config_dir(None);
    }
}
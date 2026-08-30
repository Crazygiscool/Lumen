pub mod manifest;
pub mod loader;
pub mod ffi;
pub mod builtin;
pub(crate) mod plugin_trait;

pub use plugin_trait::Plugin;
pub use manifest::PluginManifest;
pub use loader::{scan_plugins, inventory, LoadedPlugin};

use std::collections::HashSet;
use std::sync::Mutex;

use lazy_static::lazy_static;

use crate::entry::JournalEntry;

lazy_static! {
    /// Runtime enable/disable state for plugins, shared across the FFI and the
    /// TUI/CLI. Missing names count as enabled.
    static ref ENABLED: Mutex<Option<HashSet<String>>> = Mutex::new(None);
}

/// Returns true while [name] is not explicitly disabled.
pub fn is_enabled(name: &str) -> bool {
    let guard = ENABLED.lock().unwrap();
    match guard.as_ref() {
        Some(set) => set.contains(name),
        None => true,
    }
}

/// Sets whether plugin [name] runs. Serves the Plugins screen toggles.
pub fn set_enabled(name: &str, enabled: bool) {
    let mut guard = ENABLED.lock().unwrap();
    let set = guard.get_or_insert_with(HashSet::new);
    if enabled {
        set.insert(name.to_string());
    } else {
        set.remove(name);
    }
}

/// Metadata for the built-in plugins (kept in sync with PluginManager::new).
pub fn builtins_metadata() -> Vec<PluginManifest> {
    vec![
        PluginManifest {
            name: "export_md".into(),
            version: "1.0.0".into(),
            author: Some("Lumen".into()),
            description: Some("Exports journal entries to Markdown.".into()),
            hooks: ["on_export"].into_iter().map(String::from).collect(),
        },
        PluginManifest {
            name: "daily_summary".into(),
            version: "1.0.0".into(),
            author: Some("Lumen".into()),
            description: Some("Summarises each day's journal activity.".into()),
            hooks: ["on_entry"].into_iter().map(String::from).collect(),
        },
        PluginManifest {
            name: "wordcount".into(),
            version: "1.0.0".into(),
            author: Some("Lumen".into()),
            description: Some("Estimates word count from entry length.".into()),
            hooks: ["on_entry"].into_iter().map(String::from).collect(),
        },
    ]
}

pub struct PluginManager {
    builtins: Vec<(&'static str, Box<dyn Plugin>)>,
    externals: Vec<LoadedPlugin>,
}

impl PluginManager {
    pub fn new() -> Self {
        let mut builtins: Vec<(&'static str, Box<dyn Plugin>)> = Vec::new();
        builtins.push(("export_md", Box::new(builtin::export_md::ExportMdPlugin)));
        builtins.push((
            "daily_summary",
            Box::new(builtin::daily_summary::DailySummaryPlugin),
        ));
        builtins.push(("wordcount", Box::new(builtin::wordcount::WordCountPlugin)));

        let plugins_dir = crate::paths::plugins_dir();
        let externals = if plugins_dir.exists() {
            scan_plugins(&plugins_dir)
        } else {
            Vec::new()
        };

        PluginManager { builtins, externals }
    }

    pub fn register_plugin(&mut self, name: &'static str, plugin: Box<dyn Plugin>) {
        self.builtins.push((name, plugin));
    }

    pub fn run_on_entry(&self, entry: &JournalEntry) -> Vec<String> {
        let mut feedback = Vec::new();

        for (name, plugin) in &self.builtins {
            if !is_enabled(name) {
                continue;
            }
            if let Some(msg) = plugin.on_entry(entry) {
                feedback.push(msg);
            }
        }

        for loaded in &self.externals {
            let name = &loaded.manifest.name;
            if !is_enabled(name) {
                continue;
            }
            // Dynamic plugins loaded via libloading — safety: symbols resolved at runtime
            let on_entry: libloading::Symbol<unsafe extern "C" fn(
                *const std::ffi::c_char,
            ) -> *mut std::ffi::c_char> = unsafe {
                match loaded.lib.get(b"lumen_plugin_on_entry") {
                    Ok(sym) => sym,
                    Err(_) => continue,
                }
            };

            let id_cstr = std::ffi::CString::new(entry.id.as_str()).unwrap();
            let result_ptr = unsafe { on_entry(id_cstr.as_ptr()) };
            if !result_ptr.is_null() {
                let msg = unsafe { std::ffi::CStr::from_ptr(result_ptr) }
                    .to_string_lossy()
                    .into_owned();
                feedback.push(format!("[{}] {}", name, msg));
                unsafe { let _ = std::ffi::CString::from_raw(result_ptr); }
            }
        }

        feedback
    }
}
pub mod builtin;
pub mod ffi;
pub mod loader;
pub mod manifest;
pub(crate) mod plugin_trait;

pub use loader::{inventory, scan_plugins, LoadedPlugin};
pub use manifest::PluginManifest;
pub use plugin_trait::NoteContext;
pub use plugin_trait::Plugin;

use std::collections::HashSet;
use std::sync::Mutex;

use lazy_static::lazy_static;

lazy_static! {
    /// Plugins explicitly disabled at runtime. Everything else is enabled, so
    /// a fresh process starts with built-ins on.
    static ref DISABLED: Mutex<HashSet<String>> = Mutex::new(HashSet::new());
}

/// Returns true while [name] is not explicitly disabled.
pub fn is_enabled(name: &str) -> bool {
    !DISABLED.lock().unwrap().contains(name)
}

/// Sets whether plugin [name] runs. Serves the Plugins screen toggles.
pub fn set_enabled(name: &str, enabled: bool) {
    let mut disabled = DISABLED.lock().unwrap();
    if enabled {
        disabled.remove(name);
    } else {
        disabled.insert(name.to_string());
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
            description: Some("Summarises saved notes with a word count.".into()),
            hooks: ["on_note"].into_iter().map(String::from).collect(),
        },
        PluginManifest {
            name: "wordcount".into(),
            version: "1.0.0".into(),
            author: Some("Lumen".into()),
            description: Some("Counts words in saved notes.".into()),
            hooks: ["on_note"].into_iter().map(String::from).collect(),
        },
    ]
}

pub struct PluginManager {
    builtins: Vec<(&'static str, Box<dyn Plugin>)>,
    externals: Vec<LoadedPlugin>,
}

impl Default for PluginManager {
    fn default() -> Self {
        Self::new()
    }
}

impl PluginManager {
    pub fn new() -> Self {
        let builtins: Vec<(&'static str, Box<dyn Plugin>)> = vec![
            ("export_md", Box::new(builtin::export_md::ExportMdPlugin)),
            (
                "daily_summary",
                Box::new(builtin::daily_summary::DailySummaryPlugin),
            ),
            ("wordcount", Box::new(builtin::wordcount::WordCountPlugin)),
        ];

        let plugins_dir = crate::paths::plugins_dir();
        let externals = if plugins_dir.exists() {
            scan_plugins(&plugins_dir)
        } else {
            Vec::new()
        };

        PluginManager {
            builtins,
            externals,
        }
    }

    pub fn register_plugin(&mut self, name: &'static str, plugin: Box<dyn Plugin>) {
        self.builtins.push((name, plugin));
    }

    pub fn run_on_note(&self, note: &NoteContext<'_>) -> Vec<String> {
        let mut feedback = Vec::new();

        for (name, plugin) in &self.builtins {
            if !is_enabled(name) {
                continue;
            }
            if let Some(msg) = plugin.on_note(note) {
                feedback.push(msg);
            }
        }

        for loaded in &self.externals {
            let name = &loaded.manifest.name;
            if !is_enabled(name) {
                continue;
            }
            // Dynamic plugins loaded via libloading — safety: symbols resolved at runtime
            let on_entry: libloading::Symbol<
                unsafe extern "C" fn(*const std::ffi::c_char) -> *mut std::ffi::c_char,
            > = unsafe {
                match loaded.lib.get(b"lumen_plugin_on_entry") {
                    Ok(sym) => sym,
                    Err(_) => continue,
                }
            };

            let id_cstr = std::ffi::CString::new(note.id).unwrap_or_default();
            let result_ptr = unsafe { on_entry(id_cstr.as_ptr()) };
            if !result_ptr.is_null() {
                let msg = unsafe { std::ffi::CStr::from_ptr(result_ptr) }
                    .to_string_lossy()
                    .into_owned();
                feedback.push(format!("[{}] {}", name, msg));
                unsafe {
                    let _ = std::ffi::CString::from_raw(result_ptr);
                }
            }
        }

        feedback
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disabling_one_plugin_keeps_others_enabled() {
        set_enabled("test-plugin-a", false);
        assert!(!is_enabled("test-plugin-a"));
        assert!(is_enabled("test-plugin-b"));

        set_enabled("test-plugin-a", true);
        assert!(is_enabled("test-plugin-a"));
    }
}

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
            name: "dashboard_entries".into(),
            version: "1.0.0".into(),
            author: Some("Lumen".into()),
            description: Some("Built-in dashboard and journal presentation plugin.".into()),
            hooks: ["on_note"].into_iter().map(String::from).collect(),
            priority: 10,
            plugin_id: Some("dashboard_entries".into()),
            contributes: serde_json::Value::Null,
            ..Default::default()
        },
        PluginManifest {
            name: "theme_manager".into(),
            version: "1.0.0".into(),
            author: Some("Lumen".into()),
            description: Some("Built-in theme management plugin.".into()),
            hooks: ["on_settings"].into_iter().map(String::from).collect(),
            priority: 5,
            plugin_id: Some("theme_manager".into()),
            contributes: serde_json::json!({
                "screens": [
                    { "id": "theme_manager", "label": "Theme manager", "icon": "settings", "template": "theme", "title": "Theme manager" }
                ],
                "fonts": [
                    { "family": "Lumen Theme", "path": "fonts/manager.ttf", "optional": true }
                ],
                "theme": {
                    "applyByDefault": false,
                    "primary": "#8B9CFF",
                    "fontFamily": "Lumen Theme"
                }
            }),
            ..Default::default()
        },
        PluginManifest {
            name: "import_export".into(),
            version: "1.0.0".into(),
            author: Some("Lumen".into()),
            description: Some("Import and export journal data through a plugin-provided screen.".into()),
            hooks: ["on_export"].into_iter().map(String::from).collect(),
            priority: 7,
            plugin_id: Some("import_export".into()),
            contributes: serde_json::json!({
                "sidebar": [
                    { "id": "import_export.import", "label": "Import/Export", "icon": "import", "action": "screen:import_export", "priority": 9 }
                ],
                "screens": [
                    { "id": "import_export", "label": "Import & export", "icon": "import", "template": "import", "title": "Import & export" }
                ],
                "fonts": [
                    { "family": "Import Mono", "path": "fonts/import-mono.ttf", "optional": true }
                ]
            }),
            ..Default::default()
        },
        PluginManifest {
            name: "aurora_theme".into(),
            version: "1.0.0".into(),
            author: Some("Lumen".into()),
            description: Some("A soft aurora-inspired built-in theme.".into()),
            hooks: HashSet::new(),
            priority: 3,
            plugin_id: Some("aurora_theme".into()),
            contributes: serde_json::json!({
                "theme": {
                    "applyByDefault": false,
                    "primary": "#9FD0FF",
                    "primaryContainer": "#1B3A6B",
                    "onPrimaryContainer": "#DCEBFF",
                    "secondary": "#BDA9FF",
                    "background": "#070B14",
                    "surfaceLow": "#101826",
                    "surfaceContainer": "#152033",
                    "surfaceHigh": "#1C2A42",
                    "surfaceHighest": "#243552",
                    "onSurface": "#EAF0FF",
                    "onSurfaceVariant": "#A9B7D5",
                    "outline": "#6B7FA8",
                    "outlineVariant": "#3A4B70",
                    "success": "#7DD8A4",
                    "warning": "#F5C877",
                    "error": "#FFB4AB",
                    "fontFamily": "Geist"
                }
            }),
            ..Default::default()
        },
        PluginManifest {
            name: "ember_theme".into(),
            version: "1.0.0".into(),
            author: Some("Lumen".into()),
            description: Some("A warm ember built-in theme.".into()),
            hooks: HashSet::new(),
            priority: 3,
            plugin_id: Some("ember_theme".into()),
            contributes: serde_json::json!({
                "theme": {
                    "applyByDefault": false,
                    "primary": "#FFB47A",
                    "primaryContainer": "#6B2E12",
                    "onPrimaryContainer": "#FFE0C7",
                    "secondary": "#FFD45A",
                    "background": "#120A06",
                    "surfaceLow": "#1F120B",
                    "surfaceContainer": "#2A1810",
                    "surfaceHigh": "#3A2317",
                    "surfaceHighest": "#4A2F1F",
                    "onSurface": "#F6ECE3",
                    "onSurfaceVariant": "#CDB7A6",
                    "outline": "#8A6F5D",
                    "outlineVariant": "#5A4031",
                    "success": "#9ED6A8",
                    "warning": "#F0C16C",
                    "error": "#FFB4AB",
                    "fontFamily": "Geist"
                }
            }),
            ..Default::default()
        },
        PluginManifest {
            name: "forest_theme".into(),
            version: "1.0.0".into(),
            author: Some("Lumen".into()),
            description: Some("A calm forest built-in theme.".into()),
            hooks: HashSet::new(),
            priority: 3,
            plugin_id: Some("forest_theme".into()),
            contributes: serde_json::json!({
                "theme": {
                    "applyByDefault": false,
                    "primary": "#7FD6A6",
                    "primaryContainer": "#17422D",
                    "onPrimaryContainer": "#D8F7E6",
                    "secondary": "#8BD3FF",
                    "background": "#06110C",
                    "surfaceLow": "#0E1C16",
                    "surfaceContainer": "#14261E",
                    "surfaceHigh": "#1B3328",
                    "surfaceHighest": "#244234",
                    "onSurface": "#E6F2EC",
                    "onSurfaceVariant": "#A6C0B4",
                    "outline": "#6F9082",
                    "outlineVariant": "#3D574B",
                    "success": "#8BE0B0",
                    "warning": "#F2D38B",
                    "error": "#FFB4AB",
                    "fontFamily": "Geist"
                }
            }),
            ..Default::default()
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
            (
                "dashboard_entries",
                Box::new(builtin::dashboard_entries::DashboardEntriesPlugin),
            ),
            ("theme_manager", Box::new(builtin::theme_manager::ThemeManagerPlugin)),
            ("import_export", Box::new(builtin::import_export::ImportExportPlugin)),
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

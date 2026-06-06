pub mod manifest;
pub mod loader;
pub mod builtin;
pub(crate) mod plugin_trait;

pub use plugin_trait::Plugin;
pub use manifest::PluginManifest;
pub use loader::{scan_plugins, LoadedPlugin};

use crate::entry::JournalEntry;

pub struct PluginManager {
    builtins: Vec<Box<dyn Plugin>>,
    externals: Vec<LoadedPlugin>,
}

impl PluginManager {
    pub fn new() -> Self {
        let mut builtins: Vec<Box<dyn Plugin>> = Vec::new();
        builtins.push(Box::new(builtin::export_md::ExportMdPlugin));
        builtins.push(Box::new(builtin::daily_summary::DailySummaryPlugin));
        builtins.push(Box::new(builtin::wordcount::WordCountPlugin));

        let plugins_dir = dirs::data_dir()
            .map(|d| d.join("lumen").join("plugins"));
        let externals = match plugins_dir {
            Some(dir) if dir.exists() => scan_plugins(&dir),
            _ => Vec::new(),
        };

        PluginManager { builtins, externals }
    }

    pub fn register_plugin(&mut self, plugin: Box<dyn Plugin>) {
        self.builtins.push(plugin);
    }

    pub fn run_on_entry(&self, entry: &JournalEntry) -> Vec<String> {
        let mut feedback = Vec::new();

        for plugin in &self.builtins {
            if let Some(msg) = plugin.on_entry(entry) {
                feedback.push(msg);
            }
        }

        for loaded in &self.externals {
            let name = &loaded.manifest.name;
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

use std::fs;
use std::path::PathBuf;

use libloading::Library;

use super::manifest::PluginManifest;

pub struct LoadedPlugin {
    pub manifest: PluginManifest,
    pub lib: Library,
}

pub fn scan_plugins(plugins_dir: &PathBuf) -> Vec<LoadedPlugin> {
    let mut loaded = Vec::new();

    let entries = match fs::read_dir(plugins_dir) {
        Ok(e) => e,
        Err(_) => return loaded,
    };

    for entry in entries.flatten() {
        let dir = entry.path();
        if !dir.is_dir() {
            continue;
        }

        let manifest_path = dir.join("plugin.toml");
        let manifest = match PluginManifest::from_file(&manifest_path) {
            Some(m) => m,
            None => continue,
        };

        // Determine shared library path
        let lib_name = format!("lib{}.so", manifest.name);
        let lib_path = dir.join(&lib_name);
        if !lib_path.exists() {
            eprintln!("[lumen] Plugin '{}' missing shared lib", manifest.name);
            continue;
        }

        let lib = match unsafe { Library::new(&lib_path) } {
            Ok(l) => l,
            Err(e) => {
                eprintln!("[lumen] Failed to load plugin '{}': {e}", manifest.name);
                continue;
            }
        };

        loaded.push(LoadedPlugin { manifest, lib });
    }

    loaded
}

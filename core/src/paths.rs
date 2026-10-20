use std::path::PathBuf;

use lazy_static::lazy_static;

lazy_static! {
    pub static ref ROOT_CONFIG_PATH: PathBuf = {
        let mut path = dirs::config_dir().unwrap_or_else(|| {
            // Fallback to data_dir if config_dir is not available, then to "."
            dirs::data_dir().unwrap_or_else(|| PathBuf::from("."))
        });
        path.push("Lumen");
        let _ = std::fs::create_dir_all(&path);
        path
    };
}

/// Directory scanned for on-disk plugin manifests.
pub fn plugins_dir() -> PathBuf {
    ROOT_CONFIG_PATH.join("plugins")
}

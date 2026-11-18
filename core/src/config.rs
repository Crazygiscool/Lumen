//! Configuration management for Lumen.

use std::path::PathBuf;

use dirs;
use lazy_static::lazy_static;
use serde::{Deserialize, Serialize};

lazy_static! {
    static ref CONFIG: Mutex<Option<Config>> = Mutex::new(None);
    /// Overrides the configuration directory. Used by tests so they never
    /// read or write the user's real configuration.
    static ref CONFIG_DIR_OVERRIDE: Mutex<Option<PathBuf>> = Mutex::new(None);
}

use std::sync::Mutex;

/// Global configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Template settings.
    pub templates: TemplateConfig,

    /// Search settings.
    pub search: SearchConfig,

    /// Wikilink settings.
    pub wikilinks: WikilinkConfig,

    /// Sync settings.
    pub sync: SyncConfig,

    /// AI settings.
    pub ai: AiConfig,

    /// Backup settings.
    pub backup: BackupConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateConfig {
    /// Path to daily note template.
    #[serde(default = "default_daily_template_path")]
    pub daily: String,
}

fn default_daily_template_path() -> String {
    let base = config_dir();
    base.join("templates/daily.md").to_string_lossy().to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchConfig {
    /// Enable full-text search.
    #[serde(default = "default_true")]
    pub enabled: bool,

    /// The folder holding the Tantivy indexes.
    ///
    /// The index holds the plain text of the notes, so it is kept out of the
    /// vault: the vault is what the user syncs and backs up, and everything
    /// in it is meant to be encrypted. A relative path is taken from the
    /// configuration folder.
    #[serde(default = "default_index_path")]
    pub index_path: String,

    /// Auto-reindex on vault unlock.
    #[serde(default = "default_true")]
    pub auto_reindex: bool,
}

fn default_true() -> bool {
    true
}

fn default_index_path() -> String {
    config_dir().join("search").to_string_lossy().to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WikilinkConfig {
    /// Case-sensitive matching.
    #[serde(default)]
    pub case_sensitive: bool,

    /// Create missing notes when clicking wikilinks.
    #[serde(default = "default_true")]
    pub create_missing: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncConfig {
    /// Sync method: "syncthing", "webdav", "none".
    #[serde(default = "default_sync_method")]
    pub method: String,

    /// Syncthing-specific config.
    #[serde(default)]
    pub syncthing: SyncthingConfig,

    /// WebDAV-specific config.
    #[serde(default)]
    pub webdav: WebdavConfig,
}

fn default_sync_method() -> String {
    "none".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SyncthingConfig {
    /// Path to Syncthing config.xml.
    pub config_path: String,

    /// Folder ID for journal.
    pub folder_id: String,

    /// Ignore patterns.
    #[serde(default = "default_ignore_patterns")]
    pub ignore_patterns: Vec<String>,

    /// Versioning strategy.
    #[serde(default = "default_versioning")]
    pub versioning: String,

    /// Versioning retention days.
    #[serde(default = "default_versioning_days")]
    pub versioning_days: u32,
}

fn default_ignore_patterns() -> Vec<String> {
    vec![
        "*.tmp".to_string(),
        "*.swp".to_string(),
        ".lumen/search/".to_string(),
        ".lumen/*.lock".to_string(),
    ]
}

fn default_versioning() -> String {
    "staggered".to_string()
}

fn default_versioning_days() -> u32 {
    30
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct WebdavConfig {
    /// WebDAV URL.
    pub url: String,

    /// Username.
    pub username: String,

    /// Encrypt before upload.
    #[serde(default = "default_true")]
    pub encrypt: bool,

    /// Schedule: "daily", "weekly", "manual".
    #[serde(default = "default_schedule")]
    pub schedule: String,

    /// Retention count.
    #[serde(default = "default_retention")]
    pub retention: u32,
}

fn default_schedule() -> String {
    "daily".to_string()
}

fn default_retention() -> u32 {
    7
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiConfig {
    /// Enable AI features.
    #[serde(default)]
    pub enabled: bool,

    /// Ollama base URL.
    #[serde(default = "default_ollama_url")]
    pub ollama_url: String,

    /// Default chat model.
    #[serde(default = "default_model")]
    pub default_model: String,

    /// Embedding model.
    #[serde(default = "default_embedding_model")]
    pub embedding_model: String,

    /// Max context notes for RAG.
    #[serde(default = "default_max_context_notes")]
    pub max_context_notes: usize,

    /// Max context tokens.
    #[serde(default = "default_max_context_tokens")]
    pub max_context_tokens: usize,

    /// Allow external APIs (default false for privacy).
    #[serde(default)]
    pub allow_external: bool,
}

fn default_ollama_url() -> String {
    "http://localhost:11434".to_string()
}

fn default_model() -> String {
    "llama3.1:8b".to_string()
}

fn default_embedding_model() -> String {
    "nomic-embed-text".to_string()
}

fn default_max_context_notes() -> usize {
    10
}

fn default_max_context_tokens() -> usize {
    4000
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackupConfig {
    /// Auto-export backup on close.
    #[serde(default)]
    pub auto_export: bool,

    /// Export directory.
    #[serde(default = "default_backup_path")]
    pub export_path: String,

    /// Encrypt backup.
    #[serde(default = "default_true")]
    pub encrypt: bool,
}

fn default_backup_path() -> String {
    let base = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
    base.join("Backups/Lumen").to_string_lossy().to_string()
}

/// Get the configuration directory.
///
/// `LUMEN_CONFIG_DIR` overrides the default location, and
/// [set_config_dir] overrides it in-process. The latter keeps tests from
/// touching the user's real configuration.
pub fn config_dir() -> PathBuf {
    let override_dir = CONFIG_DIR_OVERRIDE.lock().unwrap().clone();
    if let Some(dir) = override_dir {
        return dir;
    }
    if let Some(dir) = std::env::var_os("LUMEN_CONFIG_DIR") {
        return PathBuf::from(dir);
    }
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("Lumen")
}

/// Point the configuration at a different directory, or restore the default
/// when passed `None`.
///
/// The cached configuration is dropped, so the next read comes from the new
/// location.
pub fn set_config_dir(dir: Option<PathBuf>) {
    {
        let mut guard = CONFIG_DIR_OVERRIDE.lock().unwrap();
        *guard = dir;
    }
    let mut guard = CONFIG.lock().unwrap();
    *guard = None;
}

/// Get the path to the daily template file.
pub fn daily_template_path() -> PathBuf {
    let config = get_config();
    PathBuf::from(shellexpand::tilde(&config.templates.daily).to_string())
}

/// Load configuration from file.
pub fn load_config() -> Config {
    let config_path = config_dir().join("config.toml");

    if config_path.exists() {
        let content = std::fs::read_to_string(&config_path).unwrap_or_default();
        if let Ok(config) = toml::from_str::<Config>(&content) {
            return config;
        }
    }

    // Return defaults
    Config {
        templates: TemplateConfig {
            daily: default_daily_template_path(),
        },
        search: SearchConfig {
            enabled: true,
            index_path: default_index_path(),
            auto_reindex: true,
        },
        wikilinks: WikilinkConfig {
            case_sensitive: false,
            create_missing: true,
        },
        sync: SyncConfig {
            method: default_sync_method(),
            syncthing: SyncthingConfig::default(),
            webdav: WebdavConfig::default(),
        },
        ai: AiConfig {
            enabled: false,
            ollama_url: default_ollama_url(),
            default_model: default_model(),
            embedding_model: default_embedding_model(),
            max_context_notes: default_max_context_notes(),
            max_context_tokens: default_max_context_tokens(),
            allow_external: false,
        },
        backup: BackupConfig {
            auto_export: false,
            export_path: default_backup_path(),
            encrypt: true,
        },
    }
}

/// Get the global config (lazy-loaded).
pub fn get_config() -> Config {
    let mut guard = CONFIG.lock().unwrap();
    if guard.is_none() {
        *guard = Some(load_config());
    }
    guard.clone().unwrap()
}

/// Set the global config (for testing).
pub fn set_config(config: Config) {
    let mut guard = CONFIG.lock().unwrap();
    *guard = Some(config);
}

/// Save configuration to file.
pub fn save_config(config: &Config) -> std::io::Result<()> {
    let config_dir = config_dir();
    std::fs::create_dir_all(&config_dir)?;

    let config_path = config_dir.join("config.toml");
    let content = toml::to_string_pretty(config).unwrap();
    std::fs::write(config_path, content)?;

    // Update global
    let mut guard = CONFIG.lock().unwrap();
    *guard = Some(config.clone());

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = Config {
            templates: TemplateConfig { daily: "test.md".to_string() },
            search: SearchConfig { enabled: true, index_path: "idx".to_string(), auto_reindex: true },
            wikilinks: WikilinkConfig { case_sensitive: false, create_missing: true },
            sync: SyncConfig { method: "none".to_string(), syncthing: SyncthingConfig::default(), webdav: WebdavConfig::default() },
            ai: AiConfig { enabled: false, ollama_url: "http://localhost:11434".to_string(), default_model: "llama3".to_string(), embedding_model: "nomic".to_string(), max_context_notes: 10, max_context_tokens: 4000, allow_external: false },
            backup: BackupConfig { auto_export: false, export_path: "/tmp".to_string(), encrypt: true },
        };
        assert!(config.search.enabled);
    }
}
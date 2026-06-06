use std::collections::HashSet;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, serde::Deserialize)]
pub struct PluginManifest {
    pub name: String,
    pub version: String,
    pub author: Option<String>,
    pub description: Option<String>,
    #[serde(default)]
    pub hooks: HashSet<String>,
}

impl PluginManifest {
    pub fn from_file(path: &Path) -> Option<Self> {
        let content = fs::read_to_string(path).ok()?;
        toml::from_str(&content).ok()
    }
}

use std::collections::HashSet;
use std::fs;
use std::path::Path;

use serde_json;

#[derive(Debug, Clone, serde::Deserialize)]
pub struct PluginManifest {
    pub name: String,
    pub version: String,
    pub author: Option<String>,
    pub description: Option<String>,
    #[serde(default)]
    pub hooks: HashSet<String>,
    #[serde(default)]
    pub priority: i32,
    #[serde(default)]
    pub plugin_id: Option<String>,
    /// Arbitrary declarative UI contributions:
    /// `theme`, `icons`, `sidebar`, `dashboardCards`, etc.
    #[serde(default)]
    pub contributes: serde_json::Value,
}

impl PluginManifest {
    pub fn from_file(path: &Path) -> Option<Self> {
        let content = fs::read_to_string(path).ok()?;
        toml::from_str(&content).ok()
    }

    pub fn id(&self) -> String {
        self.plugin_id.clone().unwrap_or_else(|| self.name.clone())
    }
}

impl Default for PluginManifest {
    fn default() -> Self {
        Self {
            name: String::new(),
            version: String::new(),
            author: None,
            description: None,
            hooks: HashSet::new(),
            priority: 0,
            plugin_id: None,
            contributes: serde_json::Value::Null,
        }
    }
}

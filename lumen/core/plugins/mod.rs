//! Plugin runtime, lifecycle hooks

use crate::entry::JournalEntry;

pub trait Plugin {
    fn on_entry(&self, entry: &JournalEntry) -> Option<String>;
    fn on_export(&self, entry: &JournalEntry) -> Option<Vec<u8>>;
    // Add other hooks as needed
}

pub struct PluginManager {
    plugins: Vec<Box<dyn Plugin>>,
}

impl PluginManager {
    pub fn new() -> Self {
        PluginManager { plugins: Vec::new() }
    }

    pub fn register_plugin(&mut self, plugin: Box<dyn Plugin>) {
        self.plugins.push(plugin);
    }

    pub fn run_on_entry(&self, entry: &JournalEntry) {
        for plugin in &self.plugins {
            if let Some(feedback) = plugin.on_entry(entry) {
                // Attach feedback to entry (logic to be implemented)
            }
        }
    }
}

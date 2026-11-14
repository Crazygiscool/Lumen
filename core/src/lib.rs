// Re-export vault's Result type
pub type Result<T> = std::result::Result<T, String>;

pub mod config;
pub mod diff;
pub mod ffi;
pub mod frontmatter;
pub mod graph;
pub mod importer;
pub mod paths;
pub mod plugins;
pub mod query;
pub mod search;
pub mod secrets;
pub mod sync;
pub mod sync_notes;
pub mod sync_plan;
pub mod syncthing;
pub mod auto_update;
pub mod template;
pub mod vault;
pub mod wikilinks;

#[cfg(test)]
pub mod testutil;

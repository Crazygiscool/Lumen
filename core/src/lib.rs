// Re-export vault's Result type
pub type Result<T> = std::result::Result<T, String>;

pub mod config;
pub mod frontmatter;
pub mod graph;
pub mod importer;
pub mod paths;
pub mod plugins;
pub mod search;
pub mod template;
pub mod vault;
pub mod wikilinks;

#[cfg(test)]
pub mod testutil;

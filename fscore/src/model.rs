use serde::{Deserialize, Serialize};

#[derive(Serialize, Clone, Debug)]
pub struct FsEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub is_symlink: bool,
    pub size: u64,
    pub modified_ms: i64,
    pub permissions: String,
    pub owner: String,
    pub symlink_target: Option<String>,
    pub extension: Option<String>,
    pub is_hidden: bool,
}

#[derive(Serialize, Debug)]
pub struct DuNode {
    pub name: String,
    pub path: String,
    pub size: u64,
    pub children: Vec<DuNode>,
}

#[derive(Deserialize, Debug)]
pub struct ListArgs {
    pub path: String,
    #[serde(default)]
    pub show_hidden: bool,
}

#[derive(Deserialize, Debug)]
pub struct StatArgs {
    pub path: String,
}

#[derive(Deserialize, Debug)]
pub struct ReadArgs {
    pub path: String,
    #[serde(default = "default_cap")]
    pub max_bytes: u64,
}

fn default_cap() -> u64 {
    5 * 1024 * 1024
}

#[derive(Deserialize, Debug)]
pub struct WriteArgs {
    pub path: String,
    pub data: String,
}

#[derive(Deserialize, Debug)]
pub struct MoveArgs {
    pub from: String,
    pub to: String,
}

#[derive(Deserialize, Debug)]
pub struct SearchArgs {
    pub root: String,
    pub query: String,
    #[serde(default)]
    pub show_hidden: bool,
    #[serde(default = "default_max_results")]
    pub max_results: usize,
}

fn default_max_results() -> usize {
    500
}

#[derive(Deserialize, Debug)]
pub struct DuArgs {
    pub path: String,
    #[serde(default = "default_du_depth")]
    pub max_depth: usize,
}

fn default_du_depth() -> usize {
    3
}

pub fn ok(v: serde_json::Value) -> serde_json::Value {
    serde_json::json!({ "ok": true, "data": v })
}

pub fn err(e: impl ToString) -> serde_json::Value {
    serde_json::json!({ "ok": false, "error": e.to_string() })
}
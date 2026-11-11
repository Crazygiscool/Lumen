//! Graph view data structures and generation.

use std::collections::{HashMap, HashSet};

use crate::vault::{self};
use crate::wikilinks::{self};
use crate::frontmatter::Frontmatter;

/// Graph node representing a note.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct GraphNode {
    /// Unique identifier (vault path).
    pub id: String,
    /// Display title.
    pub title: String,
    /// Tags for coloring/filtering.
    pub tags: Vec<String>,
    /// Node weight (size) - based on word count + link count.
    pub weight: usize,
    /// Frontmatter for additional metadata.
    pub frontmatter: Frontmatter,
}

/// Graph edge representing a connection between notes.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct GraphEdge {
    /// Source node ID.
    pub source: String,
    /// Target node ID.
    pub target: String,
    /// Edge type for styling.
    #[serde(rename = "type")]
    pub edge_type: EdgeType,
}

/// Type of connection between notes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EdgeType {
    /// Direct wikilink from source to target.
    Wikilink,
    /// Backlink (target links to source).
    Backlink,
    /// Shared tag connection.
    Tag,
    /// Temporal proximity (adjacent dates).
    Temporal,
}

/// Complete graph data for visualization.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct GraphData {
    pub nodes: Vec<GraphNode>,
    pub edges: Vec<GraphEdge>,
}

/// Build graph data from vault.
pub fn build_graph_data(store: &str) -> crate::Result<GraphData> {
    let entries = vault::list("", store)?;
    let mut nodes = Vec::new();
    let mut node_map: HashMap<String, usize> = HashMap::new(); // path -> index
    let mut tag_to_nodes: HashMap<String, Vec<String>> = HashMap::new(); // tag -> paths

    // First pass: create nodes
    for entry in &entries {
        if entry.is_dir || !entry.name.ends_with(".md") {
            continue;
        }

        let body = vault::read_text(&entry.rel_path, store).unwrap_or_default();
        let (fm, _) = crate::frontmatter::parse_frontmatter(&body);

        let title = fm.title.clone().unwrap_or_else(|| entry.name.trim_end_matches(".md").to_string());
        let word_count = body.split_whitespace().count();
        let wikilinks = wikilinks::parse_wikilinks(&body);
        let link_count = wikilinks.len();
        let backlink_count = wikilinks::get_backlinks(store, &entry.rel_path).len();

        // Weight: word count + links * 10 (links are more significant for graph)
        let weight = word_count + link_count * 10 + backlink_count * 10;

        let node = GraphNode {
            id: entry.rel_path.clone(),
            title,
            tags: fm.tags.clone(),
            weight,
            frontmatter: fm.clone(),
        };

        let idx = nodes.len();
        nodes.push(node);
        node_map.insert(entry.rel_path.clone(), idx);

        // Index by tag
        for tag in &fm.tags {
            tag_to_nodes.entry(tag.clone()).or_default().push(entry.rel_path.clone());
        }
    }

    // Second pass: build edges
    let mut edges = Vec::new();
    let mut edge_set: HashSet<(String, String, EdgeType)> = HashSet::new();

    for entry in &entries {
        if entry.is_dir || !entry.name.ends_with(".md") {
            continue;
        }

        let body = vault::read_text(&entry.rel_path, store).unwrap_or_default();
        let wikilinks = wikilinks::parse_wikilinks(&body);

        // Wikilink edges
        for wl in wikilinks {
            let target = wikilinks::resolve_wikilink(store, &wl.target);
            if node_map.contains_key(&target) {
                let key = (entry.rel_path.clone(), target.clone(), EdgeType::Wikilink);
                if edge_set.insert(key) {
                    edges.push(GraphEdge {
                        source: entry.rel_path.clone(),
                        target,
                        edge_type: EdgeType::Wikilink,
                    });
                }
            }
        }

        // Backlink edges
        let backlinks = wikilinks::get_backlinks(store, &entry.rel_path);
        for backlink in backlinks {
            let key = (backlink.clone(), entry.rel_path.clone(), EdgeType::Backlink);
            if edge_set.insert(key) {
                edges.push(GraphEdge {
                    source: backlink,
                    target: entry.rel_path.clone(),
                    edge_type: EdgeType::Backlink,
                });
            }
        }
    }

    // Tag-based edges (connect notes sharing tags)
    for (_, paths) in tag_to_nodes {
        if paths.len() > 1 && paths.len() <= 50 { // Limit to avoid dense clusters
            for i in 0..paths.len() {
                for j in i+1..paths.len() {
                    let key = (paths[i].clone(), paths[j].clone(), EdgeType::Tag);
                    if edge_set.insert(key) {
                        edges.push(GraphEdge {
                            source: paths[i].clone(),
                            target: paths[j].clone(),
                            edge_type: EdgeType::Tag,
                        });
                    }
                }
            }
        }
    }

    // Temporal edges (adjacent daily notes)
    let mut daily_notes: Vec<_> = entries.iter()
        .filter(|e| !e.is_dir && e.name.ends_with(".md"))
        .filter_map(|e| {
            let stem = e.name.trim_end_matches(".md");
            chrono::NaiveDate::parse_from_str(&stem[..10.min(stem.len())], "%Y-%m-%d").ok().map(|d| (d, e.rel_path.clone()))
        })
        .collect();
    daily_notes.sort_by_key(|(d, _)| *d);

    for i in 1..daily_notes.len() {
        let (_, prev_path) = &daily_notes[i-1];
        let (_, curr_path) = &daily_notes[i];
        let key = (prev_path.clone(), curr_path.clone(), EdgeType::Temporal);
        if edge_set.insert(key) {
            edges.push(GraphEdge {
                source: prev_path.clone(),
                target: curr_path.clone(),
                edge_type: EdgeType::Temporal,
            });
        }
    }

    Ok(GraphData { nodes, edges })
}

/// Filter graph data by tags, date range, or search query.
pub fn filter_graph_data(data: GraphData, tags: &[String], query: Option<&str>) -> GraphData {
    let tag_set: HashSet<_> = tags.iter().collect();
    let query_lower = query.map(|q| q.to_lowercase());

    // Filter nodes
    let mut filtered_nodes = Vec::new();
    let mut node_id_to_new_idx = HashMap::new();

    for (_idx, node) in data.nodes.into_iter().enumerate() {
        let matches_tag = tag_set.is_empty() || node.tags.iter().any(|t| tag_set.contains(t));
        let matches_query = query_lower.as_ref().map_or(true, |q| {
            node.title.to_lowercase().contains(q) || node.tags.iter().any(|t| t.to_lowercase().contains(q))
        });

        if matches_tag && matches_query {
            node_id_to_new_idx.insert(node.id.clone(), filtered_nodes.len());
            filtered_nodes.push(node);
        }
    }

    // Filter edges to only include those between filtered nodes
    let filtered_edges = data.edges.into_iter()
        .filter(|e| node_id_to_new_idx.contains_key(&e.source) && node_id_to_new_idx.contains_key(&e.target))
        .collect();

    GraphData {
        nodes: filtered_nodes,
        edges: filtered_edges,
    }
}

/// Get graph data for a specific note and its neighborhood (for focus view).
pub fn get_note_neighborhood(store: &str, center_path: &str, depth: usize) -> crate::Result<GraphData> {
    let full_graph = build_graph_data(store)?;

    if depth == 0 {
        return Ok(full_graph);
    }

    // BFS from center to find nodes within depth
    let mut visited = HashSet::new();
    let mut current_level = vec![center_path.to_string()];
    visited.insert(center_path.to_string());

    for _ in 0..depth {
        let mut next_level = Vec::new();
        for node_id in &current_level {
            for edge in &full_graph.edges {
                let neighbor = if edge.source == *node_id {
                    Some(&edge.target)
                } else if edge.target == *node_id {
                    Some(&edge.source)
                } else {
                    None
                };

                if let Some(n) = neighbor {
                    if visited.insert(n.clone()) {
                        next_level.push(n.clone());
                    }
                }
            }
        }
        if next_level.is_empty() {
            break;
        }
        current_level = next_level;
    }

    // Filter to visited nodes
    Ok(filter_graph_data(full_graph, &[], None))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::{self, STORE_JOURNAL};
    use crate::wikilinks;
    use crate::config::{self, GraphConfig, Config};

    fn setup_test_vault() -> (tempfile::TempDir, String, crate::testutil::TestGuard) {
        // The vault registry is process-global, so hold the shared lock for
        // the duration of the test.
        let guard = crate::testutil::TestGuard::new();

        let temp = tempfile::tempdir().unwrap();
        let vault_path = temp.path().to_string_lossy().to_string();
        vault::create_with_passphrase(&vault_path, "testpass123", STORE_JOURNAL).unwrap();
        vault::unlock(&vault_path, "testpass123", STORE_JOURNAL).unwrap();

        // Set config to enable graph
        let mut cfg = config::get_config();
        cfg.graph = GraphConfig {
            enabled: true,
            layout: "force".to_string(),
            max_nodes: 5000,
        };
        config::set_config(cfg);

        (temp, vault_path, guard)
    }

    #[test]
    fn test_build_graph_data() {
        let (_temp, _vault_path, _guard) = setup_test_vault();

        vault::write_text("2026-01-01.md", "# Day One\n\nSee [[2026-01-02]]", STORE_JOURNAL).unwrap();
        vault::write_text("2026-01-02.md", "# Day Two\n\nBacklink to [[2026-01-01]]", STORE_JOURNAL).unwrap();
        vault::write_text("project-alpha.md", "---\ntags: [project]\n---\n\n# Project Alpha", STORE_JOURNAL).unwrap();
        vault::write_text("project-beta.md", "---\ntags: [project]\n---\n\n# Project Beta", STORE_JOURNAL).unwrap();

        wikilinks::init_backlink_index(STORE_JOURNAL);

        let graph = build_graph_data(STORE_JOURNAL).unwrap();

        assert_eq!(graph.nodes.len(), 4);

        // Should have wikilink edges
        let wikilink_edges: Vec<_> = graph.edges.iter().filter(|e| e.edge_type == EdgeType::Wikilink).collect();
        assert!(!wikilink_edges.is_empty());

        // Should have backlink edges
        let backlink_edges: Vec<_> = graph.edges.iter().filter(|e| e.edge_type == EdgeType::Backlink).collect();
        assert!(!backlink_edges.is_empty());

        // Should have tag edges between project notes
        let tag_edges: Vec<_> = graph.edges.iter().filter(|e| e.edge_type == EdgeType::Tag).collect();
        assert!(!tag_edges.is_empty());
    }

    #[test]
    fn test_filter_graph_data() {
        let (_temp, _vault_path, _guard) = setup_test_vault();

        vault::write_text("work-1.md", "---\ntags: [work]\n---\n\n# Work 1", STORE_JOURNAL).unwrap();
        vault::write_text("personal-1.md", "---\ntags: [personal]\n---\n\n# Personal 1", STORE_JOURNAL).unwrap();
        vault::write_text("work-2.md", "---\ntags: [work]\n---\n\n# Work 2", STORE_JOURNAL).unwrap();

        wikilinks::init_backlink_index(STORE_JOURNAL);
        let graph = build_graph_data(STORE_JOURNAL).unwrap();

        // Filter by work tag
        let filtered = filter_graph_data(graph, &["work".to_string()], None);
        assert_eq!(filtered.nodes.len(), 2);
        assert!(filtered.nodes.iter().all(|n| n.tags.contains(&"work".to_string())));
    }
}
use std::fs;
use std::io::{Read, Write};
use std::path::Path;

use base64::Engine;
use chrono::{Datelike, Timelike, Utc};
use walkdir::WalkDir;

use crate::model::{DuNode, FsEntry};

fn is_hidden(name: &str) -> bool {
    name.starts_with('.') && name.len() > 1
}

fn permissions_of(md: &fs::Metadata) -> String {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = md.permissions().mode();
        let mut s = String::with_capacity(9);
        for (mask, ch) in [
            (0o400, 'r'),
            (0o200, 'w'),
            (0o100, 'x'),
            (0o040, 'r'),
            (0o020, 'w'),
            (0o010, 'x'),
            (0o004, 'r'),
            (0o002, 'w'),
            (0o001, 'x'),
        ] {
            s.push(if mode & mask != 0 { ch } else { '-' });
        }
        s
    }
    #[cfg(not(unix))]
    {
        let _ = md;
        String::from("---")
    }
}

fn owner_of(meta: &fs::Metadata) -> String {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        let uid = meta.uid();
        let gid = meta.gid();
        let user = uzers::get_user_by_uid(uid)
            .map(|u| u.name().to_string_lossy().into_owned())
            .unwrap_or_else(|| uid.to_string());
        let group = uzers::get_group_by_gid(gid)
            .map(|g| g.name().to_string_lossy().into_owned())
            .unwrap_or_else(|| gid.to_string());
        format!("{user}:{group}")
    }
    #[cfg(not(unix))]
    {
        let _ = meta;
        String::from("-")
    }
}

fn entry_from_path(path: &Path, name: &str) -> std::io::Result<FsEntry> {
    let symlink_meta = fs::symlink_metadata(path)?;
    let is_symlink = symlink_meta.file_type().is_symlink();
    let meta = if is_symlink {
        fs::metadata(path).unwrap_or_else(|_| symlink_meta.clone())
    } else {
        symlink_meta.clone()
    };

    let modified_ms = if let Ok(t) = meta.modified() {
        t.duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0)
    } else {
        0
    };

    let symlink_target = if is_symlink {
        fs::read_link(path)
            .ok()
            .map(|p| p.to_string_lossy().into_owned())
    } else {
        None
    };

    let extension = if meta.is_file() {
        path.extension().map(|e| e.to_string_lossy().into_owned())
    } else {
        None
    };

    Ok(FsEntry {
        name: name.to_string(),
        path: path.to_string_lossy().into_owned(),
        is_dir: meta.is_dir(),
        is_symlink,
        size: if meta.is_file() { meta.len() } else { 0 },
        modified_ms,
        permissions: permissions_of(&symlink_meta),
        owner: owner_of(&symlink_meta),
        symlink_target,
        extension,
        is_hidden: is_hidden(name),
    })
}

pub fn list_dir(path: &str, show_hidden: bool) -> Result<Vec<FsEntry>, String> {
    let dir = Path::new(path);
    if !dir.is_dir() {
        return Err(format!("Not a directory: {path}"));
    }

    let mut entries = Vec::new();
    for read in fs::read_dir(dir).map_err(|e| e.to_string())? {
        let de = read.map_err(|e| e.to_string())?;
        let name = de.file_name().to_string_lossy().into_owned();
        if !show_hidden && is_hidden(&name) {
            continue;
        }
        if let Ok(e) = entry_from_path(&de.path(), &name) {
            entries.push(e);
        }
    }

    entries.sort_by(|a, b| {
        b.is_dir
            .cmp(&a.is_dir)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });

    Ok(entries)
}

pub fn stat(path: &str) -> Result<FsEntry, String> {
    let p = Path::new(path);
    let name = p
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string());
    entry_from_path(p, &name).map_err(|e| e.to_string())
}

fn human_date(ms: i64) -> String {
    if ms <= 0 {
        return String::new();
    }
    let seconds = ms / 1000;
    let dt = chrono::DateTime::<Utc>::from_timestamp(seconds, 0)
        .unwrap_or_else(Utc::now);
    format!(
        "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
        dt.year(),
        dt.month(),
        dt.day(),
        dt.hour(),
        dt.minute(),
        dt.second()
    )
}

pub fn stat_json(path: &str) -> Result<serde_json::Value, String> {
    let info = stat(path)?;
    let readable = if info.is_dir { String::new() } else { human_date(info.modified_ms) };
    Ok(serde_json::json!({
        "name": info.name,
        "path": info.path,
        "is_dir": info.is_dir,
        "is_symlink": info.is_symlink,
        "size": info.size,
        "modified_ms": info.modified_ms,
        "modified_readable": readable,
        "permissions": info.permissions,
        "owner": info.owner,
        "symlink_target": info.symlink_target,
        "extension": info.extension,
        "is_hidden": info.is_hidden,
    }))
}

pub fn read_file_base64(path: &str, max_bytes: u64) -> Result<serde_json::Value, String> {
    let p = Path::new(path);
    let size = fs::metadata(p).map_err(|e| e.to_string())?.len();
    if size > max_bytes {
        return Err(format!("File is {size} bytes; exceeds {max_bytes} byte preview limit"));
    }
    let mut file = fs::File::open(p).map_err(|e| e.to_string())?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer).map_err(|e| e.to_string())?;
    let b64 = base64::engine::general_purpose::STANDARD.encode(&buffer);
    Ok(serde_json::json!({ "data": b64, "size": buffer.len() }))
}

pub fn write_file(path: &str, b64: &str) -> Result<(), String> {
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(b64)
        .map_err(|e| format!("base64 decode: {e}"))?;
    let p = Path::new(path);
    if let Some(parent) = p.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let mut f = fs::File::create(p).map_err(|e| e.to_string())?;
    f.write_all(&bytes).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn create_dir(path: &str) -> Result<(), String> {
    fs::create_dir_all(path).map_err(|e| e.to_string())
}

pub fn rename(from: &str, to: &str) -> Result<(), String> {
    if let Some(parent) = Path::new(to).parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    fs::rename(from, to).map_err(|e| e.to_string())
}

pub fn copy(src: &str, dst: &str) -> Result<(), String> {
    let sp = Path::new(src);
    let dp = Path::new(dst);
    if sp.is_dir() {
        fs::create_dir_all(dp).map_err(|e| e.to_string())?;
        for read in fs::read_dir(sp).map_err(|e| e.to_string())? {
            let de = read.map_err(|e| e.to_string())?;
            let child_src = de.path();
            let child_dst = dp.join(de.file_name());
            copy(&child_src.to_string_lossy(), &child_dst.to_string_lossy())?;
        }
        Ok(())
    } else {
        if let Some(parent) = dp.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        fs::copy(sp, dp).map(|_| ()).map_err(|e| e.to_string())
    }
}

pub fn trash(path: &str) -> Result<(), String> {
    trash::delete(path).map_err(|e| e.to_string())
}

pub fn delete(path: &str) -> Result<(), String> {
    let p = Path::new(path);
    if p.is_dir() {
        fs::remove_dir_all(p).map_err(|e| e.to_string())
    } else {
        fs::remove_file(p).map_err(|e| e.to_string())
    }
}

pub fn search_names(
    root: &str,
    query: &str,
    show_hidden: bool,
    max_results: usize,
) -> Result<Vec<serde_json::Value>, String> {
    let needle = query.to_lowercase();
    let mut results = Vec::new();

    for read in WalkDir::new(root)
        .follow_links(false)
        .into_iter()
        .filter_entry(|e| {
            if !show_hidden {
                !is_hidden(&e.file_name().to_string_lossy())
            } else {
                true
            }
        })
        .flatten()
    {
        if !needle.is_empty() && !read.file_name().to_string_lossy().to_lowercase().contains(&needle) {
            continue;
        }
        if results.len() >= max_results {
            break;
        }
        let path = read.path();
        let name = read.file_name().to_string_lossy().into_owned();
        if let Ok(entry) = entry_from_path(path, &name) {
            results.push(serde_json::json!({
                "name": entry.name,
                "path": entry.path,
                "is_dir": entry.is_dir,
                "size": entry.size,
            }));
        }
    }

    Ok(results)
}

fn build_du_node(path: &Path, depth: usize, max_depth: usize) -> DuNode {
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string_lossy().into_owned());

    let mut node = DuNode {
        name,
        path: path.to_string_lossy().into_owned(),
        size: 0,
        children: Vec::new(),
    };

    if path.is_dir() {
        let mut children = Vec::new();
        if let Ok(read) = fs::read_dir(path) {
            for de in read.flatten() {
                let child_path = de.path();
                let child = if depth < max_depth {
                    build_du_node(&child_path, depth + 1, max_depth)
                } else {
                    build_du_node(&child_path, depth + 1, max_depth)
                };
                node.size += child.size;
                children.push(child);
            }
        }
        node.children = children;
    } else if let Ok(md) = fs::metadata(path) {
        node.size = md.len();
    }

    node
}

pub fn du_tree(path: &str, max_depth: usize) -> Result<DuNode, String> {
    let p = Path::new(path);
    if !p.exists() {
        return Err(format!("Path does not exist: {path}"));
    }
    Ok(build_du_node(p, 0, max_depth))
}

pub fn du_tree_json(path: &str, max_depth: usize) -> Result<serde_json::Value, String> {
    let node = du_tree(path, max_depth)?;
    let json = serde_json::to_value(&node).map_err(|e| e.to_string())?;
    Ok(json)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn list_roundtrip() {
        let tmp = std::env::temp_dir().join(format!("fscore_test_{}", std::process::id()));
        fs::create_dir_all(tmp.join("nested")).unwrap();
        fs::write(tmp.join("a.txt"), b"hello").unwrap();
        fs::write(tmp.join(".hidden"), b"x").unwrap();

        let entries = list_dir(tmp.to_str().unwrap(), false).unwrap();
        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        assert!(names.contains(&"a.txt"));
        assert!(names.contains(&"nested"));
        assert!(!names.contains(&".hidden"));

        let entries_hidden = list_dir(tmp.to_str().unwrap(), true).unwrap();
        let names_hidden: Vec<&str> = entries_hidden.iter().map(|e| e.name.as_str()).collect();
        assert!(names_hidden.contains(&".hidden"));

        fs::remove_dir_all(&tmp).unwrap();
    }

    #[test]
    fn search_finds_name() {
        let tmp = std::env::temp_dir().join(format!("fscore_search_{}", std::process::id()));
        fs::create_dir_all(tmp.join("sub")).unwrap();
        fs::write(tmp.join("Report2026.md"), b"x").unwrap();
        fs::write(tmp.join("sub/notes.md"), b"y").unwrap();

        let hits = search_names(tmp.to_str().unwrap(), "report", false, 100).unwrap();
        assert_eq!(hits.len(), 1);
        assert!(hits[0]["name"].as_str().unwrap().contains("Report2026"));

        fs::remove_dir_all(&tmp).unwrap();
    }

    #[test]
    fn du_sums_sizes() {
        let tmp = std::env::temp_dir().join(format!("fscore_du_{}", std::process::id()));
        fs::create_dir_all(tmp.join("sub")).unwrap();
        fs::write(tmp.join("a.bin"), vec![0u8; 10]).unwrap();
        fs::write(tmp.join("sub/b.bin"), vec![0u8; 5]).unwrap();

        let root = du_tree(tmp.to_str().unwrap(), 3).unwrap();
        assert_eq!(root.size, 15);
        assert_eq!(root.children.len(), 2);

        fs::remove_dir_all(&tmp).unwrap();
    }
}
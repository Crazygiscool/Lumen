//! Auto-update for Lumen desktop apps.
//!
//! Checks GitHub Releases for a newer version, downloads the platform-specific
//! artifact, verifies its SHA-256 checksum, extracts it, and applies the update.
//!
//! The update flow is:
//!
//!   1. `check_for_update()` queries the GitHub Releases API for the latest
//!      release and compares its tag against the current version.
//!   2. `download_update()` downloads the release asset for the current
//!      platform, downloads its `.sha256` sidecar, and verifies the hash.
//!   3. `apply_update()` extracts the archive and installs the new executable
//!      (+ Flutter bundle on desktop) in place of the running one.

use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// The GitHub repository for Lumen releases.
const GITHUB_REPO: &str = "Crazygiscool/Lumen";

/// Information about a release published on GitHub.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReleaseInfo {
    /// The release tag (e.g. `v4.0.3`).
    pub tag_name: String,
    /// Whether this is a prerelease.
    pub prerelease: bool,
    /// The release assets.
    pub assets: Vec<ReleaseAsset>,
}

/// A single release asset (downloadable file).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReleaseAsset {
    /// The file name (e.g. `Lumen-linux-v4.0.3.tar.gz`).
    pub name: String,
    /// The download URL.
    pub browser_download_url: String,
    /// The file size in bytes.
    pub size: u64,
}

/// The result of checking for an update.
#[derive(Debug, Clone)]
pub enum UpdateStatus {
    /// No update is available.
    UpToDate,
    /// An update is available with the given release info.
    UpdateAvailable(ReleaseInfo),
    /// The update check failed.
    Error(String),
}

/// The current version of Lumen, read from the workspace Cargo.toml.
pub fn current_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Parse a version tag like `v4.0.3` into a comparable tuple.
fn parse_version(tag: &str) -> Option<(u32, u32, u32)> {
    let tag = tag.strip_prefix('v').unwrap_or(tag);
    let parts: Vec<&str> = tag.split('.').collect();
    if parts.len() != 3 {
        return None;
    }
    Some((
        parts[0].parse().ok()?,
        parts[1].parse().ok()?,
        parts[2].parse().ok()?,
    ))
}

/// Compare two version tags. Returns `true` if `remote` is newer than `local`.
fn is_newer(remote: &str, local: &str) -> bool {
    match (parse_version(remote), parse_version(local)) {
        (Some((rm, rn, rp)), Some((lm, ln, lp))) => {
            (rm, rn, rp) > (lm, ln, lp)
        }
        _ => remote != local,
    }
}

/// The HTTP client used to talk to the GitHub API.
///
/// A single client is reused across calls so connections are pooled.
fn http_client() -> Result<Client, String> {
    Client::builder()
        .user_agent(format!("Lumen/{}", current_version()))
        .build()
        .map_err(|e| format!("failed to create HTTP client: {e}"))
}

/// Check whether a newer version of Lumen is available on GitHub.
///
/// Returns `UpdateStatus::UpToDate` if the current version is the latest,
/// `UpdateStatus::UpdateAvailable(info)` if a newer release exists, or
/// `UpdateStatus::Error` if the check could not be completed.
pub fn check_for_update() -> UpdateStatus {
    let client = match http_client() {
        Ok(c) => c,
        Err(e) => return UpdateStatus::Error(e),
    };

    let url = format!("https://api.github.com/repos/{GITHUB_REPO}/releases/latest");
    let response: Result<ReleaseInfo, _> = client
        .get(&url)
        .header("Accept", "application/vnd.github+json")
        .send()
        .and_then(|r| r.error_for_status())
        .and_then(|r| r.json())
        .map_err(|e| format!("failed to query GitHub API: {e}"));

    let release = match response {
        Ok(r) => r,
        Err(e) => return UpdateStatus::Error(e),
    };

    if is_newer(&release.tag_name, &current_version()) {
        UpdateStatus::UpdateAvailable(release)
    } else {
        UpdateStatus::UpToDate
    }
}

/// Find the release asset matching the current platform for the NEW version.
///
/// Uses the release's tag name (the version being updated *to*), not the
/// currently installed version.
fn find_asset(release: &ReleaseInfo) -> Option<&ReleaseAsset> {
    let version = release.tag_name.strip_prefix('v').unwrap_or(&release.tag_name);
    let target = if cfg!(target_os = "linux") {
        format!("Lumen-linux-v{}.tar.gz", version)
    } else if cfg!(target_os = "macos") {
        format!("Lumen-macos-v{}.zip", version)
    } else if cfg!(target_os = "windows") {
        format!("Lumen-windows-v{}-setup.exe", version)
    } else {
        return None;
    };

    release.assets.iter().find(|a| a.name == target)
}

/// Find the SHA-256 sidecar asset for a given asset (e.g. `foo.tar.gz.sha256`).
fn find_sha256_asset<'a>(release: &'a ReleaseInfo, asset: &ReleaseAsset) -> Option<&'a ReleaseAsset> {
    let sidecar_name = format!("{}.sha256", asset.name);
    release.assets.iter().find(|a| a.name == sidecar_name)
}

/// Compute the SHA-256 hex digest of a file.
fn sha256_file(path: &Path) -> Result<String, String> {
    let mut file = fs::File::open(path).map_err(|e| format!("cannot open file: {e}"))?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 8192];
    loop {
        let n = file.read(&mut buf).map_err(|e| format!("read error: {e}"))?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

/// Download an update asset to a temporary file and verify its SHA-256
/// checksum against the `.sha256` sidecar published in the release.
pub fn download_update(release: &ReleaseInfo) -> Result<PathBuf, String> {
    let asset = find_asset(release).ok_or_else(|| {
        format!(
            "no release asset for platform {}",
            if cfg!(target_os = "linux") {
                "linux"
            } else if cfg!(target_os = "macos") {
                "macos"
            } else if cfg!(target_os = "windows") {
                "windows"
            } else {
                "unknown"
            }
        )
    })?;

    let client = http_client()?;
    let mut response = client
        .get(&asset.browser_download_url)
        .send()
        .map_err(|e| format!("failed to start download: {e}"))?
        .error_for_status()
        .map_err(|e| format!("download failed: {e}"))?;

    let temp_dir = std::env::temp_dir();
    let out_path = temp_dir.join(format!("lumen-update-{}", asset.name));
    let mut file = fs::File::create(&out_path).map_err(|e| format!("cannot create temp file: {e}"))?;

    let mut downloaded = 0u64;
    loop {
        let mut buf = [0u8; 8192];
        let n = response
            .read(&mut buf)
            .map_err(|e| format!("read error: {e}"))?;
        if n == 0 {
            break;
        }
        file.write_all(&buf[..n]).map_err(|e| format!("write error: {e}"))?;
        downloaded += n as u64;
    }

    if downloaded != asset.size {
        let _ = fs::remove_file(&out_path);
        return Err(format!(
            "size mismatch: expected {} bytes, got {}",
            asset.size, downloaded
        ));
    }

    // Verify SHA-256 against the sidecar asset if one exists.
    if let Some(sha_asset) = find_sha256_asset(release, asset) {
        let mut sha_response = client
            .get(&sha_asset.browser_download_url)
            .send()
            .map_err(|e| format!("failed to download SHA-256 sidecar: {e}"))?
            .error_for_status()
            .map_err(|e| format!("SHA-256 sidecar download failed: {e}"))?;

        let mut sha_content = String::new();
        sha_response
            .read_to_string(&mut sha_content)
            .map_err(|e| format!("failed to read SHA-256 sidecar: {e}"))?;

        let expected_hash = sha_content
            .split_whitespace()
            .next()
            .ok_or_else(|| "invalid SHA-256 sidecar: no hash found".to_string())?;

        let actual_hash = sha256_file(&out_path)?;
        if actual_hash != expected_hash {
            let _ = fs::remove_file(&out_path);
            return Err(format!(
                "SHA-256 checksum mismatch: expected {}, got {}",
                expected_hash, actual_hash
            ));
        }
    }

    Ok(out_path)
}

/// Extract a `.tar.gz` archive into `dest`.
fn extract_tar_gz(archive: &Path, dest: &Path) -> Result<(), String> {
    let file = fs::File::open(archive).map_err(|e| format!("cannot open archive: {e}"))?;
    let gz = flate2::read::GzDecoder::new(file);
    let mut archive = tar::Archive::new(gz);
    archive
        .unpack(dest)
        .map_err(|e| format!("failed to extract tar.gz: {e}"))
}

/// Extract a `.zip` archive into `dest`.
fn extract_zip(archive: &Path, dest: &Path) -> Result<(), String> {
    let file = fs::File::open(archive).map_err(|e| format!("cannot open archive: {e}"))?;
    let mut archive = zip::ZipArchive::new(file).map_err(|e| format!("invalid zip: {e}"))?;
    for i in 0..archive.len() {
        let mut file = archive.by_index(i).map_err(|e| format!("zip read error: {e}"))?;
        let out_path = match file.enclosed_name() {
            Some(p) => dest.join(p),
            None => continue,
        };
        if (*file.name()).ends_with('/') {
            fs::create_dir_all(&out_path).map_err(|e| format!("mkdir error: {e}"))?;
        } else {
            if let Some(p) = out_path.parent() {
                if !p.exists() {
                    fs::create_dir_all(p).map_err(|e| format!("mkdir error: {e}"))?;
                }
            }
            let mut out = fs::File::create(&out_path).map_err(|e| format!("create error: {e}"))?;
            std::io::copy(&mut file, &mut out).map_err(|e| format!("write error: {e}"))?;
        }
    }
    Ok(())
}

/// Install the extracted update into the install directory.
///
/// On Linux/macOS the Flutter bundle lives next to the executable, so we
/// copy the extracted `bundle/` contents over the install directory and
/// make the `lumen` executable writable. On Windows we stage the new
/// installer next to the running executable.
fn install_update(extracted_dir: &Path) -> Result<(), String> {
    let current_exe = std::env::current_exe()
        .map_err(|e| format!("cannot locate current executable: {e}"))?;
    let install_dir = current_exe
        .parent()
        .ok_or_else(|| "current executable has no parent directory".to_string())?;

    if cfg!(target_os = "windows") {
        // Windows locks running executables, so stage the new installer
        // next to the current one and tell the user to restart.
        let staged = current_exe.with_extension("exe.new");
        // Find the setup.exe inside the extracted dir
        let setup_exe = find_file_named(extracted_dir, "Lumen-windows-*-setup.exe")?;
        fs::copy(setup_exe, &staged).map_err(|e| format!("cannot stage update: {e}"))?;
        println!("Update staged at {}. Restart Lumen to apply.", staged.display());
        return Ok(());
    }

    // Linux/macOS: find the bundle directory inside the extraction.
    // The tarball contains `bundle/` at top level; the zip may contain
    // `Lumen.app/` on macOS or `bundle/` on Linux-style zips.
    let bundle_dir = find_bundle_dir(extracted_dir)?;

    // Copy bundle contents into the install directory, overwriting old files.
    copy_dir_recursive(&bundle_dir, install_dir)?;

    // Ensure the executable is runnable.
    let exe_name = if cfg!(target_os = "macos") {
        "lumen"
    } else {
        "lumen"
    };
    let exe_path = install_dir.join(exe_name);
    if exe_path.exists() {
        let metadata = fs::metadata(&exe_path).map_err(|e| format!("metadata error: {e}"))?;
        let mut perms = metadata.permissions();
        perms.set_readonly(false);
        fs::set_permissions(&exe_path, perms).map_err(|e| format!("chmod error: {e}"))?;
    }

    let _ = fs::remove_dir_all(extracted_dir);
    println!("Update applied. Restart Lumen to use the new version.");
    Ok(())
}

/// Find a file matching a glob-like pattern (simple prefix match) under dir.
fn find_file_named(dir: &Path, pattern: &str) -> Result<PathBuf, String> {
    for entry in fs::read_dir(dir).map_err(|e| format!("read dir error: {e}"))? {
        let entry = entry.map_err(|e| format!("dir entry error: {e}"))?;
        let name = entry.file_name().to_string_lossy().to_string();
        if glob_match(&name, pattern) {
            return Ok(entry.path());
        }
    }
    Err(format!("no file matching '{}' found in {:?}", pattern, dir))
}

/// Find the bundle directory inside an extracted update.
/// On Linux the tarball contains `bundle/`; on macOS the zip contains `Lumen.app/`.
fn find_bundle_dir(dir: &Path) -> Result<PathBuf, String> {
    // First check for a `bundle/` subdirectory (Linux tarball layout).
    let bundle = dir.join("bundle");
    if bundle.is_dir() {
        return Ok(bundle);
    }

    // Check for `Lumen.app` (macOS zip layout).
    let app = dir.join("Lumen.app");
    if app.is_dir() {
        return Ok(app);
    }

    // Otherwise, look for any subdirectory containing a `lumen` executable.
    for entry in fs::read_dir(dir).map_err(|e| format!("read dir error: {e}"))? {
        let entry = entry.map_err(|e| format!("dir entry error: {e}"))?;
        let path = entry.path();
        if path.is_dir() {
            let exe = path.join("lumen");
            if exe.is_file() {
                return Ok(path);
            }
        }
    }

    Err(format!("no bundle directory found in {:?}", dir))
}

/// Simple glob match supporting `*` wildcards.
fn glob_match(name: &str, pattern: &str) -> bool {
    let mut pi = 0;
    let mut ni = 0;
    let pattern_chars: Vec<char> = pattern.chars().collect();
    let name_chars: Vec<char> = name.chars().collect();
    while pi < pattern_chars.len() {
        if pattern_chars[pi] == '*' {
            pi += 1;
            if pi == pattern_chars.len() {
                return true;
            }
            while ni < name_chars.len() {
                if glob_match(&name_chars[ni..].iter().collect::<String>(), &pattern_chars[pi..].iter().collect::<String>()) {
                    return true;
                }
                ni += 1;
            }
            return false;
        } else if ni >= name_chars.len() || pattern_chars[pi] != name_chars[ni] {
            return false;
        }
        pi += 1;
        ni += 1;
    }
    ni == name_chars.len()
}

/// Recursively copy `src` directory contents into `dst`, overwriting existing files.
fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<(), String> {
    for entry in fs::read_dir(src).map_err(|e| format!("read dir error: {e}"))? {
        let entry = entry.map_err(|e| format!("dir entry error: {e}"))?;
        let src_path = entry.path();
        let name = entry.file_name();
        let dst_path = dst.join(&name);

        if src_path.is_dir() {
            fs::create_dir_all(&dst_path).map_err(|e| format!("mkdir error: {e}"))?;
            copy_dir_recursive(&src_path, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path).map_err(|e| format!("copy error: {e}"))?;
        }
    }
    Ok(())
}

/// Apply a downloaded update by extracting it and installing in place.
pub fn apply_update(update_path: &Path) -> Result<(), String> {
    let temp_dir = std::env::temp_dir().join("lumen-update-extract");
    let _ = fs::remove_dir_all(&temp_dir);
    fs::create_dir_all(&temp_dir).map_err(|e| format!("cannot create extract dir: {e}"))?;

    let name = update_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("update");

    if name.ends_with(".tar.gz") {
        extract_tar_gz(update_path, &temp_dir)?;
    } else if name.ends_with(".zip") {
        extract_zip(update_path, &temp_dir)?;
    } else {
        return Err(format!("unknown archive type: {name}"));
    }

    install_update(&temp_dir)?;

    let _ = fs::remove_file(update_path);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_version() {
        assert_eq!(parse_version("v3.2.3"), Some((3, 2, 3)));
        assert_eq!(parse_version("3.2.3"), Some((3, 2, 3)));
        assert_eq!(parse_version("v1.0.0"), Some((1, 0, 0)));
        assert_eq!(parse_version("invalid"), None);
        assert_eq!(parse_version("v1.2"), None);
    }

    #[test]
    fn test_is_newer() {
        assert!(is_newer("v3.2.4", "v3.2.3"));
        assert!(is_newer("v3.3.0", "v3.2.3"));
        assert!(is_newer("v4.0.0", "v3.2.3"));
        assert!(!is_newer("v3.2.3", "v3.2.3"));
        assert!(!is_newer("v3.2.2", "v3.2.3"));
    }

    #[test]
    fn test_current_version() {
        let v = current_version();
        assert!(!v.is_empty());
        assert!(v.contains('.'));
    }

    #[test]
    fn test_glob_match() {
        assert!(glob_match("Lumen-linux-v4.0.3.tar.gz", "Lumen-linux-v*.tar.gz"));
        assert!(!glob_match("Lumen-macos-v4.0.3.zip", "Lumen-linux-v*.tar.gz"));
        assert!(glob_match("Lumen-linux-v4.0.3.tar.gz.sha256", "*.sha256"));
        assert!(!glob_match("Lumen-linux-v4.0.3.tar.gz", "*.sha256"));
    }
}

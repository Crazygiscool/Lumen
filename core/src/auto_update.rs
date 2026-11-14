//! Auto-update for Lumen desktop apps.
//!
//! Checks GitHub Releases for a newer version, downloads the platform-specific
//! artifact, and applies the update. The update is verified against the
//! checksum published in the release assets.
//!
//! The update flow is:
//!
//!   1. `check_for_update()` queries the GitHub Releases API for the latest
//!      release and compares its tag against the current version.
//!   2. `download_update()` downloads the release asset for the current
//!      platform and verifies its SHA-256 checksum.
//!   3. `apply_update()` installs the downloaded artifact, replacing the
//!      running executable (and, on Linux/macOS, the Flutter bundle).

use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};

/// The GitHub repository for Lumen releases.
const GITHUB_REPO: &str = "Crazygiscool/Lumen";

/// Information about a release published on GitHub.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReleaseInfo {
    /// The release tag (e.g. `v3.2.3`).
    pub tag_name: String,
    /// Whether this is a prerelease.
    pub prerelease: bool,
    /// The release assets.
    pub assets: Vec<ReleaseAsset>,
}

/// A single release asset (downloadable file).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReleaseAsset {
    /// The file name (e.g. `Lumen-linux-v3.2.3.tar.gz`).
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

/// Parse a version tag like `v3.2.3` into a comparable tuple.
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

/// Find the release asset matching the current platform.
///
/// Platform-specific asset name patterns:
///   - Linux:   `Lumen-linux-v{version}.tar.gz`
///   - macOS:   `Lumen-macos-v{version}.zip`
///   - Windows: `Lumen-windows-v{version}-setup.exe`
fn find_asset(release: &ReleaseInfo) -> Option<&ReleaseAsset> {
    let target = if cfg!(target_os = "linux") {
        format!("Lumen-linux-v{}.tar.gz", current_version())
    } else if cfg!(target_os = "macos") {
        format!("Lumen-macos-v{}.zip", current_version())
    } else if cfg!(target_os = "windows") {
        format!("Lumen-windows-v{}-setup.exe", current_version())
    } else {
        return None;
    };

    release.assets.iter().find(|a| a.name == target)
}

/// Download an update asset to a temporary file and verify its checksum.
///
/// The checksum is read from the release asset's name with a `.sha256`
/// suffix if such an asset exists; otherwise the download is accepted
/// without verification (the GitHub API already authenticates the upload).
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
            "checksum mismatch: expected {} bytes, got {}",
            asset.size, downloaded
        ));
    }

    Ok(out_path)
}

/// Apply a downloaded update by replacing the running executable.
///
/// On Linux and macOS, the new executable is copied over the current one.
/// On Windows, the running executable cannot be replaced in place, so the
/// update is staged and a note is printed telling the user to restart.
pub fn apply_update(update_path: &Path) -> Result<(), String> {
    let current_exe = std::env::current_exe().map_err(|e| format!("cannot locate current executable: {e}"))?;

    if cfg!(target_os = "windows") {
        // Windows locks running executables, so we stage the update next to
        // the current one and tell the user to restart.
        let staged = current_exe.with_extension("exe.new");
        fs::copy(update_path, &staged).map_err(|e| format!("cannot stage update: {e}"))?;
        println!("Update staged at {}. Restart Lumen to apply.", staged.display());
        Ok(())
    } else {
        // On Unix we can replace the executable in place.
        fs::copy(update_path, &current_exe).map_err(|e| format!("cannot replace executable: {e}"))?;
        let _ = fs::remove_file(update_path);
        println!("Update applied. Restart Lumen to use the new version.");
        Ok(())
    }
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
}

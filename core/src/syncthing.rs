//! The Syncthing API, read over the local REST interface.
//!
//! Syncthing runs on the machine and offers a REST interface on localhost.
//! Reading it is how Lumen knows which devices are connected and how much
//! is still to be synced, instead of guessing from the files on disk.
//!
//! The interface is asked over plain HTTP on the loopback address, and the
//! key it wants comes from Syncthing's own configuration file, so the user
//! is never asked for it twice.

use std::fs;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::time::Duration;

use chrono::{DateTime, Utc};
use serde::Deserialize;

use crate::config;

/// How long to wait for Syncthing to answer.
const TIMEOUT: Duration = Duration::from_secs(3);

/// Where the Syncthing interface lives, and the key it wants.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoint {
    /// The host and port of the interface, e.g. `127.0.0.1:8384`.
    pub address: String,
    /// The key the API asks for.
    pub api_key: String,
}

impl Endpoint {
    /// The host and the port of the interface.
    fn host_port(&self) -> crate::Result<(String, u16)> {
        let (host, port) = match self.address.rsplit_once(':') {
            Some((host, port)) => (host.to_string(), port),
            None => (self.address.clone(), "8384"),
        };
        let port = port
            .parse::<u16>()
            .map_err(|_| format!("{} is not a port", port))?;
        Ok((host, port))
    }
}

/// A device Syncthing knows.
#[derive(Debug, Clone, PartialEq)]
pub struct DeviceInfo {
    /// The device's identifier.
    pub id: String,
    /// The name the device is known by.
    pub name: String,
    /// Whether the device is connected right now.
    pub connected: bool,
    /// When the device was last seen.
    pub last_seen: Option<DateTime<Utc>>,
}

/// What Syncthing says about the sync.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Status {
    /// The devices Syncthing knows.
    pub devices: Vec<DeviceInfo>,
    /// The number of changes still to be synced.
    pub pending: usize,
    /// The state of the folder, e.g. `idle`.
    pub state: String,
}

/// The folder Syncthing keeps for the vault.
#[derive(Debug, Clone, Deserialize)]
struct Folder {
    id: String,
    #[serde(default)]
    path: String,
}

/// A device in Syncthing's configuration.
#[derive(Debug, Clone, Deserialize)]
struct Device {
    #[serde(rename = "deviceID")]
    device_id: String,
    #[serde(default)]
    name: String,
}

/// The connection state of a device.
#[derive(Debug, Clone, Deserialize)]
struct DeviceStats {
    #[serde(default)]
    connected: bool,
    #[serde(default, rename = "lastSeen")]
    last_seen: Option<DateTime<Utc>>,
}

/// The state of a folder.
#[derive(Debug, Clone, Deserialize)]
struct FolderStatus {
    #[serde(default)]
    state: String,
}

/// The items still to be synced.
#[derive(Debug, Clone, Deserialize)]
struct Need {
    #[serde(default)]
    total: usize,
}

/// The path of Syncthing's configuration file.
///
/// The file is where the interface's address and key live, so it is read
/// from the place Syncthing puts it.
pub fn default_config_path() -> PathBuf {
    let config = config::get_config();
    if !config.sync.syncthing.config_path.is_empty() {
        return PathBuf::from(shellexpand::tilde(&config.sync.syncthing.config_path).to_string());
    }
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("syncthing")
        .join("config.xml")
}

/// Read the address and the key of the interface from Syncthing's
/// configuration file.
///
/// The file is XML, but only two values are wanted from it, and both are
/// plain text between an opening and a closing tag.
pub fn read_endpoint(path: &Path) -> Option<Endpoint> {
    let content = fs::read_to_string(path).ok()?;
    let address = element_text(&content, "address")?;
    let api_key = element_text(&content, "apikey")?;
    Some(Endpoint { address, api_key })
}

/// The text inside an element, if the element is there.
fn element_text(xml: &str, name: &str) -> Option<String> {
    let open = format!("<{name}>");
    let close = format!("</{name}>");
    let start = xml.find(&open)? + open.len();
    let end = xml[start..].find(&close)? + start;
    let text = xml[start..end].trim();
    if text.is_empty() {
        None
    } else {
        Some(text.to_string())
    }
}

/// Ask the interface a question and return the answer.
fn get(endpoint: &Endpoint, path: &str) -> crate::Result<String> {
    let (host, port) = endpoint.host_port()?;
    let mut stream = TcpStream::connect((host.as_str(), port))
        .map_err(|e| format!("could not reach Syncthing on {host}:{port}: {e}"))?;
    stream
        .set_read_timeout(Some(TIMEOUT))
        .map_err(|e| e.to_string())?;
    stream
        .set_write_timeout(Some(TIMEOUT))
        .map_err(|e| e.to_string())?;

    let request = format!(
        "GET {path} HTTP/1.1\r\n\
         Host: {host}:{port}\r\n\
         X-API-Key: {api_key}\r\n\
         Accept: application/json\r\n\
         Connection: close\r\n\r\n",
        path = path,
        host = host,
        port = port,
        api_key = endpoint.api_key,
    );
    stream
        .write_all(request.as_bytes())
        .map_err(|e| e.to_string())?;

    let mut response = Vec::new();
    stream
        .read_to_end(&mut response)
        .map_err(|e| e.to_string())?;
    let response = String::from_utf8_lossy(&response).to_string();

    let (head, body) = response
        .split_once("\r\n\r\n")
        .ok_or("the answer from Syncthing was not readable")?;
    let status = head.lines().next().unwrap_or_default();
    if !status.contains(" 200") {
        return Err(format!("Syncthing answered: {status}"));
    }
    Ok(body.to_string())
}

/// The folder Syncthing keeps for the vault.
///
/// The folder is found by its path, so Lumen works with a folder Syncthing
/// set up itself, without the identifier having to be configured.
fn find_folder(endpoint: &Endpoint, vault_path: &str) -> crate::Result<Option<Folder>> {
    let body = get(endpoint, "/rest/config/folders")?;
    let folders: Vec<Folder> = serde_json::from_str(&body).map_err(|e| e.to_string())?;

    // The path Syncthing knows may differ in its spelling from the one Lumen
    // was given, so the folders are compared without their trailing slash.
    let wanted = vault_path.trim_end_matches('/');
    Ok(folders.into_iter().find(|folder| {
        folder.path.trim_end_matches('/') == wanted || folder.path.ends_with(wanted)
    }))
}

/// The identifier of the folder, from the configuration when it is set.
fn configured_folder_id() -> Option<String> {
    let config = config::get_config();
    let id = config.sync.syncthing.folder_id.trim();
    if id.is_empty() {
        None
    } else {
        Some(id.to_string())
    }
}

/// Ask Syncthing how the sync is going.
///
/// The answer is what the interface says; when Syncthing is not running,
/// the error says so.
pub fn status(vault_path: &str) -> crate::Result<Status> {
    let endpoint = read_endpoint(&default_config_path())
        .ok_or("Syncthing's configuration could not be read")?;

    let mut status = Status::default();

    // The devices.
    let body = get(&endpoint, "/rest/config/devices")?;
    let devices: Vec<Device> = serde_json::from_str(&body).map_err(|e| e.to_string())?;

    let stats_body = get(&endpoint, "/rest/stats/device").unwrap_or_default();
    let stats: std::collections::HashMap<String, DeviceStats> =
        serde_json::from_str(&stats_body).unwrap_or_default();

    for device in devices {
        let device_stats = stats.get(&device.device_id);
        status.devices.push(DeviceInfo {
            id: device.device_id.clone(),
            name: if device.name.is_empty() {
                device.device_id.clone()
            } else {
                device.name.clone()
            },
            connected: device_stats.map(|s| s.connected).unwrap_or(false),
            last_seen: device_stats.and_then(|s| s.last_seen),
        });
    }

    // The folder, and what is left to sync in it.
    let folder_id = match configured_folder_id() {
        Some(id) => Some(id),
        None => find_folder(&endpoint, vault_path)?.map(|folder| folder.id),
    };

    if let Some(folder_id) = folder_id {
        let body = get(&endpoint, &format!("/rest/db/status?folder={folder_id}"))?;
        if let Ok(folder_status) = serde_json::from_str::<FolderStatus>(&body) {
            status.state = folder_status.state;
        }

        let body = get(
            &endpoint,
            &format!("/rest/db/need?folder={folder_id}&page=1&perpage=1"),
        )?;
        if let Ok(need) = serde_json::from_str::<Need>(&body) {
            status.pending = need.total;
        }
    }

    Ok(status)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_element_text_is_read() {
        let xml = "<configuration><gui><address>127.0.0.1:8384</address>\
                   <apikey>abc123</apikey></gui></configuration>";

        assert_eq!(
            element_text(xml, "address").as_deref(),
            Some("127.0.0.1:8384")
        );
        assert_eq!(element_text(xml, "apikey").as_deref(), Some("abc123"));
    }

    #[test]
    fn test_element_text_of_a_missing_element_is_none() {
        let xml = "<configuration><gui></gui></configuration>";

        assert!(element_text(xml, "address").is_none());
        assert!(element_text(xml, "apikey").is_none());
    }

    #[test]
    fn test_an_empty_element_is_none() {
        let xml = "<configuration><apikey>  </apikey></configuration>";

        assert!(element_text(xml, "apikey").is_none());
    }

    #[test]
    fn test_the_endpoint_is_read_from_the_configuration_file() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("config.xml");
        std::fs::write(
            &path,
            "<configuration version=\"37\"><gui enabled=\"true\">\
             <address>127.0.0.1:8384</address><apikey>secret</apikey>\
             </gui></configuration>",
        )
        .unwrap();

        let endpoint = read_endpoint(&path).unwrap();

        assert_eq!(endpoint.address, "127.0.0.1:8384");
        assert_eq!(endpoint.api_key, "secret");
    }

    #[test]
    fn test_a_missing_configuration_file_has_no_endpoint() {
        let temp = tempfile::tempdir().unwrap();

        assert!(read_endpoint(&temp.path().join("config.xml")).is_none());
    }

    #[test]
    fn test_the_host_and_port_are_split() {
        let endpoint = Endpoint {
            address: "127.0.0.1:8384".to_string(),
            api_key: "secret".to_string(),
        };

        let (host, port) = endpoint.host_port().unwrap();

        assert_eq!(host, "127.0.0.1");
        assert_eq!(port, 8384);
    }

    #[test]
    fn test_an_address_without_a_port_uses_the_default_one() {
        let endpoint = Endpoint {
            address: "127.0.0.1".to_string(),
            api_key: "secret".to_string(),
        };

        let (host, port) = endpoint.host_port().unwrap();

        assert_eq!(host, "127.0.0.1");
        assert_eq!(port, 8384);
    }
}

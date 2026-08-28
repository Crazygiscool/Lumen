use sysinfo::{ProcessRefreshKind, System};

pub fn hardware() -> serde_json::Value {
    let mut sys = System::new_all();
    sys.refresh_all();

    let cpus: Vec<serde_json::Value> = sys
        .cpus()
        .iter()
        .enumerate()
        .map(|(i, cpu)| {
            serde_json::json!({
                "index": i,
                "brand": cpu.brand(),
                "frequency_mhz": cpu.frequency(),
                "usage_percent": cpu.cpu_usage(),
            })
        })
        .collect();

    serde_json::json!({
        "os_name": System::name(),
        "os_version": System::os_version(),
        "kernel": System::kernel_version(),
        "hostname": System::host_name(),
        "total_memory": sys.total_memory(),
        "used_memory": sys.used_memory(),
        "total_swap": sys.total_swap(),
        "cpus": cpus,
        "cpu_count": sys.cpus().len(),
        "uptime_seconds": System::uptime(),
    })
}

pub fn processes() -> serde_json::Value {
    let mut sys = System::new_all();
    sys.refresh_processes_specifics(ProcessRefreshKind::everything());

    let mut list: Vec<serde_json::Value> = sys
        .processes()
        .iter()
        .map(|(pid, proc)| {
            serde_json::json!({
                "pid": pid.as_u32(),
                "name": proc.name().to_string(),
                "exe": proc.exe().map(|e| e.to_string_lossy()),
                "parent_pid": proc.parent().map(|p| p.as_u32()),
                "memory": proc.memory(),
                "cpu_usage": proc.cpu_usage(),
                "status": format!("{:?}", proc.status()),
            })
        })
        .collect();

    list.sort_by(|a, b| {
        let a_mem = a["memory"].as_u64().unwrap_or(0);
        let b_mem = b["memory"].as_u64().unwrap_or(0);
        b_mem.cmp(&a_mem)
    });

    serde_json::json!(list)
}

pub fn mounts() -> serde_json::Value {
    #[cfg(target_os = "linux")]
    {
        let mut mounts = Vec::new();
        if let Ok(content) = std::fs::read_to_string("/proc/self/mounts") {
            for line in content.lines() {
                let fields: Vec<&str> = line.split_whitespace().collect();
                if fields.len() >= 3 {
                    mounts.push(serde_json::json!({
                        "device": fields[0],
                        "mount_point": fields[1],
                        "fs_type": fields[2].to_string(),
                    }));
                }
            }
        }
        return serde_json::json!(mounts);
    }

    #[cfg(target_os = "macos")]
    {
        let mut mounts = Vec::new();
        if let Ok(out) = std::process::Command::new("df").args(["-kP"]).output() {
            let text = String::from_utf8_lossy(&out.stdout);
            for line in text.lines().skip(1) {
                let fields: Vec<&str> = line.split_whitespace().collect();
                if fields.len() >= 6 {
                    mounts.push(serde_json::json!({
                        "device": fields[0],
                        "mount_point": fields[5],
                        "fs_type": fields[1].to_string(),
                    }));
                }
            }
        }
        return serde_json::json!(mounts);
    }

    #[cfg(target_os = "windows")]
    {
        serde_json::json!([])
    }
}

pub fn disks() -> serde_json::Value {
    let disks = sysinfo::Disks::new_with_refreshed_list();

    let list: Vec<serde_json::Value> = disks.iter()
        .map(|d| {
            serde_json::json!({
                "name": d.name().to_string_lossy(),
                "mount_point": d.mount_point().to_string_lossy(),
                "file_system": d.file_system().to_string_lossy(),
                "total_space": d.total_space(),
                "available_space": d.available_space(),
                "is_removable": d.is_removable(),
            })
        })
        .collect();

    serde_json::json!(list)
}

/// Reads the active GTK/desktop theme so the UI can follow the system look.
///
/// Linux: queries `gsettings` from the GNOME/GSettings schemas with a
/// `GTK_THEME` environment fallback. Other platforms report `available: false`.
/// If gsettings is missing, fields fall back to sensible defaults rather than
/// erroring — the UI should treat this as "no system preference".
pub fn gtk() -> serde_json::Value {
    #[cfg(target_os = "linux")]
    {
        use std::process::Command;

        let mut color_scheme: Option<String> = None;
        let mut theme_name: Option<String> = None;
        let mut accent_name: Option<String> = None;

        if let Ok(out) = Command::new("gsettings")
            .args(["get", "org.gnome.desktop.interface", "color-scheme"])
            .output()
        {
            if out.status.success() {
                let v = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if !v.is_empty() {
                    color_scheme = Some(v.trim_matches('\'').to_string());
                }
            }
        }
        if let Ok(out) = Command::new("gsettings")
            .args(["get", "org.gnome.desktop.interface", "gtk-theme"])
            .output()
        {
            if out.status.success() {
                let v = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if !v.is_empty() {
                    theme_name = Some(v.trim_matches('\'').to_string());
                }
            }
        }
        if let Ok(out) = Command::new("gsettings")
            .args(["get", "org.gnome.desktop.interface", "accent-color"])
            .output()
        {
            if out.status.success() {
                let v = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if !v.is_empty() && !v.contains("invalid") {
                    accent_name = Some(v.trim_matches('\'').to_string());
                }
            }
        }

        if theme_name.is_none() {
            theme_name = std::env::var("GTK_THEME").ok().map(|t| t.to_string());
        }

        let desktop = std::env::var("XDG_CURRENT_DESKTOP").ok();

        serde_json::json!({
            "available": true,
            "desktop": desktop,
            "color_scheme": color_scheme,
            "theme_name": theme_name,
            "accent_name": accent_name,
            "accent_hex": accent_hex(accent_name.as_deref()),
        })
    }

    #[cfg(not(target_os = "linux"))]
    {
        let _ = "";
        serde_json::json!({
            "available": false,
            "desktop": std::env::var("XDG_CURRENT_DESKTOP").ok(),
            "color_scheme": std::env::var("GTK_THEME").ok(),
            "theme_name": std::env::var("GTK_THEME").ok(),
            "accent_name": null,
            "accent_hex": null,
        })
    }
}

/// Maps a GNOME accent-colour name (org.gnome.desktop.interface accent-color)
/// to a hex string, so the app can match the desktop accent closely.
#[cfg(target_os = "linux")]
fn accent_hex(name: Option<&str>) -> Option<String> {
    let hex = match name? {
        "blue" => "#3584E4",
        "teal" => "#2197A3",
        "green" => "#2EC27E",
        "yellow" => "#F6D32D",
        "purple" => "#9141AC",
        "red" => "#E01B24",
        "orange" => "#FF7800",
        "slate" => "#4D4D4D",
        "pink" => "#DE35E3",
        _ => return None,
    };
    Some(hex.to_string())
}

#[cfg(not(target_os = "linux"))]
fn accent_hex(_name: Option<&str>) -> Option<String> {
    None
}
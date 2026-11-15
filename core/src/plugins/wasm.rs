//! WASM plugin sandbox.
//!
//! Plugins run in a WebAssembly sandbox with capability-based security:
//! fuel limits, memory limits, and host-controlled imports. Plugins cannot
//! access the filesystem, network, or any system resources unless the host
//! explicitly grants them.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use wasmtime::*;

/// Plugin configuration, loaded from plugin.toml.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PluginConfig {
    pub name: String,
    pub version: String,
    pub runtime: String, // "wasm" or "native"
    pub entry: String,   // path to .wasm file
    #[serde(default)]
    pub permissions: PluginPermissions,
    #[serde(default)]
    pub hooks: PluginHooks,
    #[serde(default)]
    pub config: HashMap<String, serde_json::Value>,
}

/// Capability-based permissions for a WASM plugin.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PluginPermissions {
    /// Can read note content (for on_note hook).
    #[serde(default)]
    pub read_notes: bool,
    /// Can modify notes.
    #[serde(default)]
    pub write_notes: bool,
    /// Can make network requests.
    #[serde(default)]
    pub network: bool,
    /// Allowed filesystem paths to read.
    #[serde(default)]
    pub fs_read: Vec<String>,
    /// Allowed filesystem paths to write.
    #[serde(default)]
    pub fs_write: Vec<String>,
    /// Maximum memory in MB.
    #[serde(default = "default_max_memory_mb")]
    pub max_memory_mb: u32,
    /// Maximum fuel (instructions) per hook call.
    #[serde(default = "default_max_fuel")]
    pub max_fuel: u64,
}

fn default_max_memory_mb() -> u32 {
    64
}

fn default_max_fuel() -> u64 {
    10_000_000
}

/// Which hooks a plugin implements.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PluginHooks {
    #[serde(default)]
    pub on_note: bool,
    #[serde(default)]
    pub on_export: bool,
    #[serde(default)]
    pub on_startup: bool,
}

/// Context passed to a plugin's on_note hook.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoteContext {
    pub path: String,
    pub title: String,
    pub body: String,
    pub frontmatter: HashMap<String, serde_json::Value>,
}

/// Result returned by a plugin's on_note hook.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PluginResult {
    /// Feedback message to show the user.
    #[serde(default)]
    pub feedback: Option<String>,
    /// Frontmatter patch to apply to the note.
    #[serde(default)]
    pub frontmatter_patch: Option<HashMap<String, serde_json::Value>>,
    /// Suggested commands for the command palette.
    #[serde(default)]
    pub commands: Vec<String>,
}

/// A loaded WASM plugin with its sandbox.
pub struct WasmPlugin {
    /// The plugin configuration.
    config: PluginConfig,
    /// The WASM engine.
    engine: Engine,
    /// The WASM store.
    store: Store<()>,
    /// The WASM instance.
    instance: Instance,
    /// The WASM memory.
    memory: Memory,
    /// The on_note exported function (if the plugin implements it).
    on_note_func: Option<TypedFunc<(i32, i32), i32>>,
    /// The on_export exported function (if the plugin implements it).
    on_export_func: Option<TypedFunc<(i32, i32), i32>>,
    /// The on_startup exported function (if the plugin implements it).
    on_startup_func: Option<TypedFunc<(), i32>>,
}

impl WasmPlugin {
    /// Load and instantiate a WASM plugin from a .wasm file.
    pub fn load(wasm_bytes: &[u8], config: PluginConfig) -> Result<Self, String> {
        let engine = Engine::new(
            &Config::new()
                .consume_fuel(true)
                .static_memory_maximum_size(
                    config.permissions.max_memory_mb as u64 * 1024 * 1024,
                ),
        )
        .map_err(|e| format!("failed to create WASM engine: {e}"))?;

        let mut store = Store::new(&engine, ());
        store.set_fuel(config.permissions.max_fuel)
            .map_err(|e| format!("failed to set fuel: {e}"))?;

        let module = Module::new(&engine, wasm_bytes)
            .map_err(|e| format!("failed to compile WASM module: {e}"))?;

        let config_name = config.name.clone();
        let config_network = config.permissions.network;
        let config_read_notes = config.permissions.read_notes;

        let mut linker = Linker::new(&engine);

        // Define host functions based on permissions.
        if config_read_notes {
            linker.func_wrap(
                "host",
                "log",
                move |mut caller: Caller<'_, ()>,
                      level_ptr: i32,
                      level_len: i32,
                      msg_ptr: i32,
                      msg_len: i32| {
                    let memory = caller.get_export("memory").unwrap().into_memory().unwrap();
                    let data = memory.data(&caller);
                    let level = String::from_utf8_lossy(
                        &data[level_ptr as usize..(level_ptr + level_len) as usize],
                    );
                    let msg = String::from_utf8_lossy(
                        &data[msg_ptr as usize..(msg_ptr + msg_len) as usize],
                    );
                    eprintln!("[plugin {}] {}: {}", config_name, level, msg);
                },
            )
            .map_err(|e| format!("failed to define host log: {e}"))?;
        }

        if config_network {
            linker.func_wrap(
                "host",
                "http_get",
                move |mut caller: Caller<'_, ()>,
                      url_ptr: i32,
                      url_len: i32,
                      out_ptr: i32,
                      out_len: i32| {
                    let memory = caller.get_export("memory").unwrap().into_memory().unwrap();
                    let data = memory.data(&caller);
                    let url = String::from_utf8_lossy(
                        &data[url_ptr as usize..(url_ptr + url_len) as usize],
                    );
                    match reqwest::blocking::get(url.as_ref()) {
                        Ok(resp) => {
                            let body = resp.text().unwrap_or_default();
                            let body_bytes = body.as_bytes();
                            let write_len = body_bytes.len().min(out_len as usize);
                            memory
                                .write(
                                    &mut caller,
                                    out_ptr as usize,
                                    &body_bytes[..write_len],
                                )
                                .ok();
                            write_len as i32
                        }
                        Err(_) => -1,
                    }
                },
            )
            .map_err(|e| format!("failed to define host http_get: {e}"))?;
        }

        let instance = linker
            .instantiate(&mut store, &module)
            .map_err(|e| format!("failed to instantiate WASM module: {e}"))?;

        let memory = instance
            .get_export(&mut store, "memory")
            .unwrap()
            .into_memory()
            .unwrap()
            .clone();

        // Look up exported functions.
        let on_note_func = instance
            .get_typed_func::<(i32, i32), i32>(&mut store, "on_note")
            .ok();

        let on_export_func = instance
            .get_typed_func::<(i32, i32), i32>(&mut store, "on_export")
            .ok();

        let on_startup_func = instance
            .get_typed_func::<(), i32>(&mut store, "on_startup")
            .ok();

        Ok(Self {
            config,
            engine,
            store,
            instance,
            memory,
            on_note_func,
            on_export_func,
            on_startup_func,
        })
    }

    /// Call the plugin's on_note hook with a note context.
    pub fn on_note(&mut self, context: &NoteContext) -> Result<PluginResult, String> {
        let on_note_func = self.on_note_func.clone();
        let Some(func) = on_note_func else {
            return Ok(PluginResult::default());
        };

        self.store.set_fuel(self.config.permissions.max_fuel)
            .map_err(|e| format!("failed to set fuel: {e}"))?;

        let context_json = serde_json::to_string(context)
            .map_err(|e| format!("failed to serialize context: {e}"))?;
        let context_bytes = context_json.as_bytes();

        let ptr = self.allocate_memory(context_bytes)?;
        let len = context_bytes.len() as i32;

        let result_ptr = func
            .call(&mut self.store, (ptr, len))
            .map_err(|e| format!("plugin on_note failed: {e}"))?;

        let result = self.read_memory(result_ptr)?;
        let result: PluginResult = serde_json::from_slice(&result)
            .map_err(|e| format!("failed to parse plugin result: {e}"))?;

        Ok(result)
    }

    /// Call the plugin's on_export hook.
    pub fn on_export(&mut self, context: &NoteContext) -> Result<PluginResult, String> {
        let on_export_func = self.on_export_func.clone();
        let Some(func) = on_export_func else {
            return Ok(PluginResult::default());
        };

        self.store.set_fuel(self.config.permissions.max_fuel)
            .map_err(|e| format!("failed to set fuel: {e}"))?;

        let context_json = serde_json::to_string(context)
            .map_err(|e| format!("failed to serialize context: {e}"))?;
        let context_bytes = context_json.as_bytes();

        let ptr = self.allocate_memory(context_bytes)?;
        let len = context_bytes.len() as i32;

        let result_ptr = func
            .call(&mut self.store, (ptr, len))
            .map_err(|e| format!("plugin on_export failed: {e}"))?;

        let result = self.read_memory(result_ptr)?;
        let result: PluginResult = serde_json::from_slice(&result)
            .map_err(|e| format!("failed to parse plugin result: {e}"))?;

        Ok(result)
    }

    /// Call the plugin's on_startup hook.
    pub fn on_startup(&mut self) -> Result<(), String> {
        let Some(func) = &self.on_startup_func else {
            return Ok(());
        };

        self.store.set_fuel(self.config.permissions.max_fuel)
            .map_err(|e| format!("failed to set fuel: {e}"))?;

        func.call(&mut self.store, ())
            .map(|_| ())
            .map_err(|e| format!("plugin on_startup failed: {e}"))
    }

    /// Allocate memory in the WASM instance and write data to it.
    fn allocate_memory(&mut self, data: &[u8]) -> Result<i32, String> {
        let current_len = self.memory.data_size(&self.store);
        let new_len = current_len + data.len();

        // Grow memory if needed (64KB per page).
        let pages_needed = ((new_len as f64) / 65536.0).ceil() as u64;
        let current_pages = self.memory.size(&self.store);
        if pages_needed > current_pages {
            self.memory
                .grow(&mut self.store, pages_needed - current_pages)
                .map_err(|e| format!("failed to grow memory: {e}"))?;
        }

        // Write data at the end of current memory.
        self.memory
            .write(
                &mut self.store,
                current_len.try_into().unwrap(),
                data,
            )
            .map_err(|e| format!("failed to write memory: {e}"))?;

        Ok(current_len as i32)
    }

    /// Read data from WASM memory starting at a pointer until a null byte.
    fn read_memory(&self, ptr: i32) -> Result<Vec<u8>, String> {
        let data = self.memory.data(&self.store);

        // Find the null terminator.
        let start = ptr as usize;
        let mut end = start;
        while end < data.len() && data[end] != 0 {
            end += 1;
        }

        Ok(data[start..end].to_vec())
    }
}

impl Drop for WasmPlugin {
    fn drop(&mut self) {
        // The WASM instance is dropped here, releasing all resources.
    }
}

/// The plugin host manages loaded plugins and dispatches hooks to them.
pub struct PluginHost {
    plugins: HashMap<String, WasmPlugin>,
}

impl PluginHost {
    /// Create a new empty plugin host.
    pub fn new() -> Self {
        Self {
            plugins: HashMap::new(),
        }
    }

    /// Load a plugin from a WASM file.
    pub fn load_plugin(
        &mut self,
        wasm_bytes: &[u8],
        config: PluginConfig,
    ) -> Result<(), String> {
        let plugin = WasmPlugin::load(wasm_bytes, config)?;
        let name = plugin.config.name.clone();
        self.plugins.insert(name.clone(), plugin);
        eprintln!("Loaded WASM plugin: {}", name);
        Ok(())
    }

    /// Call on_note on all plugins that implement it.
    pub fn on_note(&mut self, context: &NoteContext) -> Vec<PluginResult> {
        let mut results = Vec::new();
        for plugin in self.plugins.values_mut() {
            if plugin.config.hooks.on_note {
                if let Ok(result) = plugin.on_note(context) {
                    results.push(result);
                }
            }
        }
        results
    }

    /// Call on_export on all plugins that implement it.
    pub fn on_export(&mut self, context: &NoteContext) -> Vec<PluginResult> {
        let mut results = Vec::new();
        for plugin in self.plugins.values_mut() {
            if plugin.config.hooks.on_export {
                if let Ok(result) = plugin.on_export(context) {
                    results.push(result);
                }
            }
        }
        results
    }

    /// Call on_startup on all plugins that implement it.
    pub fn on_startup(&mut self) -> Vec<Result<(), String>> {
        let mut results = Vec::new();
        for plugin in self.plugins.values_mut() {
            if plugin.config.hooks.on_startup {
                results.push(plugin.on_startup());
            }
        }
        results
    }

    /// List loaded plugin names.
    pub fn plugin_names(&self) -> Vec<String> {
        self.plugins.keys().cloned().collect()
    }
}

impl Default for PluginHost {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_plugin_config_default() {
        let config = PluginConfig {
            name: "test".to_string(),
            version: "1.0.0".to_string(),
            runtime: "wasm".to_string(),
            entry: "test.wasm".to_string(),
            permissions: PluginPermissions {
                max_memory_mb: 64,
                max_fuel: 10_000_000,
                ..Default::default()
            },
            hooks: PluginHooks::default(),
            config: HashMap::new(),
        };
        assert_eq!(config.permissions.max_memory_mb, 64);
        assert_eq!(config.permissions.max_fuel, 10_000_000);
        assert!(!config.permissions.read_notes);
        assert!(!config.permissions.network);
    }

    #[test]
    fn test_plugin_result_default() {
        let result = PluginResult::default();
        assert!(result.feedback.is_none());
        assert!(result.frontmatter_patch.is_none());
        assert!(result.commands.is_empty());
    }

    #[test]
    fn test_note_context() {
        let mut frontmatter = HashMap::new();
        frontmatter.insert("tags".to_string(), serde_json::json!(["work"]));
        let ctx = NoteContext {
            path: "test.md".to_string(),
            title: "Test".to_string(),
            body: "Hello world".to_string(),
            frontmatter,
        };
        assert_eq!(ctx.path, "test.md");
        assert_eq!(ctx.title, "Test");
    }

    #[test]
    fn test_plugin_host_create_and_list() {
        let mut host = PluginHost::new();
        assert_eq!(host.plugin_names(), Vec::<String>::new());
        assert!(host.load_plugin(b"wasm", PluginConfig::default()).is_err());
    }

    #[test]
    fn test_plugin_config_serialization() {
        let config = PluginConfig {
            name: "test-plugin".to_string(),
            version: "1.0.0".to_string(),
            runtime: "wasm".to_string(),
            entry: "test-plugin.wasm".to_string(),
            permissions: PluginPermissions {
                read_notes: true,
                write_notes: false,
                network: false,
                fs_read: vec!["notes/".to_string()],
                fs_write: vec![],
                max_memory_mb: 128,
                max_fuel: 5_000_000,
            },
            hooks: PluginHooks {
                on_note: true,
                on_export: false,
                on_startup: true,
            },
            config: HashMap::from([("key".to_string(), serde_json::Value::String("value".to_string()))]),
        };

        let json = serde_json::to_string(&config).unwrap();
        let deserialized: PluginConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.name, "test-plugin");
        assert_eq!(deserialized.permissions.max_memory_mb, 128);
        assert_eq!(deserialized.permissions.max_fuel, 5_000_000);
        assert!(deserialized.permissions.read_notes);
        assert!(!deserialized.permissions.write_notes);
        assert!(deserialized.hooks.on_note);
        assert!(!deserialized.hooks.on_export);
        assert!(deserialized.hooks.on_startup);
    }

    #[test]
    fn test_plugin_result_serialization() {
        let mut frontmatter_patch = HashMap::new();
        frontmatter_patch.insert("tags".to_string(), serde_json::json!(["work"]));

        let result = PluginResult {
            feedback: Some("Added tag".to_string()),
            frontmatter_patch: Some(frontmatter_patch),
            commands: vec!["journal.openDailyNote".to_string()],
        };

        let json = serde_json::to_string(&result).unwrap();
        let deserialized: PluginResult = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.feedback, Some("Added tag".to_string()));
        assert_eq!(
            deserialized
                .frontmatter_patch
                .unwrap()
                .get("tags")
                .cloned(),
            Some(serde_json::json!(["work"]))
        );
        assert_eq!(deserialized.commands, vec!["journal.openDailyNote".to_string()]);
    }
}

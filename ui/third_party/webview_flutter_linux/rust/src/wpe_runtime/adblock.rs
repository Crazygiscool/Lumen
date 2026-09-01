// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Native request-level ad blocker for the web-process extension.
//!
//! The federated `webview_flutter` API exposes no content-rule surface, so
//! Lumen ships blocking rules as a compact binary table that the web-process
//! extension evaluates inline at the `send-request` interception point — before
//! page JavaScript runs and for every resource type WebKit knows.
//!
//! Rules are expressed as URL regular expressions plus an optional
//! include/exclude domain scope and an optional resource-type bitmask. This
//! module is deliberately independent of WPE and GLib so the matcher can be
//! unit-tested in isolation; the extension merely feeds URL + type into
//! [`RuleTable::should_block`].

use std::sync::{Mutex, OnceLock};

use regex::bytes::Regex;

/// Magic identifying the rule-table binary blob.
pub(super) const BLOB_MAGIC: &[u8; 8] = b"LUNALB1\0";
const ADBLOCK_VERSION: u64 = 1;

/// Resource-type bits. A rule with a zero mask matches every resource type.
pub(super) const TYPE_OTHER: u32 = 1 << 12;
pub(super) const TYPE_DOCUMENT: u32 = 1 << 0;
pub(super) const TYPE_IMAGE: u32 = 1 << 1;
pub(super) const TYPE_STYLESHEET: u32 = 1 << 2;
pub(super) const TYPE_SCRIPT: u32 = 1 << 3;
pub(super) const TYPE_FONT: u32 = 1 << 4;
pub(super) const TYPE_RAW: u32 = 1 << 5; // XHR / fetch
pub(super) const TYPE_SVG_DOCUMENT: u32 = 1 << 6;
pub(super) const TYPE_MEDIA: u32 = 1 << 7;
pub(super) const TYPE_PING: u32 = 1 << 8;
pub(super) const TYPE_FETCH: u32 = 1 << 9;
pub(super) const TYPE_WEBSOCKET: u32 = 1 << 10;
pub(super) const TYPE_POPUP: u32 = 1 << 11;
/// Requests whose `Sec-Fetch-Dest` is empty (XHR/fetch/beacon and friends).
pub(super) const TYPE_EMPTY_MASK: u32 = TYPE_RAW | TYPE_FETCH | TYPE_PING;

/// A single compiled blocking or exception rule.
struct Rule {
    regex: Regex,
    types: u32,
    if_domains: Vec<Vec<u8>>,
    unless_domains: Vec<Vec<u8>>,
}

/// Snapshot of the currently installed blocking table.
struct RuleTable {
    version: u64,
    blocks: Vec<Rule>,
    exceptions: Vec<Rule>,
}

// The web-process extension owns the table. Matching happens on WebKit's main
// loop (single-threaded), so a lightweight mutex guards reloads against reads.
static TABLE: OnceLock<Mutex<RuleTable>> = OnceLock::new();

fn table() -> &'static Mutex<RuleTable> {
    TABLE.get_or_init(|| {
        Mutex::new(RuleTable { version: 0, blocks: Vec::new(), exceptions: Vec::new() })
    })
}

fn domain_matches(rule_domain: &[u8], host: &[u8]) -> bool {
    if rule_domain.is_empty() {
        return false;
    }
    if host.len() == rule_domain.len() && host.eq_ignore_ascii_case(rule_domain) {
        return true;
    }
    host.len() > rule_domain.len()
        && host[host.len() - rule_domain.len() - 1] == b'.'
        && host[host.len() - rule_domain.len()..].eq_ignore_ascii_case(rule_domain)
}

fn domains_ok(rule: &Rule, host: &[u8]) -> bool {
    if !rule.if_domains.is_empty() {
        let mut hit = false;
        for d in &rule.if_domains {
            if domain_matches(d, host) {
                hit = true;
                break;
            }
        }
        if !hit {
            return false;
        }
    }
    for d in &rule.unless_domains {
        if domain_matches(d, host) {
            return false;
        }
    }
    true
}

/// Returns the host portion of `url` (lowercased) for domain scoping.
pub(super) fn host_of(url: &[u8]) -> Vec<u8> {
    let s = std::str::from_utf8(url).unwrap_or("");
    let authority = if let Some(rest) = s.split_once("://") {
        let end = rest.1.find(['/', '?', '#']).unwrap_or(rest.1.len());
        &rest.1[..end]
    } else {
        let end = s.find(['/', '?', '#']).unwrap_or(s.len());
        &s[..end]
    };
    if let Some(rest) = authority.strip_prefix('[') {
        if let Some(end) = rest.find(']') {
            return rest[..end].to_ascii_lowercase().into_bytes();
        }
    }
    authority
        .split(':')
        .next()
        .unwrap_or(authority)
        .to_ascii_lowercase()
        .into_bytes()
}

impl RuleTable {
    fn should_block(&self, url: &str, types: u32, host: &[u8]) -> bool {
        // Exceptions override blocks.
        for rule in &self.exceptions {
            if rule.types & types == 0 && rule.types != 0 {
                continue;
            }
            if domains_ok(rule, host) && rule.regex.is_match(url.as_bytes()) {
                return false;
            }
        }
        for rule in &self.blocks {
            if rule.types & types == 0 && rule.types != 0 {
                continue;
            }
            if domains_ok(rule, host) && rule.regex.is_match(url.as_bytes()) {
                return true;
            }
        }
        false
    }
}

/// Redirected URL regular expressions may contain a leading `|` (uBO anchor).
fn compile_regex(pattern: &[u8]) -> Result<Regex, ()> {
    Regex::new(std::str::from_utf8(pattern).map_err(|_| ())?).map_err(|_| ())
}

/// Parses the compact rule blob produced by the Flutter side.
fn parse_blob(blob: &[u8]) -> Result<RuleTable, ()> {
    let mut p = Cursor::new(blob);
    let magic = p.take(8).ok_or(())?;
    if magic != BLOB_MAGIC {
        return Err(());
    }
    let version = p.u64().ok_or(())?;
    let num_blocks = p.u64().ok_or(())? as usize;
    let num_exceptions = p.u64().ok_or(())? as usize;
    if num_blocks > 2_000_000 || num_exceptions > 2_000_000 {
        return Err(());
    }
    let mut blocks = Vec::with_capacity(num_blocks);
    for _ in 0..num_blocks {
        // Reject regexes that the environment cannot compile so one bad rule
        // cannot disable the whole table.
        if let Ok(rule) = parse_rule(&mut p) {
            blocks.push(rule);
        }
    }
    let mut exceptions = Vec::with_capacity(num_exceptions);
    for _ in 0..num_exceptions {
        if let Ok(rule) = parse_rule(&mut p) {
            exceptions.push(rule);
        }
    }
    Ok(RuleTable { version, blocks, exceptions })
}

fn parse_rule(p: &mut Cursor) -> Result<Rule, ()> {
    let regex_len = p.u32().ok_or(())? as usize;
    let regex_bytes = p.take(regex_len).ok_or(())?;
    let regex = compile_regex(regex_bytes)?;
    let types = p.u32().ok_or(())?;
    let if_domains = read_domains(p)?;
    let unless_domains = read_domains(p)?;
    Ok(Rule {
        regex,
        types,
        if_domains,
        unless_domains,
    })
}

fn read_domains(p: &mut Cursor) -> Result<Vec<Vec<u8>>, ()> {
    let count = p.u32().ok_or(())? as usize;
    if count > 1024 {
        return Err(());
    }
    let mut out = Vec::with_capacity(count);
    for _ in 0..count {
        let len = p.u32().ok_or(())? as usize;
        out.push(p.take(len).ok_or(())?.to_vec());
    }
    Ok(out)
}

struct Cursor<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Cursor<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, pos: 0 }
    }
    fn take(&mut self, n: usize) -> Option<&'a [u8]> {
        let end = self.pos.checked_add(n)?;
        let slice = self.bytes.get(self.pos..end)?;
        self.pos = end;
        Some(slice)
    }
    fn u64(&mut self) -> Option<u64> {
        Some(u64::from_le_bytes(self.take(8)?.try_into().ok()?))
    }
    fn u32(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.take(4)?.try_into().ok()?))
    }
}

/// Loads `blob` into the process-global table, returning its version.
pub(super) fn install_rules(blob: &[u8]) -> Result<u64, ()> {
    let parsed = parse_blob(blob)?;
    let version = parsed.version;
    let mut guard = table().lock().unwrap_or_else(|p| p.into_inner());
    *guard = parsed;
    Ok(version)
}

/// Returns the version of the currently installed table (0 if none).
pub(super) fn installed_version() -> u64 {
    table().lock().unwrap_or_else(|p| p.into_inner()).version
}

/// Whether a request to `url` of type `types` should be blocked.
///
/// `url` is the full request URL; the host is derived internally. A missing
/// table never blocks.
pub(super) fn should_block(url: &str, types: u32) -> bool {
    let guard = table().lock().unwrap_or_else(|p| p.into_inner());
    if guard.version == 0 {
        return false;
    }
    let host = host_of(url.as_bytes());
    guard.should_block(url, types, &host)
}

/// True if no blocking rules are installed.
pub(super) fn is_empty() -> bool {
    table().lock().unwrap_or_else(|p| p.into_inner()).blocks.is_empty()
}

/// Maps WebKit's `Sec-Fetch-Dest` header value onto a resource-type bitmask.
///
/// Navigation destinations (`document`, `iframe`, `frame`) return `None`: these
/// are handled by the navigation policy gate, never by the subresource blocker.
pub(super) fn resource_type_from_fetch_destination(destination: &[u8]) -> Option<u32> {
    if destination.eq_ignore_ascii_case(b"document") {
        return None;
    }
    if destination.eq_ignore_ascii_case(b"iframe") || destination.eq_ignore_ascii_case(b"frame") {
        return None;
    }
    if destination.is_empty() || destination.eq_ignore_ascii_case(b"empty") {
        return Some(TYPE_EMPTY_MASK);
    }
    Some(match destination.to_ascii_lowercase().as_slice() {
        b"image" => TYPE_IMAGE,
        b"style" | b"stylesheet" => TYPE_STYLESHEET,
        b"script" => TYPE_SCRIPT,
        b"font" => TYPE_FONT,
        b"audio" | b"video" | b"track" => TYPE_MEDIA,
        b"websocket" => TYPE_WEBSOCKET,
        b"manifest" | b"embed" | b"object" | b"webidentity" | b"worker" | b"sharedworker" => {
            TYPE_OTHER
        }
        _ => TYPE_OTHER,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn blob(version: u64, blocks: &[&str], exceptions: &[&str]) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(BLOB_MAGIC);
        out.extend_from_slice(&version.to_le_bytes());
        out.extend_from_slice(&(blocks.len() as u64).to_le_bytes());
        out.extend_from_slice(&(exceptions.len() as u64).to_le_bytes());
        for pattern in blocks {
            write_rule(&mut out, pattern, 0, &[], &[]);
        }
        for pattern in exceptions {
            write_rule(&mut out, pattern, 0, &[], &[]);
        }
        out
    }

    fn write_rule(out: &mut Vec<u8>, pattern: &str, types: u32, ifd: &[&str], unld: &[&str]) {
        out.extend_from_slice(&(pattern.len() as u32).to_le_bytes());
        out.extend_from_slice(pattern.as_bytes());
        out.extend_from_slice(&types.to_le_bytes());
        out.extend_from_slice(&(ifd.len() as u32).to_le_bytes());
        for d in ifd {
            out.extend_from_slice(&(d.len() as u32).to_le_bytes());
            out.extend_from_slice(d.as_bytes());
        }
        out.extend_from_slice(&(unld.len() as u32).to_le_bytes());
        for d in unld {
            out.extend_from_slice(&(d.len() as u32).to_le_bytes());
            out.extend_from_slice(d.as_bytes());
        }
    }

    #[test]
    fn parses_and_blocks_url() {
        let b = blob(1, &[r"^https?://ads\.example\.com"], &[]);
        install_rules(&b).unwrap();
        assert!(should_block("https://ads.example.com/banner.png", TYPE_IMAGE));
        assert!(!should_block("https://example.com/page", TYPE_DOCUMENT));
    }

    #[test]
    fn exception_overrides_block() {
        let b = blob(1, &[r"ads\.example\.com"], &[r"^https?://ads\.example\.com/allowed"]);
        install_rules(&b).unwrap();
        assert!(!should_block("https://ads.example.com/allowed/x", TYPE_RAW));
        assert!(should_block("https://ads.example.com/blocked", TYPE_RAW));
    }

    #[test]
    fn host_extraction() {
        assert_eq!(host_of(b"https://Sub.Example.com:8080/path?q=1"), b"sub.example.com");
        assert_eq!(host_of(b"http://example.com"), b"example.com");
        assert_eq!(host_of(b"example.org/a"), b"example.org");
        assert_eq!(host_of(b"[::1]:80/x"), b"::1");
    }

    #[test]
    fn no_table_blocks_nothing() {
        // Ensure a fresh process with no install does not block.
        // (A prior test installed a table; reload model is process-global, so
        // verify against a patched blob of version 0 instead.)
        let b = blob(0, &[r"ads"], &[]);
        install_rules(&b).unwrap();
        assert!(!should_block("http://ads.example.com/x", TYPE_IMAGE));
    }

    #[test]
    fn empty_blob_is_empty() {
        let b = blob(1, &[], &[]);
        install_rules(&b).unwrap();
        assert!(is_empty());
        assert!(!should_block("http://anything.com/x", TYPE_RAW));
    }
}

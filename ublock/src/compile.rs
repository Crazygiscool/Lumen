//! Compilation orchestration: parse lists → apply `$badfilter` → convert →
//! dedupe → order → emit WebKit content-rule JSON parts within WebKit's caps.

use crate::convert::{convert_cosmetic, convert_network, Converted, Skip};
use crate::filter::{parse_line, FilterLine, SkipReasons};
use serde_json::{json, Value};
use std::collections::HashMap;

/// WebKit's documented per-store caps. We stay safely below them so parts stay
/// within the combined limit.
pub const MAX_RULES_PER_PART: usize = 40_000;
pub const MAX_ABILITIES_PER_PART: usize = 120_000;

/// A parsed input list.
pub struct ListInput<'a> {
    pub text: &'a str,
}

/// Compilation statistics reported to Dart.
#[derive(Debug, Default)]
pub struct CompileStats {
    pub total_lines: usize,
    pub network_blocked: usize,
    pub exceptions: usize,
    pub cosmetic: usize,
    pub important: usize,
    pub badfilter_encountered: usize,
    pub badfilter_removed: usize,
    pub skipped: SkipReasons,
}

/// Result of a compile run.
pub struct Compiled {
    pub parts: Vec<String>,
    pub stats: CompileStats,
}

/// Compiles a set of filter lists into WebKit content-rule JSON parts.
pub fn compile(lists: &[ListInput], max_rules: Option<usize>) -> Result<Compiled, String> {
    let max_rules = max_rules.unwrap_or(MAX_RULES_PER_PART).clamp(1, MAX_RULES_PER_PART);
    let mut stats = CompileStats::default();

    let mut networks: Vec<crate::filter::NetworkFilter> = Vec::new();
    let mut cosmetics: Vec<crate::filter::CosmeticFilter> = Vec::new();
    let mut badfilters: Vec<String> = Vec::new();

    for list in lists {
        for raw in list.text.lines() {
            let line = raw.trim();
            if line.is_empty() || line.starts_with('!') || line.starts_with('[') {
                continue;
            }
            stats.total_lines += 1;
            match parse_line(line) {
                Some(FilterLine::Network(n)) => networks.push(n),
                Some(FilterLine::Cosmetic(c)) => cosmetics.push(c),
                Some(FilterLine::BadFilter(p)) => badfilters.push(p),
                None => {
                    let reason = classify_skip(line);
                    *stats.skipped.entry(reason).or_insert(0) += 1;
                }
            }
        }
    }

    apply_badfilter(&mut networks, &badfilters, &mut stats);

    // Convert network filters.
    let mut converted: Vec<Converted> = Vec::new();
    for n in &networks {
        match convert_network(n) {
            Ok(c) => {
                match c.bucket {
                    0 => stats.network_blocked += 1,
                    1 => stats.exceptions += 1,
                    _ => stats.important += 1,
                }
                converted.push(c);
            }
            Err(skip) => record_skip(&mut stats, &skip),
        }
    }

    // Convert cosmetic filters (one rule per domain).
    for c in &cosmetics {
        match convert_cosmetic(c) {
            Ok(rules) => {
                for r in rules {
                    stats.cosmetic += 1;
                    converted.push(r);
                }
            }
            Err(skip) => record_skip(&mut stats, &skip),
        }
    }

    // Dedup within a bucket by canonical key.
    let mut seen: HashMap<(u8, String), ()> = HashMap::new();
    converted.retain(|c| seen.insert((c.bucket, c.key.clone()), ()).is_none());

    // Order: normal blocks (0) → exceptions (1) → important blocks (2), so
    // `ignore-previous-rules` can cancel earlier blocks and $important blocks
    // land last and win.
    converted.sort_by_key(|c| c.bucket);

    let parts = emit_parts(&converted, max_rules);
    Ok(Compiled { parts, stats })
}

fn record_skip(stats: &mut CompileStats, skip: &Skip) {
    let reason = match skip {
        Skip::UnsupportedPattern(_) => "unsupported-pattern".to_string(),
        Skip::MixedDomains => "mixed-domains".to_string(),
        Skip::UnsupportedSelector(_) => "procedural-selector".to_string(),
    };
    *stats.skipped.entry(reason).or_insert(0) += 1;
}

/// `$badfilter[p]` deletes every pending rule whose raw pattern is exactly `p`.
fn apply_badfilter(
    networks: &mut Vec<crate::filter::NetworkFilter>,
    badfilters: &[String],
    stats: &mut CompileStats,
) {
    stats.badfilter_encountered = badfilters.len();
    if badfilters.is_empty() {
        return;
    }
    let before = networks.len();
    networks.retain(|n| !badfilters.iter().any(|b| b == &n.pattern));
    stats.badfilter_removed = before - networks.len();
}

/// Emits ordered rules as JSON parts, splitting when a part would exceed the
/// per-part rule or ability caps.
fn emit_parts(converted: &[Converted], max_rules: usize) -> Vec<String> {
    let mut parts: Vec<String> = Vec::new();
    let mut current: Vec<Value> = Vec::new();
    let mut rules = 0usize;
    let mut abilities = 0usize;

    for c in converted {
        let a = c.abilities.max(1);
        if !current.is_empty()
            && (rules + 1 > max_rules || abilities + a > MAX_ABILITIES_PER_PART)
        {
            parts.push(Value::Array(std::mem::take(&mut current)).to_string());
            rules = 0;
            abilities = 0;
        }
        rules += 1;
        abilities += a;
        current.push(c.json.clone());
    }
    if !current.is_empty() {
        parts.push(Value::Array(current).to_string());
    }
    parts
}

/// Summarises compile stats for the FFI envelope.
pub fn stats_json(stats: &CompileStats) -> Value {
    json!({
        "total_lines": stats.total_lines,
        "network_blocked": stats.network_blocked,
        "exceptions": stats.exceptions,
        "cosmetic": stats.cosmetic,
        "important": stats.important,
        "badfilter_encountered": stats.badfilter_encountered,
        "badfilter_removed": stats.badfilter_removed,
        "skipped": stats.skipped,
    })
}

/// Labels the reason a line was rejected, for statistics. Conservative and
/// approximate — the source of truth for representability is `parse_line`.
fn classify_skip(line: &str) -> String {
    if line.find("##").is_some() {
        let sel = line.split_once("##").map(|(_, s)| s).unwrap_or("");
        if sel.starts_with('+') {
            return "scriptlet".into();
        }
        if sel.starts_with('?') {
            return "procedural-cosmetic".into();
        }
        if sel.starts_with('$') {
            return "css-injection".into();
        }
        if sel.starts_with('^') {
            return "html-filtering".into();
        }
        if sel.contains(':') {
            return "procedural-selector".into();
        }
        if line.contains('~') {
            return "cosmetic-exclusion".into();
        }
        return "cosmetic-parse".into();
    }
    if line.contains("#@#") {
        return "cosmetic-exception".into();
    }
    if line.contains('#') {
        return "cosmetic-variant".into();
    }
    let rest = line.strip_prefix("@@").unwrap_or(line);
    let opts = rest.split('$').nth(1).unwrap_or("");
    for t in opts.split(',') {
        if t.is_empty() {
            continue;
        }
        let key = t.split('=').next().unwrap_or(t);
        if key == "badfilter" {
            // handled as an instruction elsewhere, should not reach here
            continue;
        }
        if matches!(
            key,
            "xmlhttprequest"
                | "xhr"
                | "fetch"
                | "websocket"
                | "ping"
                | "beacon"
                | "other"
                | "object"
                | "object-subrequest"
        ) {
            return "unsupported-resource-type".into();
        }
        if matches!(
            key,
            "removeparam"
                | "redirect"
                | "redirect-rule"
                | "csp"
                | "responseheader"
                | "cookie"
                | "urlskip"
                | "permissions"
                | "cname"
                | "sitekey"
                | "webrtc"
                | "denyallow"
                | "from"
                | "empty"
                | "mp4"
                | "rewrite"
                | "stealth"
                | "strict"
                | "generichide"
                | "elemhide"
        ) {
            return "unsupported-option".into();
        }
    }
    if rest.starts_with('/') && rest.ends_with('/') {
        return "regex-pattern".into();
    }
    "network-pattern".into()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn compile_small(lists: &[(&str, &str)]) -> Compiled {
        let inputs: Vec<ListInput> = lists
            .iter()
            .map(|(_, t)| ListInput { text: t })
            .collect();
        compile(&inputs, Some(400)).expect("compiles ok")
    }

    #[test]
    fn empty_input() {
        let c = compile_small(&[("x", "")]);
        assert!(c.parts.is_empty());
        assert_eq!(c.stats.total_lines, 0);
    }

    #[test]
    fn basic_compile() {
        let c = compile_small(&[(
            "test",
            "! header\n||ads.example.com^$script\n@@||safe.example.com\n##.ad-banner\n",
        )]);
        assert_eq!(c.stats.network_blocked, 1);
        assert_eq!(c.stats.exceptions, 1);
        assert_eq!(c.stats.cosmetic, 1);
        assert_eq!(c.parts.len(), 1);
        let v: Value = serde_json::from_str(&c.parts[0]).unwrap();
        let arr = v.as_array().unwrap();
        assert_eq!(arr.len(), 3);
        let t0 = arr[0]["action"]["type"].as_str().unwrap();
        let t1 = arr[1]["action"]["type"].as_str().unwrap();
        assert!(t0 == "block" || t0 == "css-display-none");
        assert!(t1 == "block" || t1 == "css-display-none");
        assert_ne!(t0, t1); // they must be different
        assert_eq!(arr[2]["action"]["type"], "ignore-previous-rules");
    }

    #[test]
    fn badfilter_removes_rules() {
        let c = compile_small(&[(
            "t",
            "||ads.example.com^$script\n||ads.example.com^$script,badfilter\n",
        )]);
        assert_eq!(c.stats.badfilter_encountered, 1);
        assert_eq!(c.stats.badfilter_removed, 1);
        assert_eq!(c.stats.network_blocked, 0);
    }

    #[test]
    fn skips_are_counted() {
        let c = compile_small(&[(
            "t",
            "||x.com^$xmlhttprequest\n##div:has(.ad)\n@intrack\n",
        )]);
        assert!(c.stats.skipped.contains_key("unsupported-resource-type"));
        assert!(c.stats.skipped.contains_key("procedural-selector"));
    }

    #[test]
    fn important_last() {
        let c = compile_small(&[(
            "t",
            "||ads.example.com^$important\n||ads.example.com^$script\n",
        )]);
        let v: Value = serde_json::from_str(&c.parts[0]).unwrap();
        let arr = v.as_array().unwrap();
        // important block emitted after the normal block
        assert_eq!(arr.len(), 2);
    }

    #[test]
    fn part_split() {
        let mut text = String::new();
        for i in 0..500 {
            text.push_str(&format!("||ad{i}.example.com^$script\n"));
        }
        let c = compile(&[ListInput { text: &text }], Some(100)).unwrap();
        assert!(c.parts.len() > 1);
    }
}
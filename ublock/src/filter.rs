//! Parsing of uBlock Origin / Adblock Plus filter-list syntax.
//!
//! We parse just enough to (a) separate convertible rules from unrepresentable
//! ones and (b) report precisely why the latter were skipped. Rules that cannot
//! be expressed faithfully as WebKit content rules are rejected with a reason,
//! mirroring the conservative strategy of Safari / Epiphany-style blockers.

use std::collections::BTreeMap;

/// Why a filter line was skipped during compilation.
pub type SkipReasons = BTreeMap<String, usize>;

/// A parsed network filter (blocking or exception).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkFilter {
    /// Raw pattern portion (without `@@`), e.g. `||ads.example.com^`.
    pub pattern: String,
    /// True for `@@` exception rules.
    pub exception: bool,
    pub important: bool,
    pub opts: FilterOptions,
}

/// The convertible subset of uBO/ABP network options.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct FilterOptions {
    /// `$third-party` / `$first-party`.
    pub load_type: Option<String>,
    /// WebKit resource-type names implied by `$script,image,stylesheet,...`.
    pub resource_types: Vec<String>,
    /// `$domain=a.com|b.com` positive entries.
    pub domains_include: Vec<String>,
    /// `$domain=~x.com` negative entries (also `~a` combined is rejected later).
    pub domains_exclude: Vec<String>,
    pub case_sensitive: bool,
}

/// A parsed cosmetic filter (`##selector`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CosmeticFilter {
    /// Hostnames the selector applies to. Empty => generic (all sites).
    pub domains: Vec<String>,
    pub selector: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FilterLine {
    Network(NetworkFilter),
    Cosmetic(CosmeticFilter),
    /// A `$badfilter` instruction to remove previously seen matching rules.
    BadFilter(String),
}

/// Parses a single, already-trimmed filter line.
/// Returns `None` for lines that must be skipped (recorded separately) — but
/// this function alone cannot tally reasons, so callers use
/// [`parse_line_ext`] when they need the reason.
pub fn parse_line(line: &str) -> Option<FilterLine> {
    parse_line_ext(line).map(|(f, _)| f)
}

/// Parses a single line, returning the rule (if any) and an optional skip reason.
pub fn parse_line_ext(line: &str) -> Option<(FilterLine, String)> {
    let line = line.trim();
    if line.is_empty() || line.starts_with('!') || line.starts_with('[') {
        return None;
    }

    // Cosmetic filters all contain "##" (or a variant like "#@#", "#?#", "#$#",
    // "#^#"). Exception/procedural variants are not representable.
    if let Some(ci) = line.find("##") {
        return parse_cosmetic(line, ci);
    }
    if line.contains("#@#") || line.contains("#?#") {
        return None;
    }
    if line.contains("#$#") || line.contains("#@$#") || line.contains("#^#") {
        return None;
    }

    // Network filter: [@@]pattern[$options]
    let mut rest = line;
    let exception = if let Some(r) = rest.strip_prefix("@@") {
        rest = r;
        true
    } else {
        false
    };

    let (pattern, opts_str) = match rest.find('$') {
        Some(i) => (&rest[..i], &rest[i + 1..]),
        None => (rest, ""),
    };
    if pattern.is_empty() {
        return None;
    }

    // $badfilter — an instruction, handled at compile time.
    if opts_str.split(',').any(|t| t == "badfilter") {
        return Some((FilterLine::BadFilter(pattern.to_string()), String::new()));
    }

    match parse_options(opts_str) {
        Ok(maybe_opts) => {
            let opts = maybe_opts.unwrap_or_default();
            Some((
                FilterLine::Network(NetworkFilter {
                    pattern: pattern.to_string(),
                    exception,
                    important: opts_str.split(',').any(|t| t == "important"),
                    opts,
                }),
                String::new(),
            ))
        }
        Err(reason) => {
            let _ = reason;
            None
        }
    }
}

/// Parses `$`-options into the convertible subset.
/// Returns `Ok(None)` when there are no options at all.
fn parse_options(s: &str) -> Result<Option<FilterOptions>, String> {
    if s.is_empty() {
        return Ok(None);
    }
    let mut o = FilterOptions::default();
    for tok in s.split(',') {
        if tok.is_empty() {
            continue;
        }
        // key=value options
        if let Some(eq) = tok.find('=') {
            let (key, value) = (&tok[..eq], &tok[eq + 1..]);
            match key {
                "domain" => {
                    for item in value.split('|') {
                        if item.is_empty() {
                            continue;
                        }
                        if let Some(d) = item.strip_prefix('~') {
                            o.domains_exclude.push(d.to_string());
                        } else {
                            o.domains_include.push(item.to_string());
                        }
                    }
                }
                // Never representable in WebKit content rules.
                _ => return Err(format!("unsupported option {key}")),
            }
            continue;
        }

        match tok {
            "third-party" | "3p" => set_load(&mut o.load_type, "third-party", tok)?,
            "first-party" | "1p" => set_load(&mut o.load_type, "first-party", tok)?,
            "script" => o.resource_types.push("script".into()),
            "image" => o.resource_types.push("image".into()),
            "stylesheet" | "css" => o.resource_types.push("style-sheet".into()),
            "font" => o.resource_types.push("font".into()),
            "media" => o.resource_types.push("media".into()),
            "document" | "doc" => o.resource_types.push("document".into()),
            "subdocument" | "frame" => o.resource_types.push("document".into()),
            "popup" => o.resource_types.push("popup".into()),
            "match-case" => o.case_sensitive = true,
            "all" | "important" => {} // no-op semantics for WebKit
            // Modes we deliberately do not approximate.
            "strict" => return Err("strict".into()),
            _ => return Err(format!("unsupported option {tok}")),
        }
    }
    o.resource_types.sort();
    o.resource_types.dedup();
    o.domains_include.sort();
    o.domains_include.dedup();
    o.domains_exclude.sort();
    o.domains_exclude.dedup();
    Ok(Some(o))
}

fn set_load(
    slot: &mut Option<String>,
    value: &str,
    _tok: &str,
) -> Result<(), String> {
    if let Some(existing) = slot {
        if existing != value {
            return Err("conflicting first/third-party".into());
        }
        return Ok(());
    }
    *slot = Some(value.to_string());
    Ok(())
}

/// Parses a cosmetic filter line where `ci` is the position of `##`.
fn parse_cosmetic(line: &str, ci: usize) -> Option<(FilterLine, String)> {
    let (left, _sep, selector) = (&line[..ci], &line[ci..ci + 2], &line[ci + 2..]);

    // Variants we cannot represent.
    if left.contains("#@#") {
        return None;
    }
    if left.starts_with("#@") || left.ends_with("#@") {
        return None;
    }
    if selector.starts_with('?') {
        return None; // #?# procedural
    }
    if selector.starts_with('$') {
        return None; // #$# CSS injection
    }
    if selector.starts_with('^') {
        return None; // #^# HTML filtering
    }
    if selector.starts_with('+') {
        return None; // ##+js(...) scriptlet
    }
    if selector.is_empty() {
        return None;
    }
    // Procedural / pseudo anywhere => not faithful.
    if selector.contains(':') {
        return None;
    }

    // Domain scope (may contain ~exclusions; those are not representable).
    let mut domains: Vec<String> = Vec::new();
    if !left.is_empty() {
        for d in left.split(',').map(|s| s.trim()) {
            if d.is_empty() {
                continue;
            }
            if d.starts_with('~') {
                return None;
            }
            domains.push(d.to_string());
        }
    }

    Some((
        FilterLine::Cosmetic(CosmeticFilter {
            domains,
            selector: selector.to_string(),
        }),
        String::new(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_basic_network() {
        let (f, _) = parse_line_ext("||ads.example.com^").unwrap();
        match f {
            FilterLine::Network(n) => {
                assert!(!n.exception);
                assert_eq!(n.pattern, "||ads.example.com^");
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn parses_exception() {
        let (f, _) = parse_line_ext("@@||safe.example.com").unwrap();
        match f {
            FilterLine::Network(n) => assert!(n.exception),
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn parses_options() {
        let (f, _) =
            parse_line_ext("||ads.example.com^$script,image,third-party").unwrap();
        if let FilterLine::Network(n) = f {
            assert_eq!(n.opts.resource_types, vec!["image", "script"]);
            assert_eq!(n.opts.load_type.as_deref(), Some("third-party"));
        } else {
            panic!("expected network");
        }
    }

    #[test]
    fn parses_domains() {
        let (f, _) = parse_line_ext("||ad.example^$domain=a.com|~b.com").unwrap();
        if let FilterLine::Network(n) = f {
            assert_eq!(n.opts.domains_include, vec!["a.com"]);
            assert_eq!(n.opts.domains_exclude, vec!["b.com"]);
        } else {
            panic!("expected network");
        }
    }

    #[test]
    fn skips_unrepresentable_options() {
        assert!(parse_line_ext("||x.com^$xmlhttprequest").is_none());
        assert!(parse_line_ext("||x.com^$removeparam").is_none());
        assert!(parse_line_ext("||x.com^$redirect").is_none());
        assert!(parse_line_ext("||x.com^$third-party,first-party").is_none());
    }

    #[test]
    fn parses_cosmetic() {
        let (f, _) = parse_line_ext("example.com##.ad-banner").unwrap();
        if let FilterLine::Cosmetic(c) = f {
            assert_eq!(c.domains, vec!["example.com"]);
            assert_eq!(c.selector, ".ad-banner");
        } else {
            panic!("expected cosmetic");
        }
        let (f, _) = parse_line_ext("##.advert").unwrap();
        if let FilterLine::Cosmetic(c) = f {
            assert!(c.domains.is_empty());
        } else {
            panic!("expected cosmetic");
        }
    }

    #[test]
    fn skips_procedural_cosmetic() {
        assert!(parse_line_ext("##x:has(.ad)").is_none());
        assert!(parse_line_ext("example.com##+js").is_none());
        assert!(parse_line_ext("example.com#?#.ad").is_none());
        assert!(parse_line_ext("example.com#@#.ad").is_none());
    }

    #[test]
    fn parses_badfilter() {
        let (f, _) = parse_line_ext("||ads.example.com^$badfilter").unwrap();
        match f {
            FilterLine::BadFilter(p) => assert_eq!(p, "||ads.example.com^"),
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn skips_junk() {
        assert!(parse_line("! comment").is_none());
        assert!(parse_line("").is_none());
    }
}
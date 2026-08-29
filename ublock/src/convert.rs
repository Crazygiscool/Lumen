//! Conversion from parsed filter rules to WebKit content-rule JSON.
//!
//! Only rules expressible faithfully in the WebKit content-blocker format
//! (`WKContentRuleList` / `WebKitUserContentFilterStore`) are emitted; others
//! are rejected with a reason string so compilation can report coverage.

use crate::filter::{CosmeticFilter, FilterOptions, NetworkFilter};
use serde_json::{json, Value};

/// Errors that describe *why* a rule cannot be represented.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Skip {
    /// The network pattern is a regex or otherwise unsupported.
    UnsupportedPattern(String),
    /// Options mix include+exclude domains, which WebKit cannot express.
    MixedDomains,
    /// Cosmetic selector is procedural / unrepresentable.
    UnsupportedSelector(String),
}

fn escape_pattern_char(out: &mut String, c: char) {
    if c.is_ascii_alphanumeric() || "_-%:".contains(c) {
        out.push(c);
    } else if c == '/' {
        out.push_str("\\/");
    } else {
        out.push('\\');
        out.push(c);
    }
}

/// Converts an ABP/uBO URL pattern into a fully self-anchored regex.
///
/// - `||host...` → anchored at `scheme://`, allowing subdomain labels.
/// - `|...`      → anchored at the start of the URL.
/// - anything else → contains-match (`.*pattern.*`).
///
/// `^` becomes the ABP "separator" character class; a trailing `^` additionally
/// matches end-of-URL.
pub fn pattern_to_regex(pattern: &str) -> Result<String, Skip> {
    if pattern.starts_with('/') && pattern.len() > 2 && pattern.ends_with('/') {
        return Err(Skip::UnsupportedPattern("regex pattern".into()));
    }

    let mut end_anchor = false;
    let mut s = pattern;
    if let Some(r) = s.strip_suffix('|') {
        end_anchor = true;
        s = r;
    }
    let mut trailing_sep = false;
    if let Some(r) = s.strip_suffix('^') {
        trailing_sep = true;
        s = r;
    }

    let mut out = String::with_capacity(pattern.len() + 32);

    if let Some(rest) = s.strip_prefix("||") {
        out.push_str("^[a-z][a-z0-9+.-]*://(?:[^/]*\\.)?");
        append_simple(&mut out, rest)?;
        finish(&mut out, trailing_sep, end_anchor);
    } else if let Some(rest) = s.strip_prefix('|') {
        out.push('^');
        append_simple(&mut out, rest)?;
        finish(&mut out, trailing_sep, end_anchor);
    } else {
        out.push_str(".*");
        append_simple(&mut out, s)?;
        finish(&mut out, trailing_sep, end_anchor);
    }

    if end_anchor {
        out.push('$');
    }
    Ok(out)
}

fn finish(out: &mut String, trailing_sep: bool, end_anchor: bool) {
    if trailing_sep {
        out.push_str("(?:$|[^a-zA-Z0-9._\\-])");
    } else if !end_anchor {
        out.push_str(".*");
    }
}

/// Appends literal pattern text, expanding `*` → `.*` and in-pattern `^` →
/// separator class. Rejected patterns contain stray anchors.
fn append_simple(out: &mut String, s: &str) -> Result<(), Skip> {
    for c in s.chars() {
        match c {
            '*' => out.push_str(".*"),
            '^' => out.push_str("[^a-zA-Z0-9._\\-]"),
            '|' => return Err(Skip::UnsupportedPattern("stray | anchor".into())),
            _ => escape_pattern_char(out, c),
        }
    }
    Ok(())
}

/// Builds the WebKit `trigger` JSON value from parsed options and its url-filter.
fn trigger_json(regex: &str, o: &FilterOptions) -> Value {
    let mut trigger = json!({ "url-filter": regex });
    if !o.resource_types.is_empty() {
        trigger["resource-type"] =
            Value::Array(o.resource_types.iter().map(|s| Value::String(s.clone())).collect());
    }
    if let Some(lt) = &o.load_type {
        trigger["load-type"] = json!([lt]);
    }
    if !o.domains_include.is_empty() {
        trigger["if-domain"] =
            Value::Array(o.domains_include.iter().map(|s| Value::String(s.clone())).collect());
    }
    if !o.domains_exclude.is_empty() {
        trigger["unless-domain"] =
            Value::Array(o.domains_exclude.iter().map(|s| Value::String(s.clone())).collect());
    }
    if o.case_sensitive {
        trigger["url-filter-is-case-sensitive"] = Value::Bool(true);
    }
    trigger
}

/// Trigger computed from the *page URL* for cosmetic filters (WebKit matches
/// css rules against the document URL).
fn cosmetic_trigger_url_filter(domain_opt: Option<&str>) -> String {
    match domain_opt {
        Some(d) => domain_page_regex(d),
        None => ".*".to_string(),
    }
}

/// A compiled rule ready to be emitted as WebKit JSON.
#[derive(Debug, Clone)]
pub struct Converted {
    /// Bucket: 0 = normal block, 1 = exception, 2 = important block.
    pub bucket: u8,
    /// Canonical dedup key.
    pub key: String,
    /// Estimated WebKit "abilities" consumed.
    pub abilities: usize,
    /// The rule JSON given to WebKit.
    pub json: Value,
}

/// Converts a parsed network filter to a WebKit rule, or returns a skip reason.
pub fn convert_network(n: &NetworkFilter) -> Result<Converted, Skip> {
    if !n.opts.domains_include.is_empty() && !n.opts.domains_exclude.is_empty() {
        return Err(Skip::MixedDomains);
    }

    let regex = pattern_to_regex(&n.pattern)?;
    // Reject patterns whose resulting regex suggests no hostname anchoring for
    // `||` prefixes (pattern_to_regex already handles this structurally).

    let (action_type, bucket) = if n.exception {
        ("ignore-previous-rules", 1u8)
    } else if n.important {
        ("block", 2u8)
    } else {
        ("block", 0u8)
    };

    let trigger = trigger_json(&regex, &n.opts);
    let key = format!(
        "{action_type}|{}|{}|{}|{}|{}|{}",
        trigger,
        n.opts.domains_include.join(","),
        n.opts.domains_exclude.join(","),
        n.opts.resource_types.join(","),
        n.opts.load_type.clone().unwrap_or_default(),
        n.opts.case_sensitive
    );

    let abilities = 1
        + n.opts.resource_types.len()
        + usize::from(n.opts.load_type.is_some())
        + n.opts.domains_include.len()
        + n.opts.domains_exclude.len();

    Ok(Converted {
        bucket,
        key,
        abilities,
        json: json!({
            "trigger": trigger,
            "action": { "type": action_type }
        }),
    })
}

/// Converts a cosmetic filter into one-or-more WebKit `css-display-none`
/// rules. Returns `None` if the selector is not representable.
pub fn convert_cosmetic(c: &CosmeticFilter) -> Result<Vec<Converted>, Skip> {
    if c.selector.is_empty() || c.selector.contains(':') {
        return Err(Skip::UnsupportedSelector(c.selector.clone()));
    }

    let domain_opt: Option<&str> = if c.domains.is_empty() {
        None
    } else if c.domains.len() == 1 {
        Some(c.domains[0].as_str())
    } else {
        // Multi-domain cosmetic rules become one rule per domain.
        let mut out = Vec::new();
        for d in &c.domains {
            let regex = cosmetic_trigger_url_filter(Some(d));
            out.push(Converted {
                bucket: 0,
                key: format!("css|{d}|{}", c.selector),
                abilities: 2,
                json: json!({
                    "trigger": { "url-filter": regex },
                    "action": {
                        "type": "css-display-none",
                        "selector": c.selector
                    }
                }),
            });
        }
        return Ok(out);
    };

    let regex = cosmetic_trigger_url_filter(domain_opt);
    Ok(vec![Converted {
        bucket: 0,
        key: format!("css|{}|{}", c.domains.join(","), c.selector),
        abilities: 2,
        json: json!({
            "trigger": { "url-filter": regex },
            "action": { "type": "css-display-none", "selector": c.selector }
        }),
    }])
}

/// Regex matching any page URL whose host is `domain` (or one of its subdomains).
pub fn domain_page_regex(domain: &str) -> String {
    let esc = escape_domain(domain);
    format!("^https?://(?:[^/]*\\.)?{esc}(?:[:/?#]|$)")
}

fn escape_domain(d: &str) -> String {
    let mut out = String::with_capacity(d.len());
    for c in d.chars() {
        if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
            out.push(c);
        } else if c == '.' {
            out.push_str("\\.");
        } else {
            escape_pattern_char(&mut out, c);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn matches(re: &str, url: &str) -> bool {
        regex::Regex::new(re).map(|r| r.is_match(url)).unwrap_or(false)
    }

    #[test]
    fn host_anchor_regex() {
        let r = pattern_to_regex("||ads.example.com^").unwrap();
        assert!(r.starts_with("^[a-z][a-z0-9+.-]*://(?:[^/]*\\.)?ads\\.example\\.com"));
        assert!(r.ends_with("(?:$|[^a-zA-Z0-9._\\-])"));
    }

    #[test]
    fn host_anchor_matches_subdomains_and_ports() {
        let r = pattern_to_regex("||ads.example.com^").unwrap();
        assert!(matches(&r, "https://tracker.ads.example.com/page?x=1"));
        assert!(matches(&r, "https://ads.example.com:8443/x"));
        assert!(matches(&r, "http://ads.example.com"));
        assert!(!matches(&r, "https://notads.example.com.evil.net/"));
    }

    #[test]
    fn start_and_plain_anchors() {
        let r = pattern_to_regex("|https://www.example.com/foo").unwrap();
        assert!(matches(&r, "https://www.example.com/foo/bar"));
        let plain = pattern_to_regex("example.com/banner").unwrap();
        assert!(matches(&plain, "https://cdn.example.com/banner/img.png"));
    }

    #[test]
    fn wildcards_and_end_anchor() {
        let r = pattern_to_regex("*/ads/*").unwrap();
        assert!(matches(&r, "https://host/a/ads/b"));
        let e = pattern_to_regex("||example.com|").unwrap();
        assert!(e.ends_with('$'));
    }

    #[test]
    fn rejects_regex_patterns() {
        assert!(matches!(
            pattern_to_regex("/^https?:\\/\\/ads/"),
            Err(Skip::UnsupportedPattern(_))
        ));
    }

    #[test]
    fn cosmetic_domain_regex() {
        let r = domain_page_regex("example.com");
        assert!(matches(&r, "https://example.com/index.html"));
        assert!(matches(&r, "https://blog.example.com/"));
        assert!(!matches(&r, "https://notexample.org/"));
    }
}
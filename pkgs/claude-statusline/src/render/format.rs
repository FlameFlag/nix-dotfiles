//! Pure formatting helpers (token humanization, model-name shortening).

/// Humanize a token count: `1_234_567` -> `"1.2M"`, `34_500` -> `"34k"`,
/// small values -> bare integer. Mirrors the jq `humanize` def in the bash
/// script.
pub fn humanize_tokens(n: u64) -> String {
    if n == 0 {
        return String::new();
    }
    if n >= 1_000_000 {
        // ((n + 50_000) / 100_000) gives tenths of millions, rounded.
        let tenths = (n + 50_000) / 100_000;
        format!("{}.{}M", tenths / 10, tenths % 10)
    } else if n >= 1_000 {
        format!("{}k", n / 1_000)
    } else {
        n.to_string()
    }
}

/// Compact human-friendly duration.
///
/// `45` -> `"45s"`, `750` -> `"12m"`, `5000` -> `"1h 23m"`,
/// `300_000` -> `"3d 11h"`. Returns the empty string for zero or
/// negative input so callers can drop the segment cleanly.
pub fn humanize_duration(secs: i64) -> String {
    if secs <= 0 {
        return String::new();
    }
    let secs = secs as u64;
    if secs < 60 {
        format!("{secs}s")
    } else if secs < 3600 {
        format!("{}m", secs / 60)
    } else if secs < 86400 {
        let h = secs / 3600;
        let m = (secs % 3600) / 60;
        if m == 0 {
            format!("{h}h")
        } else {
            format!("{h}h {m}m")
        }
    } else {
        let d = secs / 86400;
        let h = (secs % 86400) / 3600;
        if h == 0 {
            format!("{d}d")
        } else {
            format!("{d}d {h}h")
        }
    }
}

/// Shorten the model display name to its family: `"Opus 4.6 (1M context)"`
/// -> `"Opus"`, `"Sonnet 4.5"` -> `"Sonnet"`, `"Haiku 4.5"` -> `"Haiku"`.
///
/// Claude Code only ever ships four model variants - Opus, Sonnet
/// (regular + 1M), and Haiku - and every display name starts with the
/// family name. So instead of scanning bytes, stripping versions, and
/// allocating a new `String`, we look at the first non-space character
/// and dispatch on it. Returns the input unchanged if we don't recognize
/// the leading letter, so a future model name still renders.
pub fn shorten_model(name: &str) -> &str {
    let trimmed = name.trim_start();
    match trimmed.as_bytes().first() {
        Some(b'O') => "Opus",
        Some(b'S') => "Sonnet",
        Some(b'H') => "Haiku",
        // Unknown family: hand the trimmed name back so we don't blank
        // out the segment for a model we haven't taught the dispatch
        // about yet. Trailing whitespace is harmless inside a segment.
        _ => trimmed.trim_end(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn humanize() {
        assert_eq!(humanize_tokens(0), "");
        assert_eq!(humanize_tokens(123), "123");
        assert_eq!(humanize_tokens(34_500), "34k");
        assert_eq!(humanize_tokens(1_234_567), "1.2M");
        assert_eq!(humanize_tokens(1_500_000), "1.5M");
    }

    #[test]
    fn humanize_duration_buckets() {
        assert_eq!(humanize_duration(0), "");
        assert_eq!(humanize_duration(-5), "");
        assert_eq!(humanize_duration(45), "45s");
        assert_eq!(humanize_duration(750), "12m");
        assert_eq!(humanize_duration(5000), "1h 23m");
        assert_eq!(humanize_duration(7200), "2h");
        assert_eq!(humanize_duration(90_000), "1d 1h");
        assert_eq!(humanize_duration(86_400), "1d");
    }

    #[test]
    fn model_shortening() {
        assert_eq!(shorten_model("Opus 4.6 (1M context)"), "Opus");
        assert_eq!(shorten_model("Sonnet 4.6"), "Sonnet");
        assert_eq!(shorten_model("Sonnet 4.6 (1M context)"), "Sonnet");
        assert_eq!(shorten_model("Haiku 4.5"), "Haiku");
        assert_eq!(shorten_model("Haiku"), "Haiku");
        // Unknown family: hand the (trimmed) name back unchanged.
        assert_eq!(shorten_model("Mystery 9.0"), "Mystery 9.0");
    }
}

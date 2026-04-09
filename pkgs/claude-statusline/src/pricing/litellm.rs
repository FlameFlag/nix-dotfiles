//! `LiteLLM` data source: fetch, cache, and parse the
//! `model_prices_and_context_window.json` snapshot that backs
//! [`crate::pricing`].
//!
//! Strategy:
//! - Cache the JSON on disk at `$XDG_CACHE_HOME/claude-statusline/litellm.json`
//!   (falling back to `$HOME/.cache/...`).
//! - Refresh via [`ureq`] (rustls, no system OpenSSL) once the cache is older
//!   than [`CACHE_TTL`]. We'd rather show no cost than block the prompt for long,
//!   so the timeout is intentionally tight.
//! - If the network fetch fails and we have an existing (stale) cache, we still
//!   use it; if there's no cache at all, [`load_table`] returns `None` and the
//!   cost segment is silently dropped upstream.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use serde::Deserialize;

use crate::pricing::Pricing;

const LITELLM_URL: &str =
    "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json";

/// Refresh the cached pricing JSON when it's older than this. A week
/// strikes a reasonable balance: pricing changes are infrequent enough
/// that fetching every render would be wasteful, but rare enough that
/// week-old data is essentially always current.
const CACHE_TTL: Duration = Duration::from_secs(7 * 24 * 60 * 60);

/// HTTP timeout for the `LiteLLM` fetch. Generous for a ~1.5 MB GET to
/// GitHub raw, but tight enough that a stalled connection won't ruin a
/// prompt render.
const FETCH_TIMEOUT: Duration = Duration::from_secs(3);

/// Hard cap on response body size - defends against a runaway upstream
/// without needing Content-Length to be set. Current upstream is ~1.5 MB.
const MAX_BODY_BYTES: u64 = 16 * 1024 * 1024;

/// Load the `LiteLLM` Claude pricing table, refreshing the disk cache if
/// stale. Returns `None` only if neither the network nor the cache is
/// available.
pub fn load_table() -> Option<HashMap<String, Pricing>> {
    let path = cache_path()?;
    let needs_refresh = match std::fs::metadata(&path) {
        Ok(meta) => meta
            .modified()
            .ok()
            .and_then(|t| SystemTime::now().duration_since(t).ok())
            .is_none_or(|age| age > CACHE_TTL),
        Err(_) => true,
    };

    if needs_refresh {
        // Best-effort refresh: failure is fine if we already have a cache.
        let _ = refresh_cache(&path);
    }

    let mut bytes = std::fs::read(&path).ok()?;
    parse_table(&mut bytes).ok()
}

fn cache_path() -> Option<PathBuf> {
    // `dirs::cache_dir` already honors `XDG_CACHE_HOME` on Linux/BSD,
    // returns `~/Library/Caches` on macOS, and `%LOCALAPPDATA%` on
    // Windows - no platform branching needed in our code.
    Some(
        dirs::cache_dir()?
            .join("claude-statusline")
            .join("litellm.json"),
    )
}

fn refresh_cache(path: &Path) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let config = ureq::Agent::config_builder()
        .timeout_global(Some(FETCH_TIMEOUT))
        .user_agent(concat!("claude-statusline/", env!("CARGO_PKG_VERSION")))
        .build();
    let agent: ureq::Agent = config.into();
    let mut resp = agent
        .get(LITELLM_URL)
        .call()
        .map_err(|e| std::io::Error::other(format!("ureq: {e}")))?;
    let bytes = resp
        .body_mut()
        .with_config()
        .limit(MAX_BODY_BYTES)
        .read_to_vec()
        .map_err(|e| std::io::Error::other(format!("ureq body: {e}")))?;
    let parent = path
        .parent()
        .ok_or_else(|| std::io::Error::other("litellm cache path has no parent directory"))?;
    let tmp = tempfile::NamedTempFile::new_in(parent)?;
    std::fs::write(tmp.path(), &bytes)?;
    tmp.persist(path)
        .map_err(|e| std::io::Error::other(format!("persist: {e}")))?;
    Ok(())
}

#[derive(Debug, Deserialize)]
struct LiteLLMEntry {
    #[serde(default)]
    input_cost_per_token: Option<f64>,
    #[serde(default)]
    output_cost_per_token: Option<f64>,
    #[serde(default)]
    cache_creation_input_token_cost: Option<f64>,
    #[serde(default)]
    cache_read_input_token_cost: Option<f64>,
    #[serde(default)]
    input_cost_per_token_above_200k_tokens: Option<f64>,
    #[serde(default)]
    output_cost_per_token_above_200k_tokens: Option<f64>,
    #[serde(default)]
    cache_creation_input_token_cost_above_200k_tokens: Option<f64>,
    #[serde(default)]
    cache_read_input_token_cost_above_200k_tokens: Option<f64>,
}

impl LiteLLMEntry {
    /// Convert to the internal [`Pricing`] shape, returning `None` when
    /// the row has neither input nor output costs (`LiteLLM`'s `sample_spec`
    /// stub looks like that).
    fn into_pricing(self) -> Option<Pricing> {
        let (input, output) = self.input_cost_per_token.zip(self.output_cost_per_token)?;
        Some(Pricing {
            input,
            output,
            cache_creation: self.cache_creation_input_token_cost.unwrap_or(0.0),
            cache_read: self.cache_read_input_token_cost.unwrap_or(0.0),
            input_above_200k: self.input_cost_per_token_above_200k_tokens,
            output_above_200k: self.output_cost_per_token_above_200k_tokens,
            cache_creation_above_200k: self.cache_creation_input_token_cost_above_200k_tokens,
            cache_read_above_200k: self.cache_read_input_token_cost_above_200k_tokens,
        })
    }
}

/// Parse a `LiteLLM` JSON blob into a `HashMap` keyed by model name.
///
/// Drops non-Claude entries and any row missing both
/// `input_cost_per_token` and `output_cost_per_token` (which is what
/// `LiteLLM`'s `sample_spec` row looks like).
///
/// Uses [`simd_json`] rather than [`serde_json`]: `LiteLLM`'s blob is
/// ~1.5 MB and parsed once per cold start, which is well above the 4–16 KB
/// crossover where SIMD JSON's structural-index pass starts paying back.
/// Serde-derive compatibility means we reuse [`LiteLLMEntry`] unchanged.
/// Takes `&mut [u8]` because simd-json mutates the input in place while
/// unescaping strings; callers must own the buffer.
pub fn parse_table(bytes: &mut [u8]) -> simd_json::Result<HashMap<String, Pricing>> {
    let raw: HashMap<String, LiteLLMEntry> = simd_json::serde::from_slice(bytes)?;
    Ok(raw
        .into_iter()
        .filter(|(k, _)| is_claude_key(k))
        .filter_map(|(k, entry)| entry.into_pricing().map(|p| (k, p)))
        .collect())
}

fn is_claude_key(k: &str) -> bool {
    k.starts_with("claude-") || k.starts_with("anthropic/claude-") || k.starts_with("anthropic.")
}

/// Tiny snapshot of `LiteLLM` JSON used by hermetic tests. Mirrors the
/// upstream schema (only the keys we care about) so the parser stays
/// honest. Update if upstream renames fields. Lives at module scope (not
/// inside `mod tests`) so `crate::pricing`'s tests can borrow it without
/// tripping rustc's "private tests module" rule.
#[cfg(test)]
pub(crate) const FIXTURE: &str = r#"{
        "sample_spec": { "litellm_provider": "irrelevant" },
        "claude-opus-4-6": {
            "input_cost_per_token": 5e-6,
            "output_cost_per_token": 25e-6,
            "cache_creation_input_token_cost": 6.25e-6,
            "cache_read_input_token_cost": 5e-7
        },
        "claude-sonnet-4-5": {
            "input_cost_per_token": 3e-6,
            "output_cost_per_token": 15e-6,
            "cache_creation_input_token_cost": 3.75e-6,
            "cache_read_input_token_cost": 3e-7,
            "input_cost_per_token_above_200k_tokens": 6e-6,
            "output_cost_per_token_above_200k_tokens": 22.5e-6,
            "cache_creation_input_token_cost_above_200k_tokens": 7.5e-6,
            "cache_read_input_token_cost_above_200k_tokens": 6e-7
        },
        "claude-haiku-4-5": {
            "input_cost_per_token": 1e-6,
            "output_cost_per_token": 5e-6
        },
        "gpt-5": {
            "input_cost_per_token": 1.25e-6,
            "output_cost_per_token": 1e-5
        }
    }"#;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_drops_non_claude_entries() {
        let mut bytes = FIXTURE.as_bytes().to_vec();
        let t = parse_table(&mut bytes).unwrap();
        assert!(!t.contains_key("gpt-5"));
        assert!(!t.contains_key("sample_spec"));
        assert!(t.contains_key("claude-opus-4-6"));
        assert!(t.contains_key("claude-sonnet-4-5"));
    }

    #[test]
    fn parse_preserves_tiered_rates() {
        let mut bytes = FIXTURE.as_bytes().to_vec();
        let t = parse_table(&mut bytes).unwrap();
        let p = t.get("claude-sonnet-4-5").unwrap();
        assert_eq!(p.input_above_200k, Some(6e-6));
    }
}

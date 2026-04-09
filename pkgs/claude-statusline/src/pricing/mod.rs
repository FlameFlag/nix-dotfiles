//! Claude pricing types and cost math. The actual rate table comes from
//! [`crate::pricing::litellm`], which fetches and caches `LiteLLM`'s
//! `model_prices_and_context_window.json`.
//!
//! This module owns:
//! - the [`Pricing`] / [`Tokens`] data structures,
//! - model-name [`lookup`] (exact -> `anthropic/` prefix -> substring fallback),
//! - the tiered [`cost_of`] formula for 1M-context models, where tokens above
//!   200k are charged at the `*_above_200k` rates.

pub mod cost;
pub mod litellm;

use std::collections::HashMap;
use std::sync::OnceLock;

const TIER_THRESHOLD: u64 = 200_000;

#[derive(Debug, Clone, Copy, Default)]
pub struct Pricing {
    pub input: f64,
    pub output: f64,
    pub cache_creation: f64,
    pub cache_read: f64,
    pub input_above_200k: Option<f64>,
    pub output_above_200k: Option<f64>,
    pub cache_creation_above_200k: Option<f64>,
    pub cache_read_above_200k: Option<f64>,
}

/// Token counts for a single model, summed over a session.
#[derive(Debug, Default, Clone, Copy)]
pub struct Tokens {
    pub input: u64,
    pub output: u64,
    pub cache_creation: u64,
    pub cache_read: u64,
}

/// Look up pricing for a model name. Returns `None` if no `LiteLLM` data
/// is available or the model isn't recognized.
pub fn lookup(model: &str) -> Option<Pricing> {
    let table = ensure_loaded()?;
    lookup_in(table, model).copied()
}

/// Pure lookup against an explicit table - exposed (rather than the
/// `OnceLock`-cached `lookup`) so benches can measure resolution against
/// a controlled fixture.
pub fn lookup_in<'a, S: std::hash::BuildHasher>(
    table: &'a HashMap<String, Pricing, S>,
    model: &str,
) -> Option<&'a Pricing> {
    if let Some(p) = table.get(model) {
        return Some(p);
    }
    let with_prefix = format!("anthropic/{model}");
    if let Some(p) = table.get(&with_prefix) {
        return Some(p);
    }
    let lower = model.to_ascii_lowercase();
    for (k, v) in table {
        let lk = k.to_ascii_lowercase();
        if lk.contains(&lower) || lower.contains(&lk) {
            return Some(v);
        }
    }
    None
}

/// Compute USD cost for a token bundle, applying tiered pricing when
/// above-200k rates exist. Each token-type's tier check is independent.
pub fn cost_of(tokens: &Tokens, p: &Pricing) -> f64 {
    tier(tokens.input, p.input, p.input_above_200k)
        + tier(tokens.output, p.output, p.output_above_200k)
        + tier(
            tokens.cache_creation,
            p.cache_creation,
            p.cache_creation_above_200k,
        )
        + tier(tokens.cache_read, p.cache_read, p.cache_read_above_200k)
}

fn tier(total: u64, base: f64, above: Option<f64>) -> f64 {
    if total == 0 {
        return 0.0;
    }
    match above {
        Some(rate) if total > TIER_THRESHOLD => {
            let below = TIER_THRESHOLD as f64 * base;
            let over = (total - TIER_THRESHOLD) as f64 * rate;
            below + over
        }
        _ => total as f64 * base,
    }
}

static TABLE: OnceLock<Option<HashMap<String, Pricing>>> = OnceLock::new();

fn ensure_loaded() -> Option<&'static HashMap<String, Pricing>> {
    TABLE.get_or_init(litellm::load_table).as_ref()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pricing::litellm;

    fn fixture_table() -> HashMap<String, Pricing> {
        let mut bytes = litellm::FIXTURE.as_bytes().to_vec();
        litellm::parse_table(&mut bytes).unwrap()
    }

    #[test]
    fn opus_lookup_exact() {
        let t = fixture_table();
        let p = lookup_in(&t, "claude-opus-4-6").unwrap();
        assert!((p.input - 5e-6).abs() < 1e-12);
        assert!((p.output - 25e-6).abs() < 1e-12);
    }

    #[test]
    fn substring_fallback_matches_dated_variant() {
        // Querying with a longer dated key: substring fallback should still
        // resolve it to the bare alias in the fixture.
        let t = fixture_table();
        assert!(lookup_in(&t, "claude-opus-4-6-20260205").is_some());
    }

    #[test]
    fn unknown_returns_none() {
        let t = fixture_table();
        assert!(lookup_in(&t, "definitely-not-real-xyz").is_none());
    }

    #[test]
    fn flat_cost_basic() {
        let t = fixture_table();
        let p = lookup_in(&t, "claude-opus-4-6").unwrap();
        let tokens = Tokens {
            input: 1000,
            output: 500,
            ..Default::default()
        };
        let c = cost_of(&tokens, p);
        // 1000 * 5e-6 + 500 * 25e-6 = 0.0175
        assert!((c - 0.0175).abs() < 1e-9);
    }

    #[test]
    fn tiered_cost_above_200k() {
        let t = fixture_table();
        let p = lookup_in(&t, "claude-sonnet-4-5").unwrap();
        let tokens = Tokens {
            input: 300_000,
            ..Default::default()
        };
        let c = cost_of(&tokens, p);
        // 200k * 3e-6 + 100k * 6e-6 = 0.6 + 0.6 = 1.2
        assert!((c - 1.2).abs() < 1e-9);
    }
}

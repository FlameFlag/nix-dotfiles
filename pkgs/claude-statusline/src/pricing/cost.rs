//! Session cost calculation.
//!
//! When Claude Code's stdin payload includes `cost.total_cost_usd`, we
//! trust it. Otherwise we walk the `transcript_path` JSONL line-by-line,
//! group token usage by model, and apply [`crate::pricing`] rates.

use std::borrow::Cow;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

use bstr::ByteSlice;
use indexmap::IndexMap;
use serde::Deserialize;

use crate::pricing::{self, Tokens};

/// Public entry point. Returns the session's API-equivalent cost in USD,
/// or `None` if no cost data is available.
pub fn session_cost(transcript_path: Option<&str>, cc_cost: Option<f64>) -> Option<f64> {
    if let Some(c) = cc_cost {
        return Some(c);
    }
    let path = transcript_path?;
    calculate_from_transcript(Path::new(path)).ok()
}

// Borrowed deserialize: serde will hand back a `&str` view into the line
// buffer when the JSON has no escapes, falling back to an owned `String`
// only when it must (e.g. a model name with `\"`). Model names are pure
// ASCII in practice, so the borrow path wins every time and we never
// allocate per-line just to read a field we'll throw away.
#[derive(Debug, Deserialize)]
struct Line<'a> {
    #[serde(borrow)]
    message: Option<Message<'a>>,
}

#[derive(Debug, Deserialize)]
struct Message<'a> {
    #[serde(borrow, default)]
    model: Option<Cow<'a, str>>,
    #[serde(default)]
    usage: Option<Usage>,
}

#[derive(Debug, Deserialize, Default)]
struct Usage {
    #[serde(default)]
    input_tokens: u64,
    #[serde(default)]
    output_tokens: u64,
    #[serde(default)]
    cache_creation_input_tokens: u64,
    #[serde(default)]
    cache_read_input_tokens: u64,
}

/// Walk a JSONL transcript and return the API-equivalent cost. Public
/// so benches can drive it against a synthetic file without going
/// through the `cc_cost` short-circuit in `session_cost`.
///
/// Hot-path notes (kept here because they explain non-obvious choices):
///
/// - **Buffer reuse.** A single `Vec<u8>` is reused for every line via
///   `read_until`. The previous `BufRead::split` form allocated a fresh `Vec<u8>`
///   per line; on long sessions that's the largest source of churn next to JSON
///   parsing.
/// - **Byte prefilter.** Roughly half of real Claude transcript lines (file
///   snapshots, user messages, slash-command frames) carry no `usage` block at
///   all. `bstr::find` is vectorized via `memchr`, so skipping a line is dozens
///   of times cheaper than the cheapest `serde_json::from_slice` call.
/// - **Borrowed parse.** `Line` / `Message` borrow into the line buffer, so
///   `model` arrives as a `Cow<&str>` view rather than an owned allocation per
///   line.
/// - **No-alloc accumulate.** `IndexMap::get_mut` lets us update the common case
///   (model already present) without owning the key. The first occurrence of each
///   model is the only allocation.
pub fn calculate_from_transcript(path: &Path) -> std::io::Result<f64> {
    let file = File::open(path)?;
    let mut reader = BufReader::with_capacity(64 * 1024, file);

    let mut models: IndexMap<String, Tokens> = IndexMap::new();
    let mut buf: Vec<u8> = Vec::with_capacity(8 * 1024);

    loop {
        buf.clear();
        if reader.read_until(b'\n', &mut buf)? == 0 {
            break;
        }
        let trimmed = buf.trim();
        if trimmed.is_empty() {
            continue;
        }
        // Cheap byte prefilter - order matters: `usage` is rarer than
        // `model` on the lines we want, so testing it first short-circuits
        // unwanted lines faster on average.
        if trimmed.find(b"\"usage\"").is_none() || trimmed.find(b"\"model\"").is_none() {
            continue;
        }

        let Ok(parsed) = serde_json::from_slice::<Line<'_>>(trimmed) else {
            continue;
        };
        let Some(msg) = parsed.message else { continue };
        let Some(usage) = msg.usage else { continue };
        let Some(model) = msg.model else { continue };
        let model: &str = model.as_ref();
        if model == "<synthetic>" {
            continue;
        }

        models
            .entry(model.to_owned())
            .and_modify(|entry| {
                entry.input += usage.input_tokens;
                entry.output += usage.output_tokens;
                entry.cache_creation += usage.cache_creation_input_tokens;
                entry.cache_read += usage.cache_read_input_tokens;
            })
            .or_insert(Tokens {
                input: usage.input_tokens,
                output: usage.output_tokens,
                cache_creation: usage.cache_creation_input_tokens,
                cache_read: usage.cache_read_input_tokens,
            });
    }

    let total = models
        .iter()
        .filter_map(|(model, tokens)| pricing::lookup(model).map(|p| pricing::cost_of(tokens, &p)))
        .sum();
    Ok(total)
}

/// Format a USD amount for the statusline, converted into the user's
/// resolved local currency (see [`crate::currency`]).
///
/// The fall back is USD with a `$` prefix when the geo-IP / FX lookup
/// fails or hasn't run yet - same shape as the historical output.
///
/// Numbers above 1000 collapse to a `1.2k`-style suffix to keep the
/// segment narrow on a long-running session; the threshold is applied
/// in the *converted* currency so a JPY user (where every figure is
/// four-plus digits) gets the suffix at the right point.
pub fn format_usd(amount: f64) -> String {
    let currency = crate::currency::current();
    let local = amount * currency.usd_rate;
    let sym = &currency.symbol;
    if local >= 1000.0 {
        format!("{sym}{:.1}k", local / 1000.0)
    } else {
        format!("{sym}{local:.2}")
    }
}

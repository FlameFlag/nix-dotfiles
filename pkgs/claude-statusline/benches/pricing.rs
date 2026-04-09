//! Benchmarks for pricing, transcript walking, and LiteLLM parsing.

use std::collections::HashMap;
use std::fs;
use std::io::Write as _;
use std::path::PathBuf;

use claude_statusline::pricing::cost::calculate_from_transcript;
use claude_statusline::pricing::litellm::parse_table;
use claude_statusline::pricing::{Pricing, Tokens, cost_of, lookup_in};

fn main() {
    divan::main();
}

/// Synthetic Claude Code transcript JSONL.
///
/// `density` is the fraction of lines that carry a `usage` block. Real
/// transcripts run around 0.4; the dense variant (1.0) measures pure
/// parse-and-accumulate throughput.
fn write_transcript(lines: usize, density: f32, tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("claude-statusline-bench-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let path = dir.join(format!("transcript-{tag}-{lines}.jsonl"));
    let mut f = fs::File::create(&path).unwrap();
    let take = (1.0 / density.max(0.001)).round() as usize;
    for i in 0..lines {
        if i % take == 0 {
            let model = if i % 2 == 0 {
                "claude-opus-4-6"
            } else {
                "claude-sonnet-4-5"
            };
            writeln!(
                f,
                r#"{{"message":{{"model":"{model}","usage":{{"input_tokens":{i_in},"output_tokens":{i_out},"cache_creation_input_tokens":{cc},"cache_read_input_tokens":{cr}}}}}}}"#,
                i_in = 100 + i,
                i_out = 50 + i,
                cc = 10,
                cr = 20,
            )
            .unwrap();
        } else {
            writeln!(
                f,
                r#"{{"type":"user","message":{{"role":"user","content":"<some user input #{i}>"}}}}"#,
            )
            .unwrap();
        }
    }
    f.flush().unwrap();
    path
}

#[divan::bench(args = [10, 100, 1_000, 10_000])]
fn transcript_walk_dense(bencher: divan::Bencher<'_, '_>, lines: usize) {
    let path = write_transcript(lines, 1.0, "dense");
    bencher.bench(|| calculate_from_transcript(divan::black_box(&path)).unwrap());
}

#[divan::bench(args = [10, 100, 1_000, 10_000])]
fn transcript_walk_realistic(bencher: divan::Bencher<'_, '_>, lines: usize) {
    let path = write_transcript(lines, 0.4, "realistic");
    bencher.bench(|| calculate_from_transcript(divan::black_box(&path)).unwrap());
}

const LITELLM_FIXTURE: &str = r#"{
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
    "anthropic/claude-3-5-sonnet": {
        "input_cost_per_token": 3e-6,
        "output_cost_per_token": 15e-6
    },
    "gpt-5": {
        "input_cost_per_token": 1.25e-6,
        "output_cost_per_token": 1e-5
    }
}"#;

#[divan::bench]
fn litellm_parse(bencher: divan::Bencher<'_, '_>) {
    bencher
        .with_inputs(|| LITELLM_FIXTURE.as_bytes().to_vec())
        .bench_local_values(|mut bytes| parse_table(&mut bytes).unwrap().len());
}

/// Real-world cold-start path: load the cached LiteLLM JSON from disk
/// and parse it. Skipped silently if the user has no cache (CI etc.).
#[divan::bench]
fn litellm_parse_real_cache(bencher: divan::Bencher<'_, '_>) {
    let Some(path) = real_cache_path() else {
        return;
    };
    let Ok(bytes) = fs::read(&path) else { return };
    bencher
        .with_inputs(|| bytes.clone())
        .bench_local_values(|mut b| parse_table(&mut b).unwrap().len());
}

fn real_cache_path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))?;
    Some(base.join("claude-statusline").join("litellm.json"))
}

fn fixture_table() -> HashMap<String, Pricing> {
    let mut bytes = LITELLM_FIXTURE.as_bytes().to_vec();
    parse_table(&mut bytes).unwrap()
}

#[divan::bench]
fn lookup_exact(bencher: divan::Bencher<'_, '_>) {
    let table = fixture_table();
    bencher.bench(|| {
        lookup_in(
            divan::black_box(&table),
            divan::black_box("claude-opus-4-6"),
        )
    });
}

#[divan::bench]
fn lookup_substring_fallback(bencher: divan::Bencher<'_, '_>) {
    let table = fixture_table();
    bencher.bench(|| {
        lookup_in(
            divan::black_box(&table),
            divan::black_box("claude-opus-4-6-20260205"),
        )
    });
}

#[divan::bench]
fn lookup_miss(bencher: divan::Bencher<'_, '_>) {
    let table = fixture_table();
    bencher.bench(|| {
        lookup_in(
            divan::black_box(&table),
            divan::black_box("definitely-not-real-xyz"),
        )
    });
}

#[divan::bench]
fn cost_of_flat() -> f64 {
    let p = Pricing {
        input: 5e-6,
        output: 25e-6,
        cache_creation: 6.25e-6,
        cache_read: 5e-7,
        ..Pricing::default()
    };
    let t = Tokens {
        input: 50_000,
        output: 12_000,
        cache_creation: 5_000,
        cache_read: 200_000,
    };
    cost_of(divan::black_box(&t), divan::black_box(&p))
}

#[divan::bench]
fn cost_of_tiered() -> f64 {
    let p = Pricing {
        input: 3e-6,
        output: 15e-6,
        cache_creation: 3.75e-6,
        cache_read: 3e-7,
        input_above_200k: Some(6e-6),
        output_above_200k: Some(22.5e-6),
        cache_creation_above_200k: Some(7.5e-6),
        cache_read_above_200k: Some(6e-7),
    };
    let t = Tokens {
        input: 350_000,
        output: 250_000,
        cache_creation: 0,
        cache_read: 220_000,
    };
    cost_of(divan::black_box(&t), divan::black_box(&p))
}

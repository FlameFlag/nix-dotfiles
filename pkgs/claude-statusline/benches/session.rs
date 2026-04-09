//! Benchmarks for session flash state and input parsing.

use claude_statusline::input::Input;
use claude_statusline::session;

fn main() {
    divan::main();
}

/// Covers the file-IO hot path behind the flash-delta feature: load an
/// existing snapshot, compute deltas vs the current values, write the
/// updated snapshot back.
#[divan::bench]
fn session_update(bencher: divan::Bencher<'_, '_>) {
    let key = format!("divan-bench-{}", std::process::id());
    // Seed: first call establishes a baseline; subsequent calls measure
    // the steady-state "load -> diff -> save" round-trip.
    let _ = session::update(
        Some(&key),
        Some(0.1),
        Some(5),
        Some(1),
        Some(10_000),
        session::DEFAULT_FLASH_TTL_SECS,
    );
    bencher.bench(|| {
        session::update(
            divan::black_box(Some(key.as_str())),
            divan::black_box(Some(0.25)),
            divan::black_box(Some(12)),
            divan::black_box(Some(3)),
            divan::black_box(Some(25_000)),
            divan::black_box(session::DEFAULT_FLASH_TTL_SECS),
        )
    });
}

#[divan::bench]
fn session_key_extract(bencher: divan::Bencher<'_, '_>) {
    bencher.bench(|| {
        session::session_key(divan::black_box(Some(
            "/Users/foo/.claude/projects/bar/abc-123.jsonl",
        )))
    });
}

const STDIN_PAYLOAD: &str = r#"{
    "workspace": {"current_dir": "/Users/flame/Developer/nix-dotfiles/pkgs/claude-statusline"},
    "model": {"display_name": "Opus 4.6 (1M context)"},
    "context_window": {
        "used_percentage": 2.5,
        "context_window_size": 1000000,
        "current_usage": {"input_tokens": 25000, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}
    },
    "rate_limits": {
        "five_hour": {"used_percentage": 7.0, "resets_at": 9999999999}
    },
    "cost": {
        "total_cost_usd": 0.22,
        "total_api_duration_ms": 47000,
        "total_lines_added": 12,
        "total_lines_removed": 3
    }
}"#;

#[divan::bench]
fn input_parse(bencher: divan::Bencher<'_, '_>) {
    bencher.bench(|| {
        let input: Input =
            serde_json::from_slice(divan::black_box(STDIN_PAYLOAD.as_bytes())).unwrap();
        input
    });
}

const STDIN_MINIMAL: &str = r#"{"workspace": {"current_dir": "/tmp/foo"}}"#;

#[divan::bench]
fn input_parse_minimal(bencher: divan::Bencher<'_, '_>) {
    bencher.bench(|| {
        let input: Input =
            serde_json::from_slice(divan::black_box(STDIN_MINIMAL.as_bytes())).unwrap();
        input
    });
}

//! Library entry point for `claude-statusline`.
//!
//! The crate is primarily a binary (`src/main.rs`), but exposing the
//! modules through a `lib.rs` lets external benches in `benches/` reach
//! into the rendering, parsing, and pricing internals without having to
//! shell out to the binary. The public API is intentionally not stable —
//! anything here is `pub` for the benches and tests, not for downstream
//! consumers.

pub mod cli;
pub mod config;
pub mod currency;
pub mod font_detect;
pub mod input;
pub mod pricing;
pub mod render;
pub mod session;
pub mod settings;
pub mod theme;
pub mod vcs;

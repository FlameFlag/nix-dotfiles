//! Benchmarks for formatting helpers, layout parsing, font detection,
//! palette construction, and segment operations.

use claude_statusline::font_detect::contains_nerd_font;
use claude_statusline::render::colors::Palette;
use claude_statusline::render::format::{humanize_duration, humanize_tokens, shorten_model};
use claude_statusline::render::layout::Layout;
use claude_statusline::render::segment::Segment;
use claude_statusline::theme::ThemeMode;

fn main() {
    divan::main();
}

#[divan::bench(args = [
    "dir",
    "dir, vcs, model",
    "dir, vcs, model | cost, diff, context, rate_limits",
    "dir, vcs, model, cost | diff, context | rate_limits, dir, vcs, model",
])]
fn layout_parse(spec: &str) -> Layout {
    Layout::parse(divan::black_box(spec)).unwrap()
}

#[divan::bench]
fn layout_two_line() -> Layout {
    Layout::two_line()
}

#[divan::bench]
fn layout_contains_hit(bencher: divan::Bencher<'_, '_>) {
    let layout = Layout::two_line();
    bencher.bench(|| {
        layout.contains(divan::black_box(
            claude_statusline::render::layout::SegmentName::Vcs,
        ))
    });
}

#[divan::bench]
fn layout_display(bencher: divan::Bencher<'_, '_>) {
    let layout = Layout::two_line();
    bencher.bench(|| format!("{}", divan::black_box(&layout)));
}

#[divan::bench(args = [0_u64, 999, 34_500, 1_234_567, 999_999_999])]
fn fmt_humanize_tokens(n: u64) -> String {
    humanize_tokens(divan::black_box(n))
}

#[divan::bench(args = [0_i64, 45, 750, 5_000, 90_000, 31_536_000])]
fn fmt_humanize_duration(secs: i64) -> String {
    humanize_duration(divan::black_box(secs))
}

#[divan::bench(args = [
    "Haiku",
    "Sonnet 4.5",
    "Opus 4.6 (1M context)",
    "Claude Opus 4.6 with extra (parens) and 4.5 versions",
])]
fn fmt_shorten_model(name: &str) -> &str {
    shorten_model(divan::black_box(name))
}

#[divan::bench(args = [
    "font-family = TX02 Nerd Font",
    "font_family JetBrainsMono Nerd Font Mono",
    "font_family Hack NF",
    "font-family = Menlo",
    "font_family = SF Mono",
    "# infinite scrollback",
])]
fn font_contains_nerd(text: &str) -> bool {
    contains_nerd_font(divan::black_box(text))
}

#[divan::bench(args = [0_u32, 49, 50, 74, 75, 100])]
fn palette_color_for_pct(pct: u32) -> anstyle::Style {
    let pal = Palette::dark();
    pal.color_for_pct(divan::black_box(pct), 50, 75)
}

#[divan::bench(args = [0_u64, 100_000, 200_000, 300_000, 500_000])]
fn palette_color_for_token_count(tokens: u64) -> anstyle::Style {
    let pal = Palette::dark();
    pal.color_for_token_count(divan::black_box(tokens))
}

#[divan::bench]
fn palette_for_theme_dark() -> Palette {
    Palette::for_theme(divan::black_box(ThemeMode::Dark))
}

#[divan::bench]
fn palette_for_theme_light() -> Palette {
    Palette::for_theme(divan::black_box(ThemeMode::Light))
}

#[divan::bench]
fn segment_push_plain(bencher: divan::Bencher<'_, '_>) {
    bencher
        .with_inputs(|| Segment::new(true))
        .bench_local_values(|mut s| {
            s.push_plain("branch-name");
            s
        });
}

#[divan::bench]
fn segment_push_styled(bencher: divan::Bencher<'_, '_>) {
    let style = anstyle::AnsiColor::Green.on_default();
    bencher
        .with_inputs(|| Segment::new(true))
        .bench_local_values(|mut s| {
            s.push_styled("+342", style);
            s
        });
}

#[divan::bench(args = [1_usize, 3, 6, 10])]
fn segment_width(bencher: divan::Bencher<'_, '_>, cells: usize) {
    let mut s = Segment::new(true);
    for i in 0..cells {
        s.push_plain(format!("cell{i}"));
    }
    bencher.bench(|| s.width());
}

#[divan::bench]
fn segment_write_to(bencher: divan::Bencher<'_, '_>) {
    let pal = Palette::dark();
    let mut s = Segment::new(true);
    s.push_styled("+342", pal.green);
    s.push_plain(" ");
    s.push_styled("-89", pal.red);
    bencher.bench(|| {
        let mut out = String::new();
        s.write_to(&mut out);
        out
    });
}

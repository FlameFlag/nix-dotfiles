const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("ruff", &.{
    m.bin("ruff", &.{ "ruff", "--version" }),
}, m.archive(m.githubLatest("astral-sh/ruff", "", "ruff-{platform}.tar.gz"), &.{
    m.archivePlatform(m.macosAarch64(), "aarch64-apple-darwin", .tar_gz, 1, &.{
        m.link("ruff", "ruff"),
    }, &.{}),
    m.archivePlatform(m.linuxAarch64(), "aarch64-unknown-linux-musl", .tar_gz, 1, &.{
        m.link("ruff", "ruff"),
    }, &.{}),
    m.archivePlatform(m.linuxX8664(), "x86_64-unknown-linux-musl", .tar_gz, 1, &.{
        m.link("ruff", "ruff"),
    }, &.{}),
    .{
        .when = m.windowsX8664(),
        .platform = "x86_64-pc-windows-msvc",
        .source = m.githubLatest("astral-sh/ruff", "", "ruff-{platform}.zip"),
        .kind = .zip,
        .strip_components = 1,
        .links = &.{m.link("ruff", "ruff.exe")},
    },
}));

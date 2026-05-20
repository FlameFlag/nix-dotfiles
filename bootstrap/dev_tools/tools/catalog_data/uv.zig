const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("uv", &.{
    m.bin("uv", &.{ "uv", "--version" }),
    m.bin("uvx", &.{ "uvx", "--version" }),
}, m.archive(m.githubLatest("astral-sh/uv", "v", "uv-{platform}.tar.gz"), &.{
    m.archivePlatform(m.macosAarch64(), "aarch64-apple-darwin", .tar_gz, 1, &.{
        m.link("uv", "uv"),
        m.link("uvx", "uvx"),
    }, &.{}),
    m.archivePlatform(m.linuxAarch64(), "aarch64-unknown-linux-musl", .tar_gz, 1, &.{
        m.link("uv", "uv"),
        m.link("uvx", "uvx"),
    }, &.{}),
    m.archivePlatform(m.linuxX8664(), "x86_64-unknown-linux-musl", .tar_gz, 1, &.{
        m.link("uv", "uv"),
        m.link("uvx", "uvx"),
    }, &.{}),
    .{
        .when = m.windowsX8664(),
        .platform = "x86_64-pc-windows-msvc",
        .source = m.githubLatest("astral-sh/uv", "v", "uv-{platform}.zip"),
        .kind = .zip,
        .strip_components = 1,
        .links = &.{
            m.link("uv", "uv.exe"),
            m.link("uvx", "uvx.exe"),
        },
    },
}));

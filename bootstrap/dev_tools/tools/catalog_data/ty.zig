const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("ty", &.{
    m.bin("ty", &.{ "ty", "--version" }),
}, m.archive(m.githubLatest("astral-sh/ty", "", "ty-{platform}.tar.gz"), &.{
    m.archivePlatform(m.macosAarch64(), "aarch64-apple-darwin", .tar_gz, 1, &.{
        m.link("ty", "ty"),
    }, &.{}),
    m.archivePlatform(m.linuxAarch64(), "aarch64-unknown-linux-musl", .tar_gz, 1, &.{
        m.link("ty", "ty"),
    }, &.{}),
    m.archivePlatform(m.linuxX8664(), "x86_64-unknown-linux-musl", .tar_gz, 1, &.{
        m.link("ty", "ty"),
    }, &.{}),
    .{
        .when = m.windowsX8664(),
        .platform = "x86_64-pc-windows-msvc",
        .source = m.githubLatest("astral-sh/ty", "", "ty-{platform}.zip"),
        .kind = .zip,
        .strip_components = 1,
        .links = &.{m.link("ty", "ty.exe")},
    },
}));

const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("zls", &.{
    m.bin("zls", &.{ "zls", "--version" }),
}, m.archive(m.githubLatest("zigtools/zls", "", "zls-{platform}.tar.xz"), &.{
    m.archivePlatform(m.macosAarch64(), "aarch64-macos", .tar_xz, 0, &.{m.link("zls", "zls")}, &.{}),
    m.archivePlatform(m.linuxAarch64(), "aarch64-linux", .tar_xz, 0, &.{m.link("zls", "zls")}, &.{}),
    m.archivePlatform(m.linuxX8664(), "x86_64-linux", .tar_xz, 0, &.{m.link("zls", "zls")}, &.{}),
    .{
        .when = m.windowsX8664(),
        .platform = "x86_64-windows",
        .source = m.githubLatest("zigtools/zls", "", "zls-{platform}.zip"),
        .kind = .zip,
        .strip_components = 0,
        .links = &.{m.link("zls", "zls.exe")},
    },
}));

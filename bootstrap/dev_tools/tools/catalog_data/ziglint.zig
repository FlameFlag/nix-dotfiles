const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("ziglint", &.{
    m.bin("ziglint", &.{ "ziglint", "--version" }),
}, m.archive(m.githubLatest("rockorager/ziglint", "v", "ziglint-{platform}.tar.gz"), &.{
    m.archivePlatform(m.macosAarch64(), "aarch64-macos", .tar_gz, 0, &.{m.link("ziglint", "ziglint")}, &.{}),
    m.archivePlatform(m.linuxAarch64(), "aarch64-linux", .tar_gz, 0, &.{m.link("ziglint", "ziglint")}, &.{}),
    m.archivePlatform(m.linuxX8664(), "x86_64-linux", .tar_gz, 0, &.{m.link("ziglint", "ziglint")}, &.{}),
    .{
        .when = m.windowsX8664(),
        .platform = "x86_64-windows",
        .source = m.githubLatest("rockorager/ziglint", "v", "ziglint-{platform}.zip"),
        .kind = .zip,
        .strip_components = 0,
        .links = &.{m.link("ziglint", "ziglint.exe")},
    },
}));

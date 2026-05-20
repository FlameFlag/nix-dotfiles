const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("chezmoi", &.{
    m.bin("chezmoi", &.{ "chezmoi", "--version" }),
}, m.archive(m.githubLatest("twpayne/chezmoi", "v", "chezmoi_{version}_{platform}.tar.gz"), &.{
    m.archivePlatform(m.macosAarch64(), "darwin_arm64", .tar_gz, 0, &.{
        m.link("chezmoi", "chezmoi"),
    }, &.{}),
    m.archivePlatform(m.linuxAarch64(), "linux_arm64", .tar_gz, 0, &.{
        m.link("chezmoi", "chezmoi"),
    }, &.{}),
    m.archivePlatform(m.linuxX8664(), "linux-musl_amd64", .tar_gz, 0, &.{
        m.link("chezmoi", "chezmoi"),
    }, &.{}),
    .{
        .when = m.windowsX8664(),
        .platform = "windows_amd64",
        .source = m.githubLatest("twpayne/chezmoi", "v", "chezmoi_{version}_{platform}.zip"),
        .kind = .zip,
        .strip_components = 0,
        .links = &.{m.link("chezmoi", "chezmoi.exe")},
    },
}));

const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = .{
    .name = "git",
    .platforms = &.{ .macos, .linux, .windows },
    .bins = &.{
        m.bin("git", &.{ "git", "--version" }),
    },
    .action = m.archive(
        m.githubLatestMatching(
            "desktop/dugite-native",
            "v",
            "dugite-native-v",
            "-{platform}.tar.gz",
        ),
        &.{
            m.archivePlatform(m.macosAarch64(), "macOS-arm64", .tar_gz, 0, &.{
                m.link("git", "bin/git"),
            }, &.{}),
            m.archivePlatform(m.linuxAarch64(), "ubuntu-arm64", .tar_gz, 0, &.{
                m.link("git", "bin/git"),
            }, &.{}),
            m.archivePlatform(m.linuxX8664(), "ubuntu-x64", .tar_gz, 0, &.{
                m.link("git", "bin/git"),
            }, &.{}),
            m.archivePlatform(m.windowsX8664(), "windows-x64", .tar_gz, 0, &.{
                m.link("git.cmd", "cmd/git.exe"),
            }, &.{}),
        },
    ),
};

const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = .{
    .name = "vscode",
    .requires = &.{.not_nixos},
    .bins = &.{
        m.bin("code", &.{ "code", "--version" }),
    },
    .action = m.archive(m.direct("latest", "https://update.code.visualstudio.com/latest/{platform}/stable"), &.{
        m.archivePlatform(m.macosAarch64(), "darwin-arm64", .zip, 0, &.{
            m.link("code", "Visual Studio Code.app/Contents/Resources/app/bin/code"),
        }, &.{
            m.link("Visual Studio Code.app", "Visual Studio Code.app"),
        }),
        m.archivePlatform(m.linuxAarch64(), "linux-arm64", .tar_gz, 1, &.{
            m.link("code", "bin/code"),
        }, &.{}),
        m.archivePlatform(m.linuxX8664(), "linux-x64", .tar_gz, 1, &.{
            m.link("code", "bin/code"),
        }, &.{}),
    }),
};

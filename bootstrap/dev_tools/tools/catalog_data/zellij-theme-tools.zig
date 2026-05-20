const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = .{
    .name = "zellij-theme-tools",
    .platforms = &.{ .macos, .linux },
    .bins = &.{
        m.bin("codex-zellij-theme", &.{
            "sh",
            "-c",
            "command -v codex-zellij-theme >/dev/null && printf installed",
        }),
        m.bin("zellij-auto-theme", &.{
            "sh",
            "-c",
            "command -v zellij-auto-theme >/dev/null && printf installed",
        }),
    },
    .action = m.zigBuild("pkgs/zellij-theme-tools"),
};

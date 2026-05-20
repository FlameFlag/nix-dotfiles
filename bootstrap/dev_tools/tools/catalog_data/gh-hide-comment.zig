const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = .{
    .name = "gh-hide-comment",
    .platforms = &.{ .macos, .linux, .windows },
    .bins = &.{
        m.bin("gh-hide-comment", &.{
            "sh",
            "-c",
            "command -v gh-hide-comment >/dev/null && printf installed",
        }),
    },
    .action = m.zigBuild("pkgs/gh-hide-comment"),
};

const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = .{
    .name = "lenovo-con-mode",
    .platforms = &.{ .linux, .windows },
    .requires = &.{.lenovo_laptop},
    .bins = &.{
        m.bin("lenovo-con-mode", &.{
            "sh",
            "-c",
            "command -v lenovo-con-mode >/dev/null && printf installed",
        }),
    },
    .action = m.zigBuild("pkgs/lenovo-con-mode"),
};

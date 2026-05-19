const std = @import("std");
const common = @import("common");

const command = @import("command.zig");
const theme = @import("theme.zig");

pub fn isAvailable(rt: anytype) !bool {
    const zellij = rt.env.get("ZELLIJ") orelse return false;
    if (zellij.len == 0) return false;
    return common.process.hasBin(rt, "zellij");
}

pub fn setPaneColor(rt: anytype, colors: theme.Colors) void {
    command.runSilently(rt, &.{
        "zellij",
        "action",
        "set-pane-color",
        "--fg",
        colors.fg,
        "--bg",
        colors.bg,
    });
}

pub fn resetPaneColor(rt: anytype) void {
    command.runSilently(rt, &.{ "zellij", "action", "set-pane-color", "--reset" });
}

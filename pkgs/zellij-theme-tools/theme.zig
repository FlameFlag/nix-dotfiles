const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");

pub const Colors = struct {
    fg: []const u8,
    bg: []const u8,
};

pub const Theme = struct {
    name: []const u8,
    colors: Colors,
};

pub const frappe: Theme = .{
    .name = "catppuccin-frappe",
    .colors = .{
        .fg = "#c6d0f5",
        .bg = "#303446",
    },
};

pub const latte: Theme = .{
    .name = "catppuccin-latte",
    .colors = .{
        .fg = "#4c4f69",
        .bg = "#eff1f5",
    },
};

pub fn detect(rt: anytype) !Theme {
    return if (try prefersLight(rt)) latte else frappe;
}

fn prefersLight(rt: anytype) !bool {
    return switch (builtin.os.tag) {
        .macos => macosPrefersLight(rt),
        .linux => linuxPrefersLight(rt),
        else => false,
    };
}

fn macosPrefersLight(rt: anytype) !bool {
    const defaults = try common.process.pathOf(rt, "defaults") orelse return false;
    defer rt.allocator.free(defaults);

    var result = common.process.capture(rt, &.{ defaults, "read", "-g", "AppleInterfaceStyle" }) catch {
        return false;
    };
    defer result.deinit(rt.allocator);

    return !result.succeeded();
}

fn linuxPrefersLight(rt: anytype) !bool {
    const gsettings = try common.process.pathOf(rt, "gsettings") orelse return false;
    defer rt.allocator.free(gsettings);

    var result = common.process.capture(rt, &.{
        gsettings,
        "get",
        "org.gnome.desktop.interface",
        "color-scheme",
    }) catch {
        return false;
    };
    defer result.deinit(rt.allocator);
    if (!result.succeeded()) return false;

    return std.mem.indexOf(u8, result.stdout, "dark") == null;
}

test "themes expose the previous script colors" {
    try std.testing.expectEqualStrings("catppuccin-frappe", frappe.name);
    try std.testing.expectEqualStrings("#c6d0f5", frappe.colors.fg);
    try std.testing.expectEqualStrings("#303446", frappe.colors.bg);
    try std.testing.expectEqualStrings("catppuccin-latte", latte.name);
    try std.testing.expectEqualStrings("#4c4f69", latte.colors.fg);
    try std.testing.expectEqualStrings("#eff1f5", latte.colors.bg);
}

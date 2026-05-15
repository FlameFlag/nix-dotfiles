const std = @import("std");

const constants = @import("constants.zig");

pub const Action = enum {
    status,
    on,
    off,
    toggle,
};

const actions = std.StaticStringMapWithEql(Action, std.static_string_map.eqlAsciiIgnoreCase).initComptime(.{
    .{ "status", .status },
    .{ "on", .on },
    .{ "enable", .on },
    .{ "off", .off },
    .{ "disable", .off },
    .{ "toggle", .toggle },
});

pub fn parse(stderr: *std.Io.Writer, args: []const [:0]const u8) !?Action {
    if (args.len == 0) return .toggle;
    if (args.len > 1) return fail(?Action, "expected at most one action", stderr, .{});

    const arg = args[0];
    if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) return null;
    if (actions.get(arg)) |action| return action;

    return fail(?Action, "unknown action: {s}", stderr, .{arg});
}

pub fn printUsage(stdout: *std.Io.Writer) !void {
    try stdout.print(
        \\Toggle or set Lenovo Ideapad conservation mode.
        \\
        \\Usage:
        \\  lenovo-con-mode [status|on|off|toggle]
        \\
        \\Without an action, defaults to `toggle`.
        \\
        \\Linux writes to:
        \\  {s}
        \\
        \\Windows uses Lenovo's installed ACPI Virtual Power Controller driver:
        \\  {s}
    , .{ constants.conservation_mode_path, constants.windows_energy_drv_path });
    try stdout.writeByte('\n');
    try stdout.flush();
}

pub fn stateLabel(enabled: bool) []const u8 {
    return if (enabled) "ENABLED (60% charge)" else "DISABLED (100% charge)";
}

pub fn fail(comptime T: type, comptime fmt: []const u8, stderr: *std.Io.Writer, args: anytype) !T {
    try stderr.print("error: " ++ fmt ++ "\n", args);
    try stderr.flush();
    return error.Failure;
}

test "parse actions" {
    var buffer: [256]u8 = undefined;
    var stderr: std.Io.Writer = .fixed(&buffer);

    try std.testing.expectEqual(Action.toggle, (try parse(&stderr, &.{})).?);
    try std.testing.expectEqual(Action.status, (try parse(&stderr, &.{"status"})).?);
    try std.testing.expectEqual(Action.on, (try parse(&stderr, &.{"on"})).?);
    try std.testing.expectEqual(Action.on, (try parse(&stderr, &.{"enable"})).?);
    try std.testing.expectEqual(Action.off, (try parse(&stderr, &.{"off"})).?);
    try std.testing.expectEqual(Action.off, (try parse(&stderr, &.{"disable"})).?);
    try std.testing.expectEqual(Action.toggle, (try parse(&stderr, &.{"toggle"})).?);
    try std.testing.expectEqual(Action.status, (try parse(&stderr, &.{"STATUS"})).?);
    try std.testing.expectEqual(null, try parse(&stderr, &.{"--help"}));
}

test "reject invalid actions" {
    var buffer: [256]u8 = undefined;
    var stderr: std.Io.Writer = .fixed(&buffer);

    try std.testing.expectError(error.Failure, parse(&stderr, &.{"wat"}));
    try std.testing.expectError(error.Failure, parse(&stderr, &.{ "on", "off" }));
}

test "state labels" {
    try std.testing.expectEqualStrings("ENABLED (60% charge)", stateLabel(true));
    try std.testing.expectEqualStrings("DISABLED (100% charge)", stateLabel(false));
}

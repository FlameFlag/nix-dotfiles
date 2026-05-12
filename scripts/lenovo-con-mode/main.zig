const std = @import("std");
const builtin = @import("builtin");

const conservation_mode_path = "/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode";
const dmi_vendor_path = "/sys/class/dmi/id/sys_vendor";
const dmi_board_vendor_path = "/sys/class/dmi/id/board_vendor";
const dmi_product_name_path = "/sys/class/dmi/id/product_name";

const Action = enum {
    status,
    on,
    off,
    toggle,
};

pub fn main(init: std.process.Init) !u8 {
    return run(init) catch |err| {
        if (err == error.Failure) return 1;

        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
        const stderr = &stderr_writer.interface;
        try stderr.print("error: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return 1;
    };
}

fn run(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const action = try parseAction(stderr, args[1..]);
    if (action == null) {
        try printUsage(stdout);
        return 0;
    }

    if (!try isSupportedLenovoLinux(init.io, init.gpa)) {
        try stderr.print("info: Lenovo conservation mode is only supported on Linux Lenovo laptops; skipping.\n", .{});
        try stderr.flush();
        return 0;
    }

    const current = try readMode(init.io, stderr);
    const desired = switch (action.?) {
        .status => null,
        .on => true,
        .off => false,
        .toggle => !current,
    };

    if (desired) |value| {
        if (value != current) {
            try writeMode(init.io, stderr, value);
        }
        try stdout.print("Conservation Mode: {s}\n", .{stateLabel(value)});
    } else {
        try stdout.print("Conservation Mode: {s}\n", .{stateLabel(current)});
    }
    try stdout.flush();

    return 0;
}

fn parseAction(stderr: *std.Io.Writer, args: []const [:0]const u8) !?Action {
    if (args.len == 0) return .toggle;
    if (args.len > 1) return fail(?Action, stderr, "expected at most one action", .{});

    const arg = args[0];
    if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) return null;
    if (std.ascii.eqlIgnoreCase(arg, "status")) return .status;
    if (std.ascii.eqlIgnoreCase(arg, "on") or std.ascii.eqlIgnoreCase(arg, "enable")) return .on;
    if (std.ascii.eqlIgnoreCase(arg, "off") or std.ascii.eqlIgnoreCase(arg, "disable")) return .off;
    if (std.ascii.eqlIgnoreCase(arg, "toggle")) return .toggle;

    return fail(?Action, stderr, "unknown action: {s}", .{arg});
}

fn printUsage(stdout: *std.Io.Writer) !void {
    try stdout.print(
        \\Toggle or set Lenovo Ideapad conservation mode.
        \\
        \\Usage:
        \\  lenovo-con-mode [status|on|off|toggle]
        \\
        \\Without an action, defaults to `toggle`.
        \\Writes to:
        \\  {s}
    , .{conservation_mode_path});
    try stdout.writeByte('\n');
    try stdout.flush();
}

fn isSupportedLenovoLinux(io: std.Io, allocator: std.mem.Allocator) !bool {
    if (builtin.os.tag != .linux) return false;
    if (!try isLenovoMachine(io, allocator)) return false;
    return sysfsNodeExists(io, conservation_mode_path) catch |err| switch (err) {
        error.AccessDenied => true,
        else => return err,
    };
}

fn isLenovoMachine(io: std.Io, allocator: std.mem.Allocator) !bool {
    if (try readTrimmedAbsolute(io, allocator, dmi_vendor_path)) |vendor| {
        defer allocator.free(vendor);
        if (isLenovoVendor(vendor)) return true;
    }
    if (try readTrimmedAbsolute(io, allocator, dmi_board_vendor_path)) |vendor| {
        defer allocator.free(vendor);
        if (isLenovoVendor(vendor)) return true;
    }
    if (try readTrimmedAbsolute(io, allocator, dmi_product_name_path)) |product| {
        defer allocator.free(product);
        if (std.ascii.findIgnoreCase(product, "lenovo") != null or std.ascii.findIgnoreCase(product, "legion") != null) return true;
    }
    return false;
}

fn readTrimmedAbsolute(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return null,
        else => return err,
    };
    defer file.close(io);

    var buffer: [256]u8 = undefined;
    const len = try file.readPositionalAll(io, &buffer, 0);
    const trimmed = std.mem.trim(u8, buffer[0..len], " \t\r\n");
    return try allocator.dupe(u8, trimmed);
}

fn sysfsNodeExists(io: std.Io, path: []const u8) !bool {
    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer file.close(io);
    return true;
}

fn isLenovoVendor(value: []const u8) bool {
    return std.ascii.findIgnoreCase(value, "lenovo") != null;
}

fn readMode(io: std.Io, stderr: *std.Io.Writer) !bool {
    var file = std.Io.Dir.openFileAbsolute(io, conservation_mode_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return fail(bool, stderr, "conservation mode sysfs node not found: {s}", .{conservation_mode_path}),
        else => return err,
    };
    defer file.close(io);

    var buffer: [16]u8 = undefined;
    const len = try file.readPositionalAll(io, &buffer, 0);
    const value = std.mem.trim(u8, buffer[0..len], " \t\r\n");
    return parseMode(stderr, value);
}

fn parseMode(stderr: *std.Io.Writer, value: []const u8) !bool {
    if (std.mem.eql(u8, value, "0")) return false;
    if (std.mem.eql(u8, value, "1")) return true;
    return fail(bool, stderr, "unexpected conservation mode value: {s}", .{value});
}

fn writeMode(io: std.Io, stderr: *std.Io.Writer, enabled: bool) !void {
    var file = std.Io.Dir.openFileAbsolute(io, conservation_mode_path, .{ .mode = .write_only }) catch |err| switch (err) {
        error.FileNotFound => return fail(void, stderr, "conservation mode sysfs node not found: {s}", .{conservation_mode_path}),
        error.AccessDenied => return fail(void, stderr, "permission denied writing conservation mode; run as root", .{}),
        else => return err,
    };
    defer file.close(io);

    try file.writeStreamingAll(io, if (enabled) "1\n" else "0\n");
}

fn stateLabel(enabled: bool) []const u8 {
    return if (enabled) "ENABLED (60% charge)" else "DISABLED (100% charge)";
}

fn fail(comptime T: type, stderr: *std.Io.Writer, comptime fmt: []const u8, args: anytype) !T {
    try stderr.print("error: " ++ fmt ++ "\n", args);
    try stderr.flush();
    return error.Failure;
}

test "parse actions" {
    var buffer: [256]u8 = undefined;
    var stderr: std.Io.Writer = .fixed(&buffer);

    try std.testing.expectEqual(Action.toggle, (try parseAction(&stderr, &.{})).?);
    try std.testing.expectEqual(Action.status, (try parseAction(&stderr, &.{"status"})).?);
    try std.testing.expectEqual(Action.on, (try parseAction(&stderr, &.{"on"})).?);
    try std.testing.expectEqual(Action.on, (try parseAction(&stderr, &.{"enable"})).?);
    try std.testing.expectEqual(Action.off, (try parseAction(&stderr, &.{"off"})).?);
    try std.testing.expectEqual(Action.off, (try parseAction(&stderr, &.{"disable"})).?);
    try std.testing.expectEqual(Action.toggle, (try parseAction(&stderr, &.{"toggle"})).?);
    try std.testing.expectEqual(Action.status, (try parseAction(&stderr, &.{"STATUS"})).?);
    try std.testing.expectEqual(null, try parseAction(&stderr, &.{"--help"}));
}

test "reject invalid actions" {
    var buffer: [256]u8 = undefined;
    var stderr: std.Io.Writer = .fixed(&buffer);

    try std.testing.expectError(error.Failure, parseAction(&stderr, &.{"wat"}));
    try std.testing.expectError(error.Failure, parseAction(&stderr, &.{ "on", "off" }));
}

test "parse sysfs mode values" {
    var buffer: [256]u8 = undefined;
    var stderr: std.Io.Writer = .fixed(&buffer);

    try std.testing.expectEqual(false, try parseMode(&stderr, "0"));
    try std.testing.expectEqual(true, try parseMode(&stderr, "1"));
    try std.testing.expectError(error.Failure, parseMode(&stderr, "2"));
}

test "detect Lenovo vendor strings" {
    try std.testing.expect(isLenovoVendor("LENOVO"));
    try std.testing.expect(isLenovoVendor("Lenovo Group Limited"));
    try std.testing.expect(!isLenovoVendor("Dell Inc."));
    try std.testing.expect(!isLenovoVendor(""));
}

test "state labels" {
    try std.testing.expectEqualStrings("ENABLED (60% charge)", stateLabel(true));
    try std.testing.expectEqualStrings("DISABLED (100% charge)", stateLabel(false));
}

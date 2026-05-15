const std = @import("std");
const common = @import("common");

const cli = @import("cli.zig");
const constants = @import("constants.zig");

pub fn isSupported(allocator: std.mem.Allocator, io: std.Io) !bool {
    if (!try isLenovoMachine(allocator, io)) return false;
    return sysfsNodeExists(io, constants.conservation_mode_path) catch |err| switch (err) {
        error.AccessDenied => true,
        else => return err,
    };
}

fn isLenovoMachine(allocator: std.mem.Allocator, io: std.Io) !bool {
    if (try common.fs.readTrimmedAlloc(allocator, io, constants.dmi_vendor_path)) |vendor| {
        defer allocator.free(vendor);
        if (isLenovoVendor(vendor)) return true;
    }
    if (try common.fs.readTrimmedAlloc(allocator, io, constants.dmi_board_vendor_path)) |vendor| {
        defer allocator.free(vendor);
        if (isLenovoVendor(vendor)) return true;
    }
    if (try common.fs.readTrimmedAlloc(allocator, io, constants.dmi_product_name_path)) |product| {
        defer allocator.free(product);
        if (std.ascii.findIgnoreCase(product, "lenovo") != null or
            std.ascii.findIgnoreCase(product, "legion") != null)
        {
            return true;
        }
    }
    return false;
}

fn sysfsNodeExists(io: std.Io, path: []const u8) !bool {
    std.Io.Dir.accessAbsolute(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

fn isLenovoVendor(value: []const u8) bool {
    return std.ascii.findIgnoreCase(value, "lenovo") != null;
}

pub fn readMode(io: std.Io, stderr: *std.Io.Writer) !bool {
    var buffer: [16]u8 = undefined;
    const contents = std.Io.Dir.cwd().readFile(io, constants.conservation_mode_path, &buffer) catch |err| switch (err) {
        error.FileNotFound => return cli.fail(
            bool,
            "conservation mode sysfs node not found: {s}",
            stderr,
            .{constants.conservation_mode_path},
        ),
        error.AccessDenied => return cli.fail(
            bool,
            "permission denied reading conservation mode; run as root",
            stderr,
            .{},
        ),
        else => return cli.fail(
            bool,
            "failed to read conservation mode sysfs node {s}: {s}",
            stderr,
            .{ constants.conservation_mode_path, @errorName(err) },
        ),
    };

    const value = common.fs.trimAsciiWhitespace(contents);
    return parseMode(stderr, value);
}

fn parseMode(stderr: *std.Io.Writer, value: []const u8) !bool {
    if (value.len == 1) {
        if (std.fmt.parseInt(u1, value, 10)) |parsed| return parsed != 0 else |_| {}
    }
    return cli.fail(bool, "unexpected conservation mode value: {s}", stderr, .{value});
}

pub fn writeMode(io: std.Io, stderr: *std.Io.Writer, enabled: bool) !void {
    var file = std.Io.Dir.openFileAbsolute(
        io,
        constants.conservation_mode_path,
        .{ .mode = .write_only },
    ) catch |err| switch (err) {
        error.FileNotFound => return cli.fail(
            void,
            "conservation mode sysfs node not found: {s}",
            stderr,
            .{constants.conservation_mode_path},
        ),
        error.AccessDenied => return cli.fail(
            void,
            "permission denied writing conservation mode; run as root",
            stderr,
            .{},
        ),
        else => return cli.fail(
            void,
            "failed to open conservation mode sysfs node {s}: {s}",
            stderr,
            .{ constants.conservation_mode_path, @errorName(err) },
        ),
    };
    defer file.close(io);

    file.writeStreamingAll(io, if (enabled) "1\n" else "0\n") catch |err| switch (err) {
        error.AccessDenied => return cli.fail(
            void,
            "permission denied writing conservation mode; run as root",
            stderr,
            .{},
        ),
        else => return cli.fail(
            void,
            "failed to write conservation mode sysfs node {s}: {s}",
            stderr,
            .{ constants.conservation_mode_path, @errorName(err) },
        ),
    };
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

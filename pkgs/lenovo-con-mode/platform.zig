const std = @import("std");
const builtin = @import("builtin");

const cli = @import("cli.zig");
const linux = @import("linux.zig");
const windows = @import("windows.zig");

pub fn isSupportedLenovo(allocator: std.mem.Allocator, io: std.Io) !bool {
    return switch (builtin.os.tag) {
        .linux => linux.isSupported(allocator, io),
        .windows => windows.isSupported(),
        else => false,
    };
}

pub fn readMode(io: std.Io, stderr: *std.Io.Writer) !bool {
    return switch (builtin.os.tag) {
        .linux => linux.readMode(io, stderr),
        .windows => windows.readMode(stderr),
        else => cliUnsupported(bool, stderr),
    };
}

pub fn writeMode(io: std.Io, stderr: *std.Io.Writer, enabled: bool) !void {
    return switch (builtin.os.tag) {
        .linux => linux.writeMode(io, stderr, enabled),
        .windows => windows.writeMode(stderr, enabled),
        else => cliUnsupported(void, stderr),
    };
}

fn cliUnsupported(comptime T: type, stderr: *std.Io.Writer) !T {
    return cli.fail(T, "unsupported operating system", stderr, .{});
}

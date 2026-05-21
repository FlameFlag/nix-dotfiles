const std = @import("std");

const Context = @import("../context.zig").Context;

pub fn extractXz(ctx: *Context, bytes: []const u8, dest: std.Io.Dir, strip_components: u32) !void {
    var input: std.Io.Reader = .fixed(bytes);
    try extractXzReader(ctx, &input, dest, strip_components);
}

pub fn extractXzReader(ctx: *Context, input: *std.Io.Reader, dest: std.Io.Dir, strip_components: u32) !void {
    const buffer = try ctx.allocator.alloc(u8, 8192);
    var buffer_owner = true;
    errdefer if (buffer_owner) ctx.allocator.free(buffer);
    var xz = try std.compress.xz.Decompress.init(input, ctx.allocator, buffer);
    buffer_owner = false;
    defer xz.deinit();
    try std.tar.extract(ctx.io, dest, &xz.reader, .{ .strip_components = strip_components });
}

pub fn extractGz(ctx: *Context, bytes: []const u8, dest: std.Io.Dir, strip_components: u32) !void {
    var input: std.Io.Reader = .fixed(bytes);
    return extractGzReader(ctx, &input, dest, strip_components);
}

pub fn extractGzReader(ctx: *Context, input: *std.Io.Reader, dest: std.Io.Dir, strip_components: u32) !void {
    const buffer = try ctx.allocator.alloc(u8, std.compress.flate.max_window_len);
    defer ctx.allocator.free(buffer);
    var gz = std.compress.flate.Decompress.init(input, .gzip, buffer);
    try std.tar.extract(ctx.io, dest, &gz.reader, .{ .strip_components = strip_components });
}

const std = @import("std");

const Context = @import("context.zig").Context;
const tar = @import("archive/tar.zig");
const zip = @import("archive/zip.zig");

pub const Kind = enum { tar_xz, tar_gz, zip };

pub fn extract(ctx: *Context, bytes: []const u8, dest_path: []const u8, kind: Kind, strip_components: u32) !void {
    try std.Io.Dir.cwd().createDirPath(ctx.io, dest_path);
    var dest = try std.Io.Dir.openDirAbsolute(ctx.io, dest_path, .{});
    defer dest.close(ctx.io);

    switch (kind) {
        .tar_xz => try tar.extractXz(ctx, bytes, dest, strip_components),
        .tar_gz => try tar.extractGz(ctx, bytes, dest, strip_components),
        .zip => try zip.extract(ctx, bytes, dest_path, .zip, strip_components),
    }
}

pub fn extractFile(
    ctx: *Context,
    archive_path: []const u8,
    dest_path: []const u8,
    kind: Kind,
    strip_components: u32,
) !void {
    try std.Io.Dir.cwd().createDirPath(ctx.io, dest_path);
    var dest = try std.Io.Dir.openDirAbsolute(ctx.io, dest_path, .{});
    defer dest.close(ctx.io);

    var file = try std.Io.Dir.cwd().openFile(ctx.io, archive_path, .{});
    defer file.close(ctx.io);

    var read_buffer: [8192]u8 = undefined;
    var reader = file.reader(ctx.io, &read_buffer);
    switch (kind) {
        .tar_xz => try tar.extractXzReader(ctx, &reader.interface, dest, strip_components),
        .tar_gz => try tar.extractGzReader(ctx, &reader.interface, dest, strip_components),
        .zip => try zip.extractFile(ctx, archive_path, dest_path, .zip, strip_components),
    }
}

test {
    std.testing.refAllDecls(tar);
    std.testing.refAllDecls(zip);
}

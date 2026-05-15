const std = @import("std");
const common = @import("common");
const Context = @import("context.zig").Context;

pub const Kind = enum { tar_xz, tar_gz, zip };

const tiny_tar_xz_hex =
    "fd377a585a0000016922de360200210116000000742fe5a3e027ff005e5d0038" ++
    "1ac9159cbbcdf1024567ec4d51ba8e6c3ddafb60b2e29c3039b2cfe0ce1b5549" ++
    "f6393ca9b0ce0578f446c039ceb7eb9bd4b50983443edca6356045e077f9b0f4" ++
    "1ff7c04950991b5177d03b1f732d8f11bc96348eeb12e54eae14280900000000" ++
    "d4bafffc00017680500000003185c5643e300d8b020000000001595a";
const tiny_tar_xz_len = tiny_tar_xz_hex.len / 2;

pub fn extract(ctx: *Context, bytes: []const u8, dest_path: []const u8, kind: Kind, strip_components: u32) !void {
    try std.Io.Dir.cwd().createDirPath(ctx.io, dest_path);
    var dest = try std.Io.Dir.openDirAbsolute(ctx.io, dest_path, .{});
    defer dest.close(ctx.io);

    switch (kind) {
        .tar_xz => try extractTarXz(ctx, bytes, dest, strip_components),
        .tar_gz => try extractTarGz(ctx, bytes, dest, strip_components),
        .zip => try extractZip(ctx, bytes, dest_path, dest),
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
        .tar_xz => try extractTarXzReader(ctx, &reader.interface, dest, strip_components),
        .tar_gz => try extractTarGzReader(ctx, &reader.interface, dest, strip_components),
        .zip => try std.zip.extract(dest, &reader, .{}),
    }
}

fn extractTarXz(ctx: *Context, bytes: []const u8, dest: std.Io.Dir, strip_components: u32) !void {
    var input: std.Io.Reader = .fixed(bytes);
    try extractTarXzReader(ctx, &input, dest, strip_components);
}

fn extractTarXzReader(ctx: *Context, input: *std.Io.Reader, dest: std.Io.Dir, strip_components: u32) !void {
    const buffer = try ctx.allocator.alloc(u8, 8192);
    var buffer_owner = true;
    errdefer if (buffer_owner) ctx.allocator.free(buffer);
    var xz = try std.compress.xz.Decompress.init(input, ctx.allocator, buffer);
    buffer_owner = false;
    defer xz.deinit();
    try std.tar.extract(ctx.io, dest, &xz.reader, .{ .strip_components = strip_components });
}

fn extractTarGz(ctx: *Context, bytes: []const u8, dest: std.Io.Dir, strip_components: u32) !void {
    var input: std.Io.Reader = .fixed(bytes);
    return extractTarGzReader(ctx, &input, dest, strip_components);
}

fn extractTarGzReader(ctx: *Context, input: *std.Io.Reader, dest: std.Io.Dir, strip_components: u32) !void {
    const buffer = try ctx.allocator.alloc(u8, std.compress.flate.max_window_len);
    defer ctx.allocator.free(buffer);
    var gz = std.compress.flate.Decompress.init(input, .gzip, buffer);
    try std.tar.extract(ctx.io, dest, &gz.reader, .{ .strip_components = strip_components });
}

fn extractZip(ctx: *Context, bytes: []const u8, dest_path: []const u8, dest: std.Io.Dir) !void {
    const archive_path = try std.fs.path.join(ctx.allocator, &.{ dest_path, ".download.zip" });
    defer ctx.allocator.free(archive_path);
    errdefer deleteTempArchive(ctx, archive_path);

    try common.fs.writeFile(ctx.io, archive_path, bytes, .{ .read = true });
    var file = try std.Io.Dir.cwd().openFile(ctx.io, archive_path, .{});
    defer file.close(ctx.io);

    var read_buffer: [8192]u8 = undefined;
    var reader = file.reader(ctx.io, &read_buffer);
    try std.zip.extract(dest, &reader, .{});
    try std.Io.Dir.cwd().deleteFile(ctx.io, archive_path);
}

fn deleteTempArchive(ctx: *Context, archive_path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(ctx.io, archive_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => common.output.stderr(
            ctx.io,
            "warning: failed to delete temporary archive {s}: {s}\n",
            .{ archive_path, @errorName(err) },
        ) catch return,
    };
}

fn testingContext(env: *std.process.Environ.Map) Context {
    return .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = env,
        .home = "",
        .bin_dir = "",
        .opt_dir = "",
    };
}

fn tmpPath(allocator: std.mem.Allocator, tmp: std.testing.TmpDir, parts: []const []const u8) ![]u8 {
    return common.testing.tmpPath(allocator, tmp, parts);
}

fn tinyTarXzBytes() ![tiny_tar_xz_len]u8 {
    var bytes: [tiny_tar_xz_len]u8 = undefined;
    _ = try std.fmt.hexToBytes(&bytes, tiny_tar_xz_hex);
    return bytes;
}

test "zip extraction cleans temporary archive after failure" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest"});
    defer ctx.allocator.free(dest);
    const temp_archive = try std.fs.path.join(ctx.allocator, &.{ dest, ".download.zip" });
    defer ctx.allocator.free(temp_archive);

    if (extract(&ctx, "not a zip archive", dest, .zip, 0)) {
        return error.TestExpectedError;
    } else |_| {}

    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().access(ctx.io, temp_archive, .{}),
    );
}

test "tar xz extraction releases buffer when stream header is invalid" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest"});
    defer ctx.allocator.free(dest);

    try std.testing.expectError(error.NotXzStream, extract(&ctx, "not an xz archive", dest, .tar_xz, 0));
}

test "tar xz extraction releases decompressor-owned buffer after success" {
    const bytes = try tinyTarXzBytes();

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest"});
    defer ctx.allocator.free(dest);
    const tool_path = try tmpPath(ctx.allocator, tmp, &.{ "dest", "tool" });
    defer ctx.allocator.free(tool_path);

    try extract(&ctx, bytes[0..], dest, .tar_xz, 1);
    try std.Io.Dir.cwd().access(ctx.io, tool_path, .{ .execute = true });
}

test "tar xz extraction streams from a downloaded file" {
    const bytes = try tinyTarXzBytes();

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const archive_path = try tmpPath(ctx.allocator, tmp, &.{"download.tar.xz"});
    defer ctx.allocator.free(archive_path);
    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest-file"});
    defer ctx.allocator.free(dest);
    const tool_path = try tmpPath(ctx.allocator, tmp, &.{ "dest-file", "tool" });
    defer ctx.allocator.free(tool_path);

    try common.fs.writeFile(ctx.io, archive_path, bytes[0..], .{});
    try extractFile(&ctx, archive_path, dest, .tar_xz, 1);
    try std.Io.Dir.cwd().access(ctx.io, tool_path, .{ .execute = true });
}

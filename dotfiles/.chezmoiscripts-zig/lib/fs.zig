const std = @import("std");

/// Writes `contents` to `path` only when the existing file differs.
///
/// Returns whether the file was replaced.
pub fn writeTextIfChanged(rt: anytype, path: []const u8, contents: []const u8) !bool {
    if (std.Io.Dir.cwd().readFileAlloc(rt.io, path, rt.allocator, .limited(64 * 1024 * 1024))) |current| {
        defer rt.allocator.free(current);
        if (std.mem.eql(u8, current, contents)) return false;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    var file = try std.Io.Dir.cwd().createFileAtomic(rt.io, path, .{ .make_path = true, .replace = true });
    defer file.deinit(rt.io);
    var buffer: [8192]u8 = undefined;
    var writer = file.file.writer(rt.io, &buffer);
    try writer.interface.writeAll(contents);
    try writer.interface.flush();
    try file.replace(rt.io);
    return true;
}

/// Creates a unique temporary directory for a chezmoi script.
///
/// Caller owns returned memory and is responsible for deleting the directory.
pub fn tempDir(rt: anytype) ![]u8 {
    const base = try @import("env.zig").envOrNull(rt, "TMPDIR") orelse try rt.allocator.dupe(u8, "/tmp");
    defer rt.allocator.free(base);
    var random_bytes: [8]u8 = undefined;
    try rt.io.randomSecure(&random_bytes);
    const nonce = std.mem.readInt(u64, &random_bytes, .little);
    const path = try std.fmt.allocPrint(rt.allocator, "{s}/chezmoi-script-{x}", .{
        std.mem.trimEnd(u8, base, "/"),
        nonce,
    });
    try std.Io.Dir.cwd().createDirPath(rt.io, path);
    return path;
}

test "writeTextIfChanged writes atomically and skips unchanged content" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/file.txt", .{tmp.sub_path});
    defer allocator.free(path);

    const rt = struct {
        allocator: std.mem.Allocator,
        io: std.Io,
    }{
        .allocator = allocator,
        .io = std.testing.io,
    };

    try std.testing.expect(try writeTextIfChanged(rt, path, "first"));
    try std.testing.expect(!try writeTextIfChanged(rt, path, "first"));
    try std.testing.expect(try writeTextIfChanged(rt, path, "second"));

    const current = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, allocator, .limited(1024));
    defer allocator.free(current);
    try std.testing.expectEqualStrings("second", current);
}

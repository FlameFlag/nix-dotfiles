const std = @import("std");

pub fn tmpPath(allocator: std.mem.Allocator, tmp: std.testing.TmpDir, parts: []const []const u8) ![]u8 {
    const cwd = try std.process.currentPathAlloc(std.testing.io, allocator);
    defer allocator.free(cwd);

    var root_parts = try std.ArrayList([]const u8).initCapacity(allocator, 3 + parts.len);
    defer root_parts.deinit(allocator);
    try root_parts.appendSlice(allocator, &.{ cwd, ".zig-cache", "tmp", &tmp.sub_path });
    try root_parts.appendSlice(allocator, parts);
    return std.fs.path.join(allocator, root_parts.items);
}

test "tmpPath joins testing tmp directory with path parts" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try tmpPath(std.testing.allocator, tmp, &.{ "dir", "file" });
    defer std.testing.allocator.free(path);

    const suffix = try std.fs.path.join(std.testing.allocator, &.{
        ".zig-cache",
        "tmp",
        &tmp.sub_path,
        "dir",
        "file",
    });
    defer std.testing.allocator.free(suffix);
    try std.testing.expect(std.mem.endsWith(u8, path, suffix));
}

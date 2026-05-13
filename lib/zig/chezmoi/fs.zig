const std = @import("std");
const builtin = @import("builtin");

const env = @import("env.zig");

const posix_temp_env_var = "TMPDIR";
const posix_default_temp_dir = "/tmp";
const temp_dir_prefix = "chezmoi-script";
const temp_dir_attempts = 8;
const text_file_limit = 64 * 1024 * 1024;
const write_buffer_size = 8192;

const windows_temp_path_initial_len = if (builtin.os.tag == .windows) std.os.windows.MAX_PATH + 1 else 0;
const WindowsTempApi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn GetTempPath2W(
        buffer_len: std.os.windows.DWORD,
        buffer: std.os.windows.LPWSTR,
    ) callconv(.winapi) std.os.windows.DWORD;
    extern "kernel32" fn GetTempPathW(
        buffer_len: std.os.windows.DWORD,
        buffer: std.os.windows.LPWSTR,
    ) callconv(.winapi) std.os.windows.DWORD;
} else struct {};

/// Writes `contents` to `path` only when the existing file differs.
///
/// Returns whether the file was replaced.
pub fn writeTextIfChanged(rt: anytype, path: []const u8, contents: []const u8) !bool {
    if (std.Io.Dir.cwd().readFileAlloc(rt.io, path, rt.allocator, .limited(text_file_limit))) |current| {
        defer rt.allocator.free(current);
        if (std.mem.eql(u8, current, contents)) return false;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    var file = try std.Io.Dir.cwd().createFileAtomic(rt.io, path, .{ .make_path = true, .replace = true });
    defer file.deinit(rt.io);
    var buffer: [write_buffer_size]u8 = undefined;
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
    const base = try tempRoot(rt);
    defer rt.allocator.free(base);
    const trimmed_base = std.mem.trimEnd(u8, base, "/");
    const root = if (trimmed_base.len == 0) "/" else trimmed_base;
    try std.Io.Dir.cwd().createDirPath(rt.io, root);

    var attempt: u8 = 0;
    while (attempt < temp_dir_attempts) : (attempt += 1) {
        var random_bytes: [8]u8 = undefined;
        try rt.io.randomSecure(&random_bytes);
        const nonce = std.mem.readInt(u64, &random_bytes, .little);
        const path = try std.fmt.allocPrint(rt.allocator, "{s}/{s}-{x}", .{
            root,
            temp_dir_prefix,
            nonce,
        });
        std.Io.Dir.cwd().createDir(rt.io, path, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {
                rt.allocator.free(path);
                continue;
            },
            else => {
                rt.allocator.free(path);
                return err;
            },
        };
        return path;
    }

    return error.TemporaryDirectoryCollision;
}

fn tempRoot(rt: anytype) ![]u8 {
    return switch (builtin.os.tag) {
        .windows => windowsTempRoot(rt.allocator),
        else => posixTempRoot(rt),
    };
}

fn posixTempRoot(rt: anytype) ![]u8 {
    const value = try env.envOrNull(rt, posix_temp_env_var) orelse return rt.allocator.dupe(u8, posix_default_temp_dir);
    if (std.mem.trim(u8, value, " \t\r\n").len != 0) return value;
    rt.allocator.free(value);
    return rt.allocator.dupe(u8, posix_default_temp_dir);
}

fn windowsTempRoot(allocator: std.mem.Allocator) ![]u8 {
    var stack_buffer: [windows_temp_path_initial_len:0]u16 = undefined;
    if (try windowsTempRootFromApi(allocator, WindowsTempApi.GetTempPath2W, &stack_buffer)) |path| return path;
    if (try windowsTempRootFromApi(allocator, WindowsTempApi.GetTempPathW, &stack_buffer)) |path| return path;
    return error.TemporaryDirectoryUnavailable;
}

fn windowsTempRootFromApi(
    allocator: std.mem.Allocator,
    api: *const fn (std.os.windows.DWORD, std.os.windows.LPWSTR) callconv(.winapi) std.os.windows.DWORD,
    stack_buffer: [:0]u16,
) !?[]u8 {
    const written = api(@intCast(stack_buffer.len), stack_buffer.ptr);
    if (written == 0) return error.TemporaryDirectoryUnavailable;

    if (written < stack_buffer.len) {
        return @as(?[]u8, try std.unicode.utf16LeToUtf8Alloc(allocator, stack_buffer[0..written]));
    }

    var heap_buffer = try allocator.allocSentinel(u16, written, 0);
    defer allocator.free(heap_buffer);
    const heap_written = api(@intCast(heap_buffer.len), heap_buffer.ptr);
    if (heap_written == 0) return error.TemporaryDirectoryUnavailable;
    if (heap_written >= heap_buffer.len) return error.NameTooLong;
    return @as(?[]u8, try std.unicode.utf16LeToUtf8Alloc(allocator, heap_buffer[0..heap_written]));
}

test "writeTextIfChanged writes atomically and skips unchanged content" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/file.txt", .{tmp.sub_path});
    defer allocator.free(path);

    const rt: struct {
        allocator: std.mem.Allocator,
        io: std.Io,
    } = .{
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

test "tempDir honors TMPDIR trims trailing slashes and creates unique directories" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const tmp_root = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/nested-tmp///", .{tmp.sub_path});
    defer allocator.free(tmp_root);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, tmp_root);

    var map = std.process.Environ.Map.init(allocator);
    defer map.deinit();
    try map.put("TMPDIR", tmp_root);

    const rt: struct {
        allocator: std.mem.Allocator,
        io: std.Io,
        env: *std.process.Environ.Map,
    } = .{
        .allocator = allocator,
        .io = std.testing.io,
        .env = &map,
    };

    const first = try tempDir(rt);
    defer allocator.free(first);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, first) catch {};
    const second = try tempDir(rt);
    defer allocator.free(second);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, second) catch {};

    const expected_prefix = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/nested-tmp/chezmoi-script-",
        .{tmp.sub_path},
    );
    defer allocator.free(expected_prefix);

    try std.testing.expect(std.mem.startsWith(u8, first, expected_prefix));
    try std.testing.expect(std.mem.startsWith(u8, second, expected_prefix));
    try std.testing.expect(!std.mem.eql(u8, first, second));
    try std.Io.Dir.cwd().access(std.testing.io, first, .{});
    try std.Io.Dir.cwd().access(std.testing.io, second, .{});
}

test "posixTempRoot reads TMPDIR and falls back to the platform default" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("TMPDIR", "");

    const rt: struct {
        allocator: std.mem.Allocator,
        env: *std.process.Environ.Map,
    } = .{
        .allocator = std.testing.allocator,
        .env = &map,
    };

    const blank_root = try posixTempRoot(rt);
    defer std.testing.allocator.free(blank_root);
    try std.testing.expectEqualStrings(posix_default_temp_dir, blank_root);

    try map.put("TMPDIR", "relative-temp");
    const env_root = try posixTempRoot(rt);
    defer std.testing.allocator.free(env_root);
    try std.testing.expectEqualStrings("relative-temp", env_root);
}

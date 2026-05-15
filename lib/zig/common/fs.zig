const std = @import("std");
const builtin = @import("builtin");

const env = @import("env.zig");

const posix_temp_env_var = "TMPDIR";
const posix_default_temp_dir = "/tmp";
const temp_dir_attempts = 8;
const text_file_limit = 64 * 1024 * 1024;
const write_buffer_size = 8192;
const ascii_whitespace = " \t\r\n";

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

/// Returns `bytes` without common ASCII whitespace at either end.
pub fn trimAsciiWhitespace(bytes: []const u8) []const u8 {
    return std.mem.trim(u8, bytes, ascii_whitespace);
}

/// Reads a small text file and returns a trimmed view into `buffer`.
///
/// Missing or inaccessible files return `null`; other I/O errors are preserved.
pub fn readTrimmed(io: std.Io, path: []const u8, buffer: []u8) !?[]const u8 {
    const contents = std.Io.Dir.cwd().readFile(io, path, buffer) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return null,
        else => return err,
    };
    return trimAsciiWhitespace(contents);
}

/// Reads a small text file and returns an owned trimmed copy.
///
/// Missing or inaccessible files return `null`.
pub fn readTrimmedAlloc(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !?[]u8 {
    var buffer: [256]u8 = undefined;
    const contents = try readTrimmed(io, path, &buffer) orelse return null;
    return allocator.dupe(u8, contents);
}

/// Writes `contents` to `path`, creating parent directories when needed.
pub fn writeFile(io: std.Io, path: []const u8, contents: []const u8, flags: std.Io.Dir.CreateFileOptions) !void {
    if (std.fs.path.dirname(path)) |dir| {
        try std.Io.Dir.cwd().createDirPath(io, dir);
    }
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = contents,
        .flags = flags,
    });
}

/// Writes an executable file, creating parent directories when needed.
pub fn writeExecutableFile(io: std.Io, path: []const u8, contents: []const u8) !void {
    try writeFile(io, path, contents, .{ .permissions = .executable_file });
    if (builtin.os.tag != .windows) {
        try std.Io.Dir.cwd().setFilePermissions(io, path, .executable_file, .{});
    }
}

/// Extracts a gzip-compressed tar archive to `dest_path`.
pub fn extractTarGz(rt: anytype, bytes: []const u8, dest_path: []const u8, strip_components: u32) !void {
    try std.Io.Dir.cwd().createDirPath(rt.io, dest_path);
    var dest = try openDir(rt, dest_path, .{});
    defer dest.close(rt.io);
    try extractTarGzToDir(rt, bytes, dest, strip_components);
}

/// Extracts a gzip-compressed tar archive to an already-open destination dir.
pub fn extractTarGzToDir(rt: anytype, bytes: []const u8, dest: std.Io.Dir, strip_components: u32) !void {
    var input: std.Io.Reader = .fixed(bytes);
    const buffer = try rt.allocator.alloc(u8, std.compress.flate.max_window_len);
    defer rt.allocator.free(buffer);
    var gz = std.compress.flate.Decompress.init(&input, .gzip, buffer);
    try std.tar.extract(rt.io, dest, &gz.reader, .{ .strip_components = strip_components });
}

/// Recursively copies a directory tree.
pub fn copyDirRecursive(rt: anytype, src_path: []const u8, dst_path: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(rt.io, dst_path);

    var src = try openDir(rt, src_path, .{ .iterate = true });
    defer src.close(rt.io);

    var walker = try src.walk(rt.allocator);
    defer walker.deinit();

    while (try walker.next(rt.io)) |entry| {
        const dst = try std.fs.path.join(rt.allocator, &.{ dst_path, entry.path });
        defer rt.allocator.free(dst);

        switch (entry.kind) {
            .directory => try std.Io.Dir.cwd().createDirPath(rt.io, dst),
            .file => try entry.dir.copyFile(entry.basename, .cwd(), dst, rt.io, .{ .make_path = true }),
            .sym_link => try copySymlink(rt, entry.dir, entry.basename, dst),
            else => return error.UnsupportedFileType,
        }
    }
}

fn copySymlink(rt: anytype, src_dir: std.Io.Dir, src_name: []const u8, dst_path: []const u8) !void {
    if (std.fs.path.dirname(dst_path)) |parent| {
        try std.Io.Dir.cwd().createDirPath(rt.io, parent);
    }

    var target_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const target_len = try src_dir.readLink(rt.io, src_name, &target_buffer);
    try std.Io.Dir.cwd().symLink(rt.io, target_buffer[0..target_len], dst_path, .{});
}

fn openDir(rt: anytype, path: []const u8, options: std.Io.Dir.OpenOptions) !std.Io.Dir {
    return if (std.fs.path.isAbsolute(path))
        std.Io.Dir.openDirAbsolute(rt.io, path, options)
    else
        std.Io.Dir.cwd().openDir(rt.io, path, options);
}

/// Creates a unique temporary directory under the platform temp root.
///
/// Caller owns returned memory and is responsible for deleting the directory.
pub fn tempDir(rt: anytype, prefix: []const u8) ![]u8 {
    const base = try tempRoot(rt);
    defer rt.allocator.free(base);
    const trimmed_base = std.mem.trimEnd(u8, base, "/\\");
    const root = if (trimmed_base.len == 0) "/" else trimmed_base;
    try std.Io.Dir.cwd().createDirPath(rt.io, root);

    var attempt: u8 = 0;
    while (attempt < temp_dir_attempts) : (attempt += 1) {
        var random_bytes: [8]u8 = undefined;
        try rt.io.randomSecure(&random_bytes);
        const nonce = std.mem.readInt(u64, &random_bytes, .little);
        const leaf = try std.fmt.allocPrint(rt.allocator, "{s}-{x}", .{
            prefix,
            nonce,
        });
        defer rt.allocator.free(leaf);
        const path = try std.fs.path.join(rt.allocator, &.{ root, leaf });
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
    if (trimAsciiWhitespace(value).len != 0) return value;
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

const TestRuntime = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    env: *std.process.Environ.Map,
};

fn testRuntime(env_map: *std.process.Environ.Map) TestRuntime {
    return .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = env_map,
    };
}

test "writeTextIfChanged writes atomically and skips unchanged content" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    const rt = testRuntime(&env_map);

    const path = try std.fmt.allocPrint(rt.allocator, ".zig-cache/tmp/{s}/file.txt", .{tmp.sub_path});
    defer rt.allocator.free(path);

    try std.testing.expect(try writeTextIfChanged(rt, path, "first"));
    try std.testing.expect(!try writeTextIfChanged(rt, path, "first"));
    try std.testing.expect(try writeTextIfChanged(rt, path, "second"));

    const current = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, rt.allocator, .limited(1024));
    defer rt.allocator.free(current);
    try std.testing.expectEqualStrings("second", current);
}

test "copyDirRecursive copies files directories and symlinks" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    const rt = testRuntime(&env_map);

    const root = try std.fmt.allocPrint(rt.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer rt.allocator.free(root);
    const src = try std.fs.path.join(rt.allocator, &.{ root, "src" });
    defer rt.allocator.free(src);
    const dst = try std.fs.path.join(rt.allocator, &.{ root, "dst" });
    defer rt.allocator.free(dst);
    const nested = try std.fs.path.join(rt.allocator, &.{ src, "nested" });
    defer rt.allocator.free(nested);
    const file = try std.fs.path.join(rt.allocator, &.{ nested, "file.txt" });
    defer rt.allocator.free(file);
    const link = try std.fs.path.join(rt.allocator, &.{ src, "file-link" });
    defer rt.allocator.free(link);

    try std.Io.Dir.cwd().createDirPath(std.testing.io, nested);
    var created = try std.Io.Dir.cwd().createFile(std.testing.io, file, .{});
    try created.writeStreamingAll(std.testing.io, "contents");
    created.close(std.testing.io);
    const link_target = try std.fs.path.join(rt.allocator, &.{ "nested", "file.txt" });
    defer rt.allocator.free(link_target);
    try std.Io.Dir.cwd().symLink(std.testing.io, link_target, link, .{});

    try copyDirRecursive(rt, src, dst);

    const copied_path = try std.fs.path.join(rt.allocator, &.{ dst, "nested/file.txt" });
    defer rt.allocator.free(copied_path);
    const copied = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        copied_path,
        rt.allocator,
        .limited(1024),
    );
    defer rt.allocator.free(copied);
    try std.testing.expectEqualStrings("contents", copied);

    var link_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const link_path = try std.fs.path.join(rt.allocator, &.{ dst, "file-link" });
    defer rt.allocator.free(link_path);
    const link_len = try std.Io.Dir.cwd().readLink(std.testing.io, link_path, &link_buffer);
    try std.testing.expectEqualStrings(link_target, link_buffer[0..link_len]);
}

test "readTrimmed and writeExecutableFile use std file helpers" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    const rt = testRuntime(&env_map);

    const path = try std.fmt.allocPrint(rt.allocator, ".zig-cache/tmp/{s}/bin/tool", .{tmp.sub_path});
    defer rt.allocator.free(path);

    try writeExecutableFile(rt.io, path, "  ok\n");

    var buffer: [32]u8 = undefined;
    const trimmed = try readTrimmed(rt.io, path, &buffer) orelse return error.TestExpectedFile;
    try std.testing.expectEqualStrings("ok", trimmed);
    try std.Io.Dir.cwd().access(rt.io, path, .{ .execute = true });
}

test "tempDir honors TMPDIR trims trailing slashes and creates unique directories" {
    if (builtin.os.tag == .windows) return;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    const rt = testRuntime(&env_map);

    const tmp_root = try std.fmt.allocPrint(rt.allocator, ".zig-cache/tmp/{s}/nested-tmp///", .{tmp.sub_path});
    defer rt.allocator.free(tmp_root);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, tmp_root);
    try env_map.put("TMPDIR", tmp_root);

    const first = try tempDir(rt, "test-prefix");
    defer rt.allocator.free(first);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, first) catch {};
    const second = try tempDir(rt, "test-prefix");
    defer rt.allocator.free(second);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, second) catch {};

    const expected_prefix = try std.fmt.allocPrint(
        rt.allocator,
        ".zig-cache/tmp/{s}/nested-tmp/test-prefix-",
        .{tmp.sub_path},
    );
    defer rt.allocator.free(expected_prefix);

    try std.testing.expect(std.mem.startsWith(u8, first, expected_prefix));
    try std.testing.expect(std.mem.startsWith(u8, second, expected_prefix));
    try std.testing.expect(!std.mem.eql(u8, first, second));
    try std.Io.Dir.cwd().access(std.testing.io, first, .{});
    try std.Io.Dir.cwd().access(std.testing.io, second, .{});
}

test "posixTempRoot reads TMPDIR and falls back to the platform default" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("TMPDIR", "");

    const rt = testRuntime(&env_map);

    const blank_root = try posixTempRoot(rt);
    defer rt.allocator.free(blank_root);
    try std.testing.expectEqualStrings(posix_default_temp_dir, blank_root);

    try env_map.put("TMPDIR", "relative-temp");
    const env_root = try posixTempRoot(rt);
    defer rt.allocator.free(env_root);
    try std.testing.expectEqualStrings("relative-temp", env_root);
}

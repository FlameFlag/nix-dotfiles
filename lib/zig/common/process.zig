const std = @import("std");
const builtin = @import("builtin");
const fs = @import("fs.zig");
const common_testing = @import("testing.zig");

const Allocator = std.mem.Allocator;
const output_limit = 64 * 1024 * 1024;
const default_path = "/usr/local/bin:/bin:/usr/bin";
const default_windows_pathext = ".COM;.EXE;.BAT;.CMD";

pub const CommandResult = struct {
    exit_code: u8,
    stdout: []u8,
    stderr: []u8,

    /// Frees captured stdout and stderr.
    pub fn deinit(self: *CommandResult, allocator: Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
        self.* = undefined;
    }
};

/// Returns the executable path for `bin`, or null when it cannot be found.
///
/// Caller owns a returned path.
pub fn pathOf(rt: anytype, bin: []const u8) !?[]u8 {
    if (isPathLike(bin)) {
        std.Io.Dir.cwd().access(rt.io, bin, .{ .execute = true }) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => return null,
            else => return err,
        };
        return @as(?[]u8, try rt.allocator.dupe(u8, bin));
    }

    const path_env = rt.env.get("PATH") orelse default_path;
    var parts = std.mem.tokenizeScalar(u8, path_env, std.fs.path.delimiter);
    while (parts.next()) |dir| {
        if (try pathInDir(rt, dir, bin)) |full| return full;
    }
    return null;
}

fn pathInDir(rt: anytype, dir: []const u8, bin: []const u8) !?[]u8 {
    if (try accessCandidate(rt, dir, bin)) |full| return full;
    if (builtin.os.tag != .windows or std.fs.path.extension(bin).len != 0) return null;

    const pathext = rt.env.get("PATHEXT") orelse default_windows_pathext;
    var extensions = std.mem.tokenizeScalar(u8, pathext, ';');
    while (extensions.next()) |extension| {
        const candidate = try std.fmt.allocPrint(rt.allocator, "{s}{s}", .{ bin, extension });
        defer rt.allocator.free(candidate);
        if (try accessCandidate(rt, dir, candidate)) |full| return full;
    }
    return null;
}

fn accessCandidate(rt: anytype, dir: []const u8, bin: []const u8) !?[]u8 {
    const full = try std.fs.path.join(rt.allocator, &.{ dir, bin });
    errdefer rt.allocator.free(full);
    std.Io.Dir.cwd().access(rt.io, full, .{ .execute = true }) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => {
            rt.allocator.free(full);
            return null;
        },
        else => return err,
    };
    return full;
}

/// Returns whether `bin` can be executed directly or found in PATH.
pub fn hasBin(rt: anytype, bin: []const u8) !bool {
    const maybe = try pathOf(rt, bin);
    if (maybe) |path| {
        rt.allocator.free(path);
        return true;
    }
    return false;
}

fn isPathLike(bin: []const u8) bool {
    return std.fs.path.isAbsolute(bin) or std.fs.path.dirname(bin) != null;
}

/// Runs a command inheriting stdio.
pub fn run(rt: anytype, argv: []const []const u8) !void {
    return runInCwd(rt, .inherit, argv);
}

/// Runs a command in `cwd` inheriting stdio.
pub fn runInCwd(rt: anytype, cwd: std.process.Child.Cwd, argv: []const []const u8) !void {
    var child = try std.process.spawn(rt.io, .{
        .argv = argv,
        .cwd = cwd,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    defer child.kill(rt.io);
    const term = try child.wait(rt.io);
    switch (term) {
        .exited => |code| if (code == 0) return,
        else => {},
    }
    return error.CommandFailed;
}

/// Runs a command and captures stdout and stderr.
///
/// Caller owns the returned buffers.
pub fn capture(rt: anytype, argv: []const []const u8) !CommandResult {
    const result = try std.process.run(rt.allocator, rt.io, .{
        .argv = argv,
        .stdout_limit = .limited(output_limit),
        .stderr_limit = .limited(output_limit),
    });
    return .{
        .exit_code = switch (result.term) {
            .exited => |code| code,
            else => 1,
        },
        .stdout = result.stdout,
        .stderr = result.stderr,
    };
}

/// Runs a command and returns stdout when it exits successfully.
///
/// Caller owns returned memory.
pub fn text(rt: anytype, argv: []const []const u8) ![]u8 {
    const result = try capture(rt, argv);
    defer rt.allocator.free(result.stderr);
    if (result.exit_code != 0) {
        rt.allocator.free(result.stdout);
        return error.CommandFailed;
    }
    return result.stdout;
}

/// Runs a command and returns trimmed stdout when it exits successfully.
///
/// Caller owns returned memory.
pub fn trimmedText(rt: anytype, argv: []const []const u8) ![]u8 {
    const raw = try text(rt, argv);
    defer rt.allocator.free(raw);
    return rt.allocator.dupe(u8, fs.trimAsciiWhitespace(raw));
}

const TestRuntime = struct {
    allocator: Allocator,
    io: std.Io,
    env: *std.process.Environ.Map,
};

fn testRuntime(env: *std.process.Environ.Map) TestRuntime {
    return .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = env,
    };
}

fn tmpPath(allocator: Allocator, tmp: std.testing.TmpDir, parts: []const []const u8) ![]u8 {
    return common_testing.tmpPath(allocator, tmp, parts);
}

fn createExecutable(rt: anytype, path: []const u8) !void {
    try fs.writeExecutableFile(rt.io, path, "");
}

test "path lookup skips non-directory PATH entries" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    const rt = testRuntime(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const not_dir = try tmpPath(rt.allocator, tmp, &.{"not-a-dir"});
    defer rt.allocator.free(not_dir);
    const bin_dir = try tmpPath(rt.allocator, tmp, &.{"bin"});
    defer rt.allocator.free(bin_dir);
    const tool_path = try tmpPath(rt.allocator, tmp, &.{ "bin", "tool" });
    defer rt.allocator.free(tool_path);
    const path_env = try std.fmt.allocPrint(rt.allocator, "{s}{c}{s}", .{ not_dir, std.fs.path.delimiter, bin_dir });
    defer rt.allocator.free(path_env);

    var marker = try std.Io.Dir.cwd().createFile(rt.io, not_dir, .{});
    marker.close(rt.io);
    try createExecutable(rt, tool_path);
    try env.put("PATH", path_env);

    const resolved = try pathOf(rt, "tool") orelse return error.TestExpectedPath;
    defer rt.allocator.free(resolved);
    try std.testing.expectEqualStrings(tool_path, resolved);
}

test "hasBin rejects missing PATH entries and direct missing paths" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("PATH", "");

    const rt = testRuntime(&env);

    try std.testing.expect(!try hasBin(rt, "definitely-not-a-real-command"));
    try std.testing.expect(!try hasBin(rt, "./definitely-not-a-real-command"));
}

test "hasBin accepts executables found in PATH and direct executable paths" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    const rt = testRuntime(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const bin_dir = try tmpPath(rt.allocator, tmp, &.{"bin"});
    defer rt.allocator.free(bin_dir);
    const executable_name = if (builtin.os.tag == .windows) "tool.exe" else "tool";
    const executable_path = try tmpPath(rt.allocator, tmp, &.{ "bin", executable_name });
    defer rt.allocator.free(executable_path);

    try createExecutable(rt, executable_path);
    try env.put("PATH", bin_dir);

    try std.testing.expect(try hasBin(rt, "tool"));
    try std.testing.expect(try hasBin(rt, executable_path));
}

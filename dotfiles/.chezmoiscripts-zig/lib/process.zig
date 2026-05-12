const std = @import("std");

const Allocator = std.mem.Allocator;

pub const CommandResult = struct {
    exit_code: u8,
    stdout: []u8,
    stderr: []u8,

    /// Frees captured stdout and stderr.
    pub fn deinit(self: CommandResult, allocator: Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

/// Returns whether `bin` can be executed directly or found in PATH.
pub fn hasBin(rt: anytype, bin: []const u8) !bool {
    if (std.mem.findScalar(u8, bin, '/') != null) {
        std.Io.Dir.cwd().access(rt.io, bin, .{ .execute = true }) catch |err| return switch (err) {
            error.FileNotFound, error.AccessDenied => false,
            else => err,
        };
        return true;
    }

    const path_env = rt.env.get("PATH") orelse "/usr/local/bin:/bin:/usr/bin";
    var paths = std.mem.tokenizeScalar(u8, path_env, ':');
    while (paths.next()) |dir| {
        const full_path = try std.fs.path.join(rt.allocator, &.{ dir, bin });
        defer rt.allocator.free(full_path);
        std.Io.Dir.cwd().access(rt.io, full_path, .{ .execute = true }) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => continue,
            else => return err,
        };
        return true;
    }
    return false;
}

/// Runs a command inheriting stdio.
pub fn command(rt: anytype, argv: []const []const u8) !void {
    var child = try std.process.spawn(rt.io, .{
        .argv = argv,
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
pub fn commandQuiet(rt: anytype, argv: []const []const u8) !CommandResult {
    const result = try std.process.run(rt.allocator, rt.io, .{
        .argv = argv,
        .stdout_limit = .limited(64 * 1024 * 1024),
        .stderr_limit = .limited(64 * 1024 * 1024),
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
pub fn commandText(rt: anytype, argv: []const []const u8) ![]u8 {
    const result = try commandQuiet(rt, argv);
    defer rt.allocator.free(result.stderr);
    if (result.exit_code != 0) {
        rt.allocator.free(result.stdout);
        return error.CommandFailed;
    }
    return result.stdout;
}

/// Runs a command and returns stdout or a copy of `fallback`.
///
/// Caller owns returned memory.
pub fn commandTextOr(rt: anytype, argv: []const []const u8, fallback: []const u8) ![]u8 {
    var result = try commandQuiet(rt, argv);
    defer result.deinit(rt.allocator);
    if (result.exit_code != 0) return try rt.allocator.dupe(u8, fallback);
    return try rt.allocator.dupe(u8, result.stdout);
}

/// Writes command stdout to `path` only when `bin` is available.
///
/// Returns whether `path` was updated.
pub fn writeCommandTextIfAvailable(
    rt: anytype,
    bin: []const u8,
    path: []const u8,
    argv: []const []const u8,
) !bool {
    if (!try hasBin(rt, bin)) return false;
    const output = try commandText(rt, argv);
    defer rt.allocator.free(output);
    return try @import("fs.zig").writeTextIfChanged(rt, path, output);
}

test "hasBin rejects missing PATH entries and direct missing paths" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("PATH", "");

    const rt = struct {
        allocator: Allocator,
        io: std.Io,
        env: *std.process.Environ.Map,
    }{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = &map,
    };

    try std.testing.expect(!try hasBin(rt, "definitely-not-a-real-command"));
    try std.testing.expect(!try hasBin(rt, "./definitely-not-a-real-command"));
}

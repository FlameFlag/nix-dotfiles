const std = @import("std");

/// Returns a GitHub token from the environment or `gh auth token`.
///
/// Caller owns returned memory.
pub fn token(
    allocator: std.mem.Allocator,
    io: std.Io,
    stderr: *std.Io.Writer,
    env: *const std.process.Environ.Map,
) ![]u8 {
    if (try envToken(allocator, env, "GH_TOKEN")) |value| return value;
    if (try envToken(allocator, env, "GITHUB_TOKEN")) |value| return value;
    return ghCliToken(allocator, io, stderr);
}

fn envToken(
    allocator: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    name: []const u8,
) !?[]u8 {
    const value = env.get(name) orelse return null;
    if (value.len == 0) return null;
    return try allocator.dupe(u8, value);
}

fn ghCliToken(allocator: std.mem.Allocator, io: std.Io, stderr: *std.Io.Writer) ![]u8 {
    const result = try std.process.run(allocator, io, .{
        .argv = &.{ "gh", "auth", "token" },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code == 0) {
            return try allocator.dupe(u8, std.mem.trim(u8, result.stdout, " \t\r\n"));
        },
        else => {},
    }

    const message = std.mem.trim(u8, result.stderr, " \t\r\n");
    if (message.len > 0) {
        try stderr.print("error: gh auth token failed: {s}\n", .{message});
    } else {
        try stderr.print("error: gh auth token failed\n", .{});
    }
    try stderr.flush();
    return error.AuthTokenFailed;
}

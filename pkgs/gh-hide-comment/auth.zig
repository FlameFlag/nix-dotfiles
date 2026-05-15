const std = @import("std");
const common = @import("common");

/// Returns a GitHub token from the environment or `gh auth token`.
///
/// Caller owns returned memory.
pub fn token(
    allocator: std.mem.Allocator,
    io: std.Io,
    stderr: *std.Io.Writer,
    env: *const std.process.Environ.Map,
) ![]u8 {
    const rt: Runtime = .{ .allocator = allocator, .env = env };
    if (try common.env.nonEmptyOrNull(rt, "GH_TOKEN")) |value| return value;
    if (try common.env.nonEmptyOrNull(rt, "GITHUB_TOKEN")) |value| return value;
    return ghCliToken(allocator, io, stderr);
}

const Runtime = struct {
    allocator: std.mem.Allocator,
    env: *const std.process.Environ.Map,
};

fn ghCliToken(allocator: std.mem.Allocator, io: std.Io, stderr: *std.Io.Writer) ![]u8 {
    var result = try common.process.capture(.{
        .allocator = allocator,
        .io = io,
    }, &.{ "gh", "auth", "token" });
    defer result.deinit(allocator);

    if (result.exit_code == 0) {
        return allocator.dupe(u8, common.fs.trimAsciiWhitespace(result.stdout));
    }

    const message = common.fs.trimAsciiWhitespace(result.stderr);
    if (message.len > 0) {
        try stderr.print("error: gh auth token failed: {s}\n", .{message});
    } else {
        try stderr.print("error: gh auth token failed\n", .{});
    }
    try stderr.flush();
    return error.AuthTokenFailed;
}

test "envToken copies non-empty tokens only" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("GH_TOKEN", "secret");
    try map.put("EMPTY", "");

    const rt: Runtime = .{ .allocator = std.testing.allocator, .env = &map };
    const value = try common.env.nonEmptyOrNull(rt, "GH_TOKEN") orelse return error.TestExpectedEnvValue;
    defer std.testing.allocator.free(value);
    try std.testing.expectEqualStrings("secret", value);

    try std.testing.expectEqual(null, try common.env.nonEmptyOrNull(rt, "EMPTY"));
    try std.testing.expectEqual(null, try common.env.nonEmptyOrNull(rt, "MISSING"));
}

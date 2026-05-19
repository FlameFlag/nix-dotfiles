const std = @import("std");

const ascii_whitespace = " \t\r\n";

/// Returns a copy of an environment variable or `null` when unset.
///
/// Caller owns returned memory.
pub fn envOrNull(rt: anytype, name: []const u8) !?[]u8 {
    const result = rt.env.get(name) orelse return null;
    return @as(?[]u8, try rt.allocator.dupe(u8, result));
}

/// Returns a trimmed copy of a non-empty environment variable or `null`.
///
/// Caller owns returned memory.
pub fn nonEmptyOrNull(rt: anytype, name: []const u8) !?[]u8 {
    const result = rt.env.get(name) orelse return null;
    const trimmed = std.mem.trim(u8, result, ascii_whitespace);
    if (trimmed.len == 0) return null;
    return @as(?[]u8, try rt.allocator.dupe(u8, trimmed));
}

/// Returns a required, non-empty environment variable.
///
/// Caller owns returned memory.
pub fn required(rt: anytype, name: []const u8) ![]u8 {
    return (try nonEmptyOrNull(rt, name)) orelse {
        if (rt.env.get(name) == null) return error.EnvironmentVariableMissing;
        return error.EmptyEnvironmentVariable;
    };
}

/// Returns a copy of an environment variable or a copy of `fallback`.
///
/// Caller owns returned memory.
pub fn envOrDup(rt: anytype, name: []const u8, fallback: []const u8) ![]u8 {
    return if (try envOrNull(rt, name)) |env_value| env_value else try rt.allocator.dupe(u8, fallback);
}

const TestRuntime = struct {
    allocator: std.mem.Allocator,
    env: *std.process.Environ.Map,
};

fn testRuntime(map: *std.process.Environ.Map) TestRuntime {
    return .{ .allocator = std.testing.allocator, .env = map };
}

test "envOrNull duplicates values and returns null for missing keys" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("PRESENT", "value");

    const rt = testRuntime(&map);
    const present = try envOrNull(rt, "PRESENT") orelse return error.TestExpectedEnvValue;
    defer std.testing.allocator.free(present);
    try std.testing.expectEqualStrings("value", present);
    try std.testing.expectEqual(null, try envOrNull(rt, "MISSING"));
}

test "nonEmptyOrNull trims values and skips blank variables" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("PRESENT", " \tvalue\n");
    try map.put("EMPTY", "");
    try map.put("WHITESPACE", " \r\n\t");

    const rt = testRuntime(&map);
    const present = try nonEmptyOrNull(rt, "PRESENT") orelse return error.TestExpectedEnvValue;
    defer std.testing.allocator.free(present);
    try std.testing.expectEqualStrings("value", present);
    try std.testing.expectEqual(null, try nonEmptyOrNull(rt, "EMPTY"));
    try std.testing.expectEqual(null, try nonEmptyOrNull(rt, "WHITESPACE"));
    try std.testing.expectEqual(null, try nonEmptyOrNull(rt, "MISSING"));
}

test "required rejects missing and empty values" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();

    const rt = testRuntime(&map);
    try std.testing.expectError(error.EnvironmentVariableMissing, required(rt, "HOME"));

    try map.put("HOME", "");
    try std.testing.expectError(error.EmptyEnvironmentVariable, required(rt, "HOME"));

    try map.put("HOME", " \t");
    try std.testing.expectError(error.EmptyEnvironmentVariable, required(rt, "HOME"));

    try map.put("HOME", " /home/me\n");
    const home = try required(rt, "HOME");
    defer std.testing.allocator.free(home);
    try std.testing.expectEqualStrings("/home/me", home);
}

test "envOrDup copies fallback only when the env var is missing" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("PRESENT", "value");

    const rt = testRuntime(&map);
    const present = try envOrDup(rt, "PRESENT", "fallback");
    defer std.testing.allocator.free(present);
    try std.testing.expectEqualStrings("value", present);

    const fallback = try envOrDup(rt, "MISSING", "fallback");
    defer std.testing.allocator.free(fallback);
    try std.testing.expectEqualStrings("fallback", fallback);
}

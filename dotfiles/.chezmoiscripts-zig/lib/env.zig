const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Context = struct {
    home_dir: []u8,
    source_dir: []u8,
    source_file: []u8,
    os: []u8,

    /// Frees all strings owned by this context.
    pub fn deinit(self: Context, allocator: Allocator) void {
        allocator.free(self.home_dir);
        allocator.free(self.source_dir);
        allocator.free(self.source_file);
        allocator.free(self.os);
    }
};

fn value(rt: anytype, name: []const u8) ![]u8 {
    const result = rt.env.get(name) orelse return error.EnvironmentVariableMissing;
    if (result.len == 0) return error.EmptyEnvironmentVariable;
    return try rt.allocator.dupe(u8, result);
}

/// Returns a copy of an environment variable or `null` when unset.
///
/// Caller owns returned memory.
pub fn envOrNull(rt: anytype, name: []const u8) !?[]u8 {
    const result = rt.env.get(name) orelse return null;
    return try rt.allocator.dupe(u8, result);
}

/// Reads the chezmoi runtime context from the environment.
///
/// Caller owns returned memory.
pub fn chezmoiContext(rt: anytype) !Context {
    const home = try value(rt, "HOME");
    errdefer rt.allocator.free(home);

    const source_dir = try value(rt, "CHEZMOI_SOURCE_DIR");
    errdefer rt.allocator.free(source_dir);

    const source_file = try envOrDup(rt, "CHEZMOI_SOURCE_FILE", "");
    errdefer rt.allocator.free(source_file);

    const home_dir = try envOrDup(rt, "CHEZMOI_HOME_DIR", home);
    errdefer rt.allocator.free(home_dir);

    const os = if (try envOrNull(rt, "CHEZMOI_OS")) |env_os|
        env_os
    else
        try rt.allocator.dupe(u8, switch (@import("builtin").os.tag) {
            .macos => "darwin",
            .linux => "linux",
            .windows => "windows",
            else => @tagName(@import("builtin").os.tag),
        });

    rt.allocator.free(home);
    return .{
        .home_dir = home_dir,
        .source_dir = source_dir,
        .source_file = source_file,
        .os = os,
    };
}

fn envOrDup(rt: anytype, name: []const u8, fallback: []const u8) ![]u8 {
    return if (try envOrNull(rt, name)) |env_value| env_value else try rt.allocator.dupe(u8, fallback);
}

const TestRuntime = struct {
    allocator: Allocator,
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

test "chezmoiContext reads required environment and defaults optional values" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("HOME", "/home/me");
    try map.put("CHEZMOI_SOURCE_DIR", "/src/dotfiles");

    const rt = testRuntime(&map);
    const context = try chezmoiContext(rt);
    defer context.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("/home/me", context.home_dir);
    try std.testing.expectEqualStrings("/src/dotfiles", context.source_dir);
    try std.testing.expectEqualStrings("", context.source_file);
    try std.testing.expect(context.os.len > 0);
}

test "chezmoiContext honors optional environment overrides" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("HOME", "/home/me");
    try map.put("CHEZMOI_SOURCE_DIR", "/src/dotfiles");
    try map.put("CHEZMOI_SOURCE_FILE", "file.tmpl");
    try map.put("CHEZMOI_HOME_DIR", "/target-home");
    try map.put("CHEZMOI_OS", "test-os");

    const rt = testRuntime(&map);
    const context = try chezmoiContext(rt);
    defer context.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("/target-home", context.home_dir);
    try std.testing.expectEqualStrings("file.tmpl", context.source_file);
    try std.testing.expectEqualStrings("test-os", context.os);
}

test "chezmoiContext rejects missing or empty required values" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();

    const rt = testRuntime(&map);
    try std.testing.expectError(error.EnvironmentVariableMissing, chezmoiContext(rt));

    try map.put("HOME", "");
    try std.testing.expectError(error.EmptyEnvironmentVariable, chezmoiContext(rt));
}

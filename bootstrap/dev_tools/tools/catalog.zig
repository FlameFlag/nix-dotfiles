const std = @import("std");
const bootstrap = @import("bootstrap");

const catalog_data = @import("catalog_data/root.zig");

const Context = bootstrap.Context;

pub const Catalog = bootstrap.manifest.Catalog;

pub fn load(ctx: *Context) !Catalog {
    const result: Catalog = .{ .tools = &catalog_data.tools };
    try bootstrap.manifest.validate(ctx, result);
    return result;
}

fn testingContext(env: *std.process.Environ.Map) Context {
    return .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = env,
        .home = "",
        .bin_dir = "",
        .opt_dir = "",
    };
}

test "static catalog validates" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);
    var loaded = try load(&ctx);
    defer loaded.deinit(&ctx);
    try std.testing.expectEqual(@as(usize, 16), loaded.tools.len);
}

test "static catalog tool order is stable" {
    const expected = [_][]const u8{
        "chezmoi",
        "uv",
        "zig",
        "rustup",
        "zls",
        "ziglint",
        "node",
        "bun",
        "vscode",
        "yt-dlp",
        "yt-dlp-script",
        "ruff",
        "ty",
        "gh-hide-comment",
        "zellij-theme-tools",
        "lenovo-con-mode",
    };

    try std.testing.expectEqual(expected.len, catalog_data.tools.len);
    for (expected, catalog_data.tools) |name, tool| {
        try std.testing.expectEqualStrings(name, tool.name);
    }
}

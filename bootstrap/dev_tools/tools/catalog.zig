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
    try std.testing.expect(loaded.tools.len > 0);
}

test "static catalog tool names are unique" {
    for (catalog_data.tools, 0..) |tool, index| {
        try std.testing.expect(tool.name.len > 0);
        for (catalog_data.tools[0..index]) |previous| {
            try std.testing.expect(!std.mem.eql(u8, previous.name, tool.name));
        }
    }
}

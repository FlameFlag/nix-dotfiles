const std = @import("std");
const bootstrap = @import("bootstrap");

const Context = bootstrap.Context;

pub const Catalog = bootstrap.manifest.Catalog;

pub fn load(ctx: *Context) !Catalog {
    const manifest_path = try catalogPath(ctx);
    defer ctx.allocator.free(manifest_path);
    return bootstrap.manifest.loadPath(ctx, manifest_path);
}

fn catalogPath(ctx: *const Context) ![]u8 {
    if (ctx.env.get("BOOTSTRAP_TOOLS_JSON")) |env_path| return ctx.allocator.dupe(u8, env_path);

    const cwd = try std.process.currentPathAlloc(ctx.io, ctx.allocator);
    defer ctx.allocator.free(cwd);
    return std.fs.path.join(ctx.allocator, &.{ cwd, "bootstrap", "dev_tools", "tools", "tools.json" });
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

test "catalog path honors BOOTSTRAP_TOOLS_JSON" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("BOOTSTRAP_TOOLS_JSON", "/tmp/custom-tools.json");

    const ctx = testingContext(&env);
    const resolved = try catalogPath(&ctx);
    defer ctx.allocator.free(resolved);

    try std.testing.expectEqualStrings("/tmp/custom-tools.json", resolved);
}

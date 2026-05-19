const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");

const Context = @import("context.zig").Context;
const manifest = @import("manifest.zig");
const packages = @import("packages.zig");
const rust = @import("rust.zig");

const proc = common.process;

pub const Classification = enum {
    missing,
    managed,
    external,
};

pub fn classifyBin(
    ctx: *Context,
    cwd: []const u8,
    tool: manifest.Tool,
    bin: []const u8,
    path: ?[]const u8,
    package_inventory: packages.Inventory,
) !Classification {
    const executable_path = path orelse return .missing;

    switch (tool.action) {
        .toolchain => |toolchain| {
            const bin_dir = try rust.toolchainBinDir(ctx, toolchain);
            defer ctx.allocator.free(bin_dir);
            return if (try pathIsUnder(ctx, cwd, executable_path, bin_dir)) .managed else .external;
        },
        else => {},
    }

    const in_bin_dir = try pathIsUnder(ctx, cwd, executable_path, ctx.bin_dir);
    if (!in_bin_dir) return .external;

    if (tool.usesBuildInstaller() or tool.usesScriptInstaller()) return .managed;

    switch (tool.action) {
        .package => |package_spec| {
            return if (package_inventory.binIsManaged(package_spec, bin, executable_path)) .managed else .external;
        },
        else => {},
    }

    if (builtin.os.tag == .windows) return .managed;

    const root = try tool.managedRoot(ctx) orelse return .external;
    defer ctx.allocator.free(root);

    const target = try symlinkTarget(ctx, executable_path) orelse return .external;
    defer ctx.allocator.free(target);

    return if (try pathIsUnder(ctx, cwd, target, root)) .managed else .external;
}

pub fn classifyBinOnPath(
    ctx: *Context,
    cwd: []const u8,
    tool: manifest.Tool,
    bin: []const u8,
    package_inventory: packages.Inventory,
) !Classification {
    const path = try proc.pathOf(ctx, bin);
    defer if (path) |value| ctx.allocator.free(value);
    return classifyBin(ctx, cwd, tool, bin, path, package_inventory);
}

pub fn localExecutableInBinDir(ctx: *Context, bin: []const u8) !bool {
    const path = try std.fs.path.join(ctx.allocator, &.{ ctx.bin_dir, bin });
    defer ctx.allocator.free(path);
    std.Io.Dir.cwd().access(ctx.io, path, .{ .execute = true }) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return false,
        else => return err,
    };
    return true;
}

pub fn pathIsUnder(ctx: *Context, cwd: []const u8, path: []const u8, root: []const u8) !bool {
    const relative = try std.fs.path.relative(ctx.allocator, cwd, ctx.env, root, path);
    defer ctx.allocator.free(relative);

    if (relative.len == 0) return true;
    if (std.fs.path.isAbsolute(relative)) return false;
    if (std.mem.eql(u8, relative, "..")) return false;
    return !std.mem.startsWith(u8, relative, ".." ++ std.fs.path.sep_str);
}

fn symlinkTarget(ctx: *Context, path: []const u8) !?[]u8 {
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = readLink(ctx, path, &buf) catch |err| switch (err) {
        error.FileNotFound, error.NotLink => return null,
        else => return err,
    };
    const raw = buf[0..len];
    if (std.fs.path.isAbsolute(raw)) return @as(?[]u8, try std.fs.path.resolve(ctx.allocator, &.{raw}));

    const dir = std.fs.path.dirname(path) orelse ".";
    return @as(?[]u8, try std.fs.path.resolve(ctx.allocator, &.{ dir, raw }));
}

fn readLink(ctx: *Context, path: []const u8, buf: []u8) !usize {
    return if (std.fs.path.isAbsolute(path))
        std.Io.Dir.readLinkAbsolute(ctx.io, path, buf)
    else
        std.Io.Dir.cwd().readLink(ctx.io, path, buf);
}

fn testingContext(env: *std.process.Environ.Map, bin_dir: []const u8, opt_dir: []const u8) Context {
    return .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = env,
        .home = "",
        .bin_dir = bin_dir,
        .opt_dir = opt_dir,
    };
}

test "path prefix checks directory boundaries" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env, "", "");

    const cwd = try std.process.currentPathAlloc(ctx.io, ctx.allocator);
    defer ctx.allocator.free(cwd);

    try std.testing.expect(try pathIsUnder(&ctx, cwd, "/tmp/root/bin/tool", "/tmp/root/bin"));
    try std.testing.expect(try pathIsUnder(&ctx, cwd, "/tmp/root/bin", "/tmp/root/bin"));
    try std.testing.expect(!try pathIsUnder(&ctx, cwd, "/tmp/root/binary/tool", "/tmp/root/bin"));
    try std.testing.expect(!try pathIsUnder(&ctx, cwd, "/tmp/root", "/tmp/root/bin"));
}

test "archive bins must be managed rather than merely present" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env, "/home/me/.local/bin", "/home/me/.local/opt");
    const tool: manifest.Tool = .{
        .name = "demo",
        .bins = &.{.{ .name = "demo", .version_argv = &.{"demo"} }},
        .action = .{ .archive = .{ .platforms = &.{} } },
    };
    const cwd = try std.process.currentPathAlloc(ctx.io, ctx.allocator);
    defer ctx.allocator.free(cwd);

    try std.testing.expectEqual(
        .external,
        try classifyBin(&ctx, cwd, tool, "demo", "/usr/bin/demo", .empty()),
    );
}

test "missing bins classify distinctly" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env, "/home/me/.local/bin", "/home/me/.local/opt");
    const tool: manifest.Tool = .{
        .name = "demo",
        .bins = &.{.{ .name = "demo", .version_argv = &.{"demo"} }},
        .action = .{ .archive = .{ .platforms = &.{} } },
    };
    const cwd = try std.process.currentPathAlloc(ctx.io, ctx.allocator);
    defer ctx.allocator.free(cwd);

    try std.testing.expectEqual(.missing, try classifyBin(&ctx, cwd, tool, "demo", null, .empty()));
}

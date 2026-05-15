const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");
const Context = @import("context.zig").Context;

pub const Link = struct {
    name: []const u8,
    path: []const u8,
};

pub fn installDirPath(ctx: *Context, tool: []const u8, version: []const u8) ![]u8 {
    return std.fs.path.join(ctx.allocator, &.{ ctx.opt_dir, tool, version });
}

pub fn linkMany(ctx: *Context, tool: []const u8, install_dir: []const u8, entries: []const Link) !void {
    for (entries) |entry| {
        const target = try std.fs.path.join(ctx.allocator, &.{ install_dir, entry.path });
        defer ctx.allocator.free(target);
        try managed(ctx, tool, target, entry.name);
    }
}

pub fn managed(ctx: *Context, tool: []const u8, target: []const u8, bin: []const u8) !void {
    const link_path = try std.fs.path.join(ctx.allocator, &.{ ctx.bin_dir, bin });
    defer ctx.allocator.free(link_path);

    if (builtin.os.tag == .windows) {
        try ensureExecutable(ctx, target);
        try std.Io.Dir.copyFileAbsolute(target, link_path, ctx.io, .{ .replace = true });
        return;
    }

    var replace_existing = false;
    var old_buf: [4096]u8 = undefined;
    if (std.Io.Dir.cwd().readLink(ctx.io, link_path, &old_buf)) |old_len| {
        const old = old_buf[0..old_len];
        if (!try isManagedTarget(ctx, tool, old)) return error.NonManagedLinkExists;
        replace_existing = true;
    } else |err| switch (err) {
        error.FileNotFound => {},
        error.NotLink => return error.NonManagedLinkExists,
        else => return err,
    }

    try ensureExecutable(ctx, target);
    if (replace_existing) try std.Io.Dir.cwd().deleteFile(ctx.io, link_path);
    try std.Io.Dir.symLinkAbsolute(ctx.io, target, link_path, .{});
}

fn ensureExecutable(ctx: *Context, path: []const u8) !void {
    std.Io.Dir.cwd().access(ctx.io, path, .{ .execute = true }) catch |err| switch (err) {
        error.AccessDenied => {
            try std.Io.Dir.cwd().setFilePermissions(ctx.io, path, .executable_file, .{});
            try std.Io.Dir.cwd().access(ctx.io, path, .{ .execute = true });
        },
        else => return err,
    };
}

fn isManagedTarget(ctx: *Context, tool: []const u8, path: []const u8) !bool {
    if (!std.fs.path.isAbsolute(path)) return false;

    const prefix = try std.fs.path.join(ctx.allocator, &.{ ctx.opt_dir, tool });
    defer ctx.allocator.free(prefix);
    const normalized_prefix = try std.fs.path.resolve(ctx.allocator, &.{prefix});
    defer ctx.allocator.free(normalized_prefix);
    const normalized_path = try std.fs.path.resolve(ctx.allocator, &.{path});
    defer ctx.allocator.free(normalized_path);

    if (!std.mem.startsWith(u8, normalized_path, normalized_prefix)) return false;
    return normalized_path.len == normalized_prefix.len or std.fs.path.isSep(normalized_path[normalized_prefix.len]);
}

fn testingContext(env: *std.process.Environ.Map, home: []const u8, bin_dir: []const u8, opt_dir: []const u8) Context {
    return .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = env,
        .home = home,
        .bin_dir = bin_dir,
        .opt_dir = opt_dir,
    };
}

fn tmpPath(allocator: std.mem.Allocator, tmp: std.testing.TmpDir, parts: []const []const u8) ![]u8 {
    return common.testing.tmpPath(allocator, tmp, parts);
}

fn createExecutable(ctx: *Context, path: []const u8) !void {
    try common.fs.writeExecutableFile(ctx.io, path, "");
}

fn expectLinkTarget(ctx: *Context, link_path: []const u8, expected: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const len = try std.Io.Dir.cwd().readLink(ctx.io, link_path, &buf);
    try std.testing.expectEqualStrings(expected, buf[0..len]);
}

test "managed links reject sibling tool prefixes" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const home = try tmpPath(std.testing.allocator, tmp, &.{});
    defer std.testing.allocator.free(home);
    const bin_dir = try tmpPath(std.testing.allocator, tmp, &.{"bin"});
    defer std.testing.allocator.free(bin_dir);
    const opt_dir = try tmpPath(std.testing.allocator, tmp, &.{"opt"});
    defer std.testing.allocator.free(opt_dir);
    var ctx = testingContext(&env, home, bin_dir, opt_dir);

    try std.Io.Dir.cwd().createDirPath(ctx.io, bin_dir);
    try std.Io.Dir.cwd().createDirPath(ctx.io, opt_dir);

    const old_target = try tmpPath(ctx.allocator, tmp, &.{ "opt", "toolbox", "1", "tool" });
    defer ctx.allocator.free(old_target);
    const new_target = try tmpPath(ctx.allocator, tmp, &.{ "opt", "tool", "1", "tool" });
    defer ctx.allocator.free(new_target);
    const link_path = try tmpPath(ctx.allocator, tmp, &.{ "bin", "tool" });
    defer ctx.allocator.free(link_path);

    try createExecutable(&ctx, old_target);
    try createExecutable(&ctx, new_target);
    try std.Io.Dir.symLinkAbsolute(ctx.io, old_target, link_path, .{});

    try std.testing.expectError(error.NonManagedLinkExists, managed(&ctx, "tool", new_target, "tool"));
    try expectLinkTarget(&ctx, link_path, old_target);
}

test "managed links validate new target before replacing old link" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const home = try tmpPath(std.testing.allocator, tmp, &.{});
    defer std.testing.allocator.free(home);
    const bin_dir = try tmpPath(std.testing.allocator, tmp, &.{"bin"});
    defer std.testing.allocator.free(bin_dir);
    const opt_dir = try tmpPath(std.testing.allocator, tmp, &.{"opt"});
    defer std.testing.allocator.free(opt_dir);
    var ctx = testingContext(&env, home, bin_dir, opt_dir);

    try std.Io.Dir.cwd().createDirPath(ctx.io, bin_dir);
    try std.Io.Dir.cwd().createDirPath(ctx.io, opt_dir);

    const old_target = try tmpPath(ctx.allocator, tmp, &.{ "opt", "tool", "old", "tool" });
    defer ctx.allocator.free(old_target);
    const missing_target = try tmpPath(ctx.allocator, tmp, &.{ "opt", "tool", "new", "tool" });
    defer ctx.allocator.free(missing_target);
    const link_path = try tmpPath(ctx.allocator, tmp, &.{ "bin", "tool" });
    defer ctx.allocator.free(link_path);

    try createExecutable(&ctx, old_target);
    try std.Io.Dir.symLinkAbsolute(ctx.io, old_target, link_path, .{});

    try std.testing.expectError(error.FileNotFound, managed(&ctx, "tool", missing_target, "tool"));
    try expectLinkTarget(&ctx, link_path, old_target);
}

test "managed links reject escaped managed prefixes" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const home = try tmpPath(std.testing.allocator, tmp, &.{});
    defer std.testing.allocator.free(home);
    const bin_dir = try tmpPath(std.testing.allocator, tmp, &.{"bin"});
    defer std.testing.allocator.free(bin_dir);
    const opt_dir = try tmpPath(std.testing.allocator, tmp, &.{"opt"});
    defer std.testing.allocator.free(opt_dir);
    var ctx = testingContext(&env, home, bin_dir, opt_dir);

    try std.Io.Dir.cwd().createDirPath(ctx.io, bin_dir);
    try std.Io.Dir.cwd().createDirPath(ctx.io, opt_dir);

    const real_old_target = try tmpPath(ctx.allocator, tmp, &.{ "opt", "toolbox", "1", "tool" });
    defer ctx.allocator.free(real_old_target);
    const escaped_old_target = try std.fs.path.join(ctx.allocator, &.{ opt_dir, "tool", "..", "toolbox", "1", "tool" });
    defer ctx.allocator.free(escaped_old_target);
    const new_target = try tmpPath(ctx.allocator, tmp, &.{ "opt", "tool", "1", "tool" });
    defer ctx.allocator.free(new_target);
    const link_path = try tmpPath(ctx.allocator, tmp, &.{ "bin", "tool" });
    defer ctx.allocator.free(link_path);

    try createExecutable(&ctx, real_old_target);
    try createExecutable(&ctx, new_target);
    try std.Io.Dir.symLinkAbsolute(ctx.io, escaped_old_target, link_path, .{});

    try std.testing.expectError(error.NonManagedLinkExists, managed(&ctx, "tool", new_target, "tool"));
    const expected_old_target = if (builtin.os.tag == .windows) real_old_target else escaped_old_target;
    try expectLinkTarget(&ctx, link_path, expected_old_target);
}

test "managed links replace links inside the managed tool root" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const home = try tmpPath(std.testing.allocator, tmp, &.{});
    defer std.testing.allocator.free(home);
    const bin_dir = try tmpPath(std.testing.allocator, tmp, &.{"bin"});
    defer std.testing.allocator.free(bin_dir);
    const opt_dir = try tmpPath(std.testing.allocator, tmp, &.{"opt"});
    defer std.testing.allocator.free(opt_dir);
    var ctx = testingContext(&env, home, bin_dir, opt_dir);

    try std.Io.Dir.cwd().createDirPath(ctx.io, bin_dir);
    try std.Io.Dir.cwd().createDirPath(ctx.io, opt_dir);

    const old_target = try tmpPath(ctx.allocator, tmp, &.{ "opt", "tool", "old", "tool" });
    defer ctx.allocator.free(old_target);
    const new_target = try tmpPath(ctx.allocator, tmp, &.{ "opt", "tool", "new", "tool" });
    defer ctx.allocator.free(new_target);
    const link_path = try tmpPath(ctx.allocator, tmp, &.{ "bin", "tool" });
    defer ctx.allocator.free(link_path);

    try createExecutable(&ctx, old_target);
    try createExecutable(&ctx, new_target);
    try std.Io.Dir.symLinkAbsolute(ctx.io, old_target, link_path, .{});

    try managed(&ctx, "tool", new_target, "tool");
    try expectLinkTarget(&ctx, link_path, new_target);
}

test "managed links make zip-extracted targets executable" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const home = try tmpPath(std.testing.allocator, tmp, &.{});
    defer std.testing.allocator.free(home);
    const bin_dir = try tmpPath(std.testing.allocator, tmp, &.{"bin"});
    defer std.testing.allocator.free(bin_dir);
    const opt_dir = try tmpPath(std.testing.allocator, tmp, &.{"opt"});
    defer std.testing.allocator.free(opt_dir);
    var ctx = testingContext(&env, home, bin_dir, opt_dir);

    try std.Io.Dir.cwd().createDirPath(ctx.io, bin_dir);
    const target = try tmpPath(ctx.allocator, tmp, &.{ "opt", "tool", "1", "tool" });
    defer ctx.allocator.free(target);
    const link_path = try tmpPath(ctx.allocator, tmp, &.{ "bin", "tool" });
    defer ctx.allocator.free(link_path);

    if (std.fs.path.dirname(target)) |dir| {
        try std.Io.Dir.cwd().createDirPath(ctx.io, dir);
    }
    var file = try std.Io.Dir.cwd().createFile(ctx.io, target, .{});
    file.close(ctx.io);

    try managed(&ctx, "tool", target, "tool");
    try expectLinkTarget(&ctx, link_path, target);
    try std.Io.Dir.cwd().access(ctx.io, target, .{ .execute = true });
}

const std = @import("std");
const script = @import("chezmoi");

const yazi_plugins_repo = "https://github.com/yazi-rs/plugins.git";
const official_plugins = [_][]const u8{
    "diff",
    "full-border",
    "smart-enter",
    "smart-paste",
    "git",
};
const external_plugins = [_]struct { name: []const u8, repo: []const u8 }{
    .{
        .name = "system-clipboard",
        .repo = "https://github.com/orhnk/system-clipboard.yazi.git",
    },
    .{ .name = "starship", .repo = "https://github.com/Rolv-Apneseth/starship.yazi.git" },
};

pub fn main(init: std.process.Init) !void {
    try script.mainWith(run, init);
}

fn run(rt: *script.Runtime) !void {
    if (!try script.hasBin(rt, "git")) return error.GitNotFound;

    const context = try script.chezmoiContext(rt);
    defer context.deinit(rt.allocator);

    const plugins_dir = try std.fs.path.join(rt.allocator, &.{ context.home_dir, ".config/yazi/plugins" });
    defer rt.allocator.free(plugins_dir);
    const flavors_dir = try std.fs.path.join(rt.allocator, &.{ context.home_dir, ".config/yazi/flavors" });
    defer rt.allocator.free(flavors_dir);
    try std.Io.Dir.cwd().createDirPath(rt.io, plugins_dir);
    try std.Io.Dir.cwd().createDirPath(rt.io, flavors_dir);

    const temp_dir = try script.tempDir(rt);
    defer {
        deleteTreeIfExists(rt, temp_dir) catch |err| {
            warnTempDirCleanupFailed(rt, temp_dir, err);
        };
        rt.allocator.free(temp_dir);
    }

    try rt.stderr.print("info: Downloading plugins repository...\n", .{});
    try rt.stderr.flush();
    try script.command(rt, &.{
        "git",
        "clone",
        "--depth",
        "1",
        "--single-branch",
        "--no-tags",
        "--quiet",
        yazi_plugins_repo,
        temp_dir,
    });
    const temp_git = try std.fs.path.join(rt.allocator, &.{ temp_dir, ".git" });
    defer rt.allocator.free(temp_git);
    try std.Io.Dir.cwd().deleteTree(rt.io, temp_git);

    for (official_plugins) |plugin| {
        const src_name = try std.fmt.allocPrint(rt.allocator, "{s}.yazi", .{plugin});
        defer rt.allocator.free(src_name);
        const src = try std.fs.path.join(rt.allocator, &.{ temp_dir, src_name });
        defer rt.allocator.free(src);
        try installPluginDir(rt, plugin, src, plugins_dir);
    }

    for (external_plugins) |plugin| {
        const plugin_name = try std.fmt.allocPrint(rt.allocator, "{s}.yazi", .{plugin.name});
        defer rt.allocator.free(plugin_name);
        const plugin_dir = try std.fs.path.join(rt.allocator, &.{ plugins_dir, plugin_name });
        defer rt.allocator.free(plugin_dir);
        try deleteTreeIfExists(rt, plugin_dir);
        try rt.stderr.print("info: Installing plugin {s}...\n", .{plugin.name});
        try rt.stderr.flush();
        try script.command(rt, &.{
            "git",
            "clone",
            "--depth",
            "1",
            "--single-branch",
            "--no-tags",
            "--quiet",
            plugin.repo,
            plugin_dir,
        });
        const git_dir = try std.fs.path.join(rt.allocator, &.{ plugin_dir, ".git" });
        defer rt.allocator.free(git_dir);
        try std.Io.Dir.cwd().deleteTree(rt.io, git_dir);
    }

    try rt.stderr.print("success: Yazi plugins installed\n", .{});
    try rt.stderr.flush();
}

fn deleteTreeIfExists(rt: *script.Runtime, path: []const u8) !void {
    try std.Io.Dir.cwd().deleteTree(rt.io, path);
}

fn installPluginDir(
    rt: *script.Runtime,
    plugin: []const u8,
    src: []const u8,
    plugins_dir: []const u8,
) !void {
    const plugin_name = try std.fmt.allocPrint(rt.allocator, "{s}.yazi", .{plugin});
    defer rt.allocator.free(plugin_name);
    const dst = try std.fs.path.join(rt.allocator, &.{ plugins_dir, plugin_name });
    defer rt.allocator.free(dst);
    try deleteTreeIfExists(rt, dst);
    try rt.stderr.print("info: Installing plugin {s}...\n", .{plugin});
    try rt.stderr.flush();
    try script.command(rt, &.{ "cp", "-R", src, dst });
}

fn warnTempDirCleanupFailed(rt: *script.Runtime, temp_dir: []const u8, err: anyerror) void {
    rt.stderr.print(
        "warn: failed to remove temporary directory {s}: {s}\n",
        .{ temp_dir, @errorName(err) },
    ) catch |write_err| warnWriteFailed(write_err);
    rt.stderr.flush() catch |write_err| warnWriteFailed(write_err);
}

fn warnWriteFailed(err: anyerror) void {
    std.debug.print("warn: failed to write warning: {s}\n", .{@errorName(err)});
}

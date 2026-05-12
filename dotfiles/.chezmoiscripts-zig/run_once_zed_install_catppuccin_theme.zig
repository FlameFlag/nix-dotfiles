const std = @import("std");
const script = @import("script.zig");

const Release = struct { tag_name: []const u8 };

pub fn main(init: std.process.Init) !void {
    try script.mainWith(init, run);
}

fn run(rt: *script.Runtime) !void {
    var http = script.http.Client.init(rt);
    defer http.deinit();

    const theme_tag = try fetchLatestTag(rt, &http, "catppuccin/zed");
    defer rt.allocator.free(theme_tag);
    const icons_tag = try fetchLatestTag(rt, &http, "catppuccin/zed-icons");
    defer rt.allocator.free(icons_tag);

    try installTheme(rt, &http, theme_tag);
    try installIcons(rt, &http, icons_tag);
}

fn fetchLatestTag(rt: *script.Runtime, http: *script.http.Client, repository: []const u8) ![]u8 {
    try rt.stderr.print("info: Fetching latest {s} release...\n", .{repository});
    try rt.stderr.flush();
    const url = try std.fmt.allocPrint(rt.allocator, "https://api.github.com/repos/{s}/releases/latest", .{repository});
    defer rt.allocator.free(url);

    const body = try http.getText(url, .github);
    defer rt.allocator.free(body);

    var parsed = try std.json.parseFromSlice(Release, rt.allocator, body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    return try rt.allocator.dupe(u8, parsed.value.tag_name);
}

fn installTheme(rt: *script.Runtime, http: *script.http.Client, latest_tag: []const u8) !void {
    const context = try script.chezmoiContext(rt);
    defer context.deinit(rt.allocator);

    const themes_dir = try std.fs.path.join(rt.allocator, &.{ context.home_dir, ".config/zed/themes" });
    defer rt.allocator.free(themes_dir);
    try std.Io.Dir.cwd().createDirPath(rt.io, themes_dir);

    const theme_path = try std.fs.path.join(rt.allocator, &.{ themes_dir, "catppuccin-pink.json" });
    defer rt.allocator.free(theme_path);
    const url = try std.fmt.allocPrint(
        rt.allocator,
        "https://github.com/catppuccin/zed/releases/download/{s}/catppuccin-pink.json",
        .{latest_tag},
    );
    defer rt.allocator.free(url);

    try rt.stderr.print("info: Downloading catppuccin-pink.json...\n", .{});
    try rt.stderr.flush();
    const theme = try http.getText(url, .none);
    defer rt.allocator.free(theme);
    if (try script.writeTextIfChanged(rt, theme_path, theme)) {
        try rt.stderr.print("success: Theme installed to {s}\n", .{theme_path});
        try rt.stderr.flush();
    }
}

fn deleteTreeIfExists(rt: *script.Runtime, path: []const u8) !void {
    try std.Io.Dir.cwd().deleteTree(rt.io, path);
}

fn installIcons(rt: *script.Runtime, http: *script.http.Client, latest_tag: []const u8) !void {
    const context = try script.chezmoiContext(rt);
    defer context.deinit(rt.allocator);

    const zed_config_dir = try std.fs.path.join(rt.allocator, &.{ context.home_dir, ".config/zed" });
    defer rt.allocator.free(zed_config_dir);
    const icon_themes_dir = try std.fs.path.join(rt.allocator, &.{ zed_config_dir, "icon_themes" });
    defer rt.allocator.free(icon_themes_dir);
    const icons_dir = try std.fs.path.join(rt.allocator, &.{ zed_config_dir, "icons" });
    defer rt.allocator.free(icons_dir);

    const temp_dir = try script.tempDir(rt);
    defer {
        deleteTreeIfExists(rt, temp_dir) catch |err| {
            rt.stderr.print("warn: failed to remove temporary directory {s}: {s}\n", .{ temp_dir, @errorName(err) }) catch {};
            rt.stderr.flush() catch {};
        };
        rt.allocator.free(temp_dir);
    }

    const archive_path = try std.fs.path.join(rt.allocator, &.{ temp_dir, "zed-icons.tar.gz" });
    defer rt.allocator.free(archive_path);
    const url = try std.fmt.allocPrint(rt.allocator, "https://codeload.github.com/catppuccin/zed-icons/tar.gz/{s}", .{latest_tag});
    defer rt.allocator.free(url);

    try rt.stderr.print("info: Downloading Catppuccin Zed icon theme...\n", .{});
    try rt.stderr.flush();
    try http.downloadFile(url, archive_path);
    try script.command(rt, &.{ "tar", "-xzf", archive_path, "-C", temp_dir, "--strip-components=1" });

    try std.Io.Dir.cwd().createDirPath(rt.io, icon_themes_dir);
    try deleteTreeIfExists(rt, icons_dir);

    const src_icon_theme = try std.fs.path.join(rt.allocator, &.{ temp_dir, "icon_themes/catppuccin-icons.json" });
    defer rt.allocator.free(src_icon_theme);
    const dst_icon_theme = try std.fs.path.join(rt.allocator, &.{ icon_themes_dir, "catppuccin-icons.json" });
    defer rt.allocator.free(dst_icon_theme);
    try std.Io.Dir.cwd().copyFile(src_icon_theme, .cwd(), dst_icon_theme, rt.io, .{ .replace = true, .make_path = true });

    const src_icons = try std.fs.path.join(rt.allocator, &.{ temp_dir, "icons" });
    defer rt.allocator.free(src_icons);
    try script.command(rt, &.{ "cp", "-R", src_icons, icons_dir });
    try rt.stderr.print("success: Icon theme installed to {s}\n", .{zed_config_dir});
    try rt.stderr.flush();
}

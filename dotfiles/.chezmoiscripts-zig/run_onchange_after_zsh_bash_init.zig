const std = @import("std");
const script = @import("script.zig");

const Shell = enum { zsh, bash };
const InitCommand = struct { bin: []const u8, dir: []const u8, suffix: []const []const u8 = &.{} };
const CompletionCommand = struct {
    bin: []const u8,
    name: []const u8,
    argv0: []const u8,
    before_shell: []const []const u8,
    after_shell: []const []const u8 = &.{},
};

const init_commands = [_]InitCommand{
    .{ .bin = "starship", .dir = "starship" },
    .{ .bin = "zoxide", .dir = "zoxide" },
    .{ .bin = "atuin", .dir = "atuin", .suffix = &.{"--disable-up-arrow"} },
    .{ .bin = "tv", .dir = "television" },
};

const completion_commands = [_]CompletionCommand{
    .{ .bin = "chezmoi", .name = "chezmoi", .argv0 = "chezmoi", .before_shell = &.{"completion"} },
    .{ .bin = "jj", .name = "jj", .argv0 = "jj", .before_shell = &.{ "util", "completion" } },
    .{ .bin = "yazi", .name = "yazi", .argv0 = "yazi", .before_shell = &.{"--completions"} },
    .{ .bin = "zellij", .name = "zellij", .argv0 = "zellij", .before_shell = &.{ "setup", "--generate-completion" } },
    .{ .bin = "starship", .name = "starship", .argv0 = "starship", .before_shell = &.{"completions"} },
    .{ .bin = "deno", .name = "deno", .argv0 = "deno", .before_shell = &.{"completions"} },
    .{ .bin = "nh", .name = "nh", .argv0 = "nh", .before_shell = &.{"completions"} },
    .{ .bin = "delta", .name = "delta", .argv0 = "delta", .before_shell = &.{"--generate-completion"} },
    .{ .bin = "tv", .name = "tv", .argv0 = "tv", .before_shell = &.{"completion"} },
    .{ .bin = "rustup", .name = "rustup", .argv0 = "rustup", .before_shell = &.{"completions"} },
    .{ .bin = "rustup", .name = "cargo", .argv0 = "rustup", .before_shell = &.{"completions"}, .after_shell = &.{"cargo"} },
};

pub fn main(init: std.process.Init) !void {
    try script.mainWith(init, run);
}

fn run(rt: *script.Runtime) !void {
    const context = try script.chezmoiContext(rt);
    defer context.deinit(rt.allocator);

    const dirs = [_][]const u8{
        ".cache/starship",
        ".cache/zoxide",
        ".cache/atuin",
        ".cache/television",
        ".cache/zsh/completions",
        ".cache/bash/completions",
    };
    for (dirs) |dir| {
        const path = try std.fs.path.join(rt.allocator, &.{ context.home_dir, dir });
        defer rt.allocator.free(path);
        try std.Io.Dir.cwd().createDirPath(rt.io, path);
    }

    for ([_]Shell{ .zsh, .bash }) |shell| {
        try writeInitFiles(rt, context.home_dir, shell);
        try writeCompletionFiles(rt, context.home_dir, shell);
    }
}

fn writeInitFiles(rt: *script.Runtime, home_dir: []const u8, shell: Shell) !void {
    for (init_commands) |item| {
        if (!try script.hasBin(rt, item.bin)) continue;
        const out = try std.fmt.allocPrint(rt.allocator, "init.{s}", .{@tagName(shell)});
        defer rt.allocator.free(out);
        const path = try std.fs.path.join(rt.allocator, &.{ home_dir, ".cache", item.dir, out });
        defer rt.allocator.free(path);

        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(rt.allocator);
        try argv.appendSlice(rt.allocator, &.{ item.bin, "init", @tagName(shell) });
        try argv.appendSlice(rt.allocator, item.suffix);
        _ = try script.writeCommandTextIfAvailable(rt, item.bin, path, argv.items);
    }
}

fn writeCompletionFiles(rt: *script.Runtime, home_dir: []const u8, shell: Shell) !void {
    const shell_name = @tagName(shell);
    const outdir = try std.fs.path.join(rt.allocator, &.{ home_dir, ".cache", shell_name, "completions" });
    defer rt.allocator.free(outdir);
    const prefix = if (shell == .zsh) "_" else "";

    if (try script.hasBin(rt, "atuin")) {
        var result = try script.commandQuiet(rt, &.{ "atuin", "gen-completions", "--shell", shell_name, "--out-dir", outdir });
        defer result.deinit(rt.allocator);
        if (result.exit_code != 0) try warnCommandFailed(rt, "atuin completions", result.stderr);
    }

    for (completion_commands) |item| {
        if (!try script.hasBin(rt, item.bin)) continue;
        const argv = try completionArgs(rt, item, shell);
        defer rt.allocator.free(argv);
        var result = try script.commandQuiet(rt, argv);
        defer result.deinit(rt.allocator);
        if (result.exit_code != 0) {
            try warnCommandFailed(rt, item.name, result.stderr);
            continue;
        }

        const filename = try std.fmt.allocPrint(rt.allocator, "{s}{s}", .{ prefix, item.name });
        defer rt.allocator.free(filename);
        const path = try std.fs.path.join(rt.allocator, &.{ outdir, filename });
        defer rt.allocator.free(path);
        _ = try script.writeTextIfChanged(rt, path, result.stdout);
    }
}

fn warnCommandFailed(rt: *script.Runtime, name: []const u8, stderr: []const u8) !void {
    const message = std.mem.trim(u8, stderr, " \t\r\n");
    if (message.len == 0) {
        try rt.stderr.print("warn: failed to generate {s} completions\n", .{name});
    } else {
        try rt.stderr.print("warn: failed to generate {s} completions: {s}\n", .{ name, message });
    }
    try rt.stderr.flush();
}

fn completionArgs(rt: *script.Runtime, item: CompletionCommand, shell: Shell) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    errdefer argv.deinit(rt.allocator);
    try argv.append(rt.allocator, item.argv0);
    try argv.appendSlice(rt.allocator, item.before_shell);
    try argv.append(rt.allocator, @tagName(shell));
    try argv.appendSlice(rt.allocator, item.after_shell);
    return try argv.toOwnedSlice(rt.allocator);
}

test "completionArgs places shell between command-specific arguments" {
    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    var stdout_buffer: [1]u8 = undefined;
    var stderr_buffer: [1]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buffer);
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);
    var rt: script.Runtime = .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = &env_map,
        .stdout = &stdout,
        .stderr = &stderr,
    };

    const argv = try completionArgs(&rt, .{
        .bin = "rustup",
        .name = "cargo",
        .argv0 = "rustup",
        .before_shell = &.{"completions"},
        .after_shell = &.{"cargo"},
    }, .zsh);
    defer std.testing.allocator.free(argv);

    try std.testing.expectEqualSlices([]const u8, &.{ "rustup", "completions", "zsh", "cargo" }, argv);
}

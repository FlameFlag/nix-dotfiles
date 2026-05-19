const std = @import("std");
const common = @import("common");

const command = @import("command.zig");
const runtime = @import("runtime.zig");
const theme = @import("theme.zig");
const zellij = @import("zellij.zig");

const config_file_limit = 64 * 1024 * 1024;
const trusted_line = "trust_level = \"trusted\"";

pub fn run(init: std.process.Init) !u8 {
    const rt: runtime.Runtime = .{
        .allocator = init.gpa,
        .io = init.io,
        .env = init.environ_map,
    };

    var pane_color_set = false;
    if (try zellij.isAvailable(rt)) {
        const selected = try theme.detect(rt);
        zellij.setPaneColor(rt, selected.colors);
        pane_color_set = true;
    }
    defer if (pane_color_set) zellij.resetPaneColor(rt);

    const overlay_home = try createTrustOverlay(rt);
    defer {
        common.fs.deleteTreeWarning(rt.io, "Codex trust overlay", overlay_home);
        rt.allocator.free(overlay_home);
    }

    var child_env = try init.environ_map.clone(rt.allocator);
    defer child_env.deinit();
    try child_env.put("CODEX_HOME", overlay_home);

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const argv_len = if (args.len == 0) 1 else args.len;
    const argv = try rt.allocator.alloc([]const u8, argv_len);
    defer rt.allocator.free(argv);
    const codex_bin = try codexBin(rt);
    defer rt.allocator.free(codex_bin);
    argv[0] = codex_bin;
    if (args.len > 1) @memcpy(argv[1..], args[1..]);

    return command.runInherit(rt, argv, &child_env);
}

fn codexBin(rt: anytype) ![]u8 {
    if (try common.process.pathOf(rt, "codex")) |path| return path;

    const home = rt.env.get("HOME") orelse return error.HomeMissing;
    const candidates = [_][]const u8{
        ".bun/bin/codex",
        ".npm/bin/codex",
        ".local/bin/codex",
    };
    for (candidates) |candidate| {
        const path = try std.fs.path.join(rt.allocator, &.{ home, candidate });
        errdefer rt.allocator.free(path);
        std.Io.Dir.cwd().access(rt.io, path, .{ .execute = true }) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => {
                rt.allocator.free(path);
                continue;
            },
            else => return err,
        };
        return path;
    }
    return error.FileNotFound;
}

fn createTrustOverlay(rt: anytype) ![]u8 {
    const trust_target = try trustTarget(rt);
    defer rt.allocator.free(trust_target);

    const codex_home = try codexHome(rt);
    defer rt.allocator.free(codex_home);
    try std.Io.Dir.cwd().createDirPath(rt.io, codex_home);

    const overlay_home = try common.fs.tempDir(rt, "codex-trust");
    errdefer {
        common.fs.deleteTreeWarning(rt.io, "Codex trust overlay", overlay_home);
        rt.allocator.free(overlay_home);
    }

    try symlinkHomeEntries(rt, codex_home, overlay_home);
    try writeTrustedConfig(rt, codex_home, overlay_home, trust_target);
    return overlay_home;
}

fn trustTarget(rt: anytype) ![]u8 {
    var result = common.process.capture(rt, &.{ "git", "rev-parse", "--show-toplevel" }) catch {
        return std.process.currentPathAlloc(rt.io, rt.allocator);
    };
    defer result.deinit(rt.allocator);

    if (result.succeeded()) {
        const trimmed = common.fs.trimAsciiWhitespace(result.stdout);
        if (trimmed.len != 0) return rt.allocator.dupe(u8, trimmed);
    }

    return std.process.currentPathAlloc(rt.io, rt.allocator);
}

fn codexHome(rt: anytype) ![]u8 {
    if (rt.env.get("CODEX_HOME")) |value| {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (trimmed.len != 0) {
            const expanded = try expandUser(rt, trimmed);
            defer rt.allocator.free(expanded);
            return std.fs.path.resolve(rt.allocator, &.{expanded});
        }
    }

    const home = rt.env.get("HOME") orelse return error.HomeMissing;
    const joined = try std.fs.path.join(rt.allocator, &.{ home, ".codex" });
    defer rt.allocator.free(joined);
    return std.fs.path.resolve(rt.allocator, &.{joined});
}

fn expandUser(rt: anytype, path: []const u8) ![]u8 {
    if (std.mem.eql(u8, path, "~")) {
        const home = rt.env.get("HOME") orelse return error.HomeMissing;
        return rt.allocator.dupe(u8, home);
    }
    if (std.mem.startsWith(u8, path, "~/")) {
        const home = rt.env.get("HOME") orelse return error.HomeMissing;
        return std.fs.path.join(rt.allocator, &.{ home, path[2..] });
    }
    return rt.allocator.dupe(u8, path);
}

fn symlinkHomeEntries(rt: anytype, codex_home: []const u8, overlay_home: []const u8) !void {
    var real_dir = try std.Io.Dir.openDirAbsolute(rt.io, codex_home, .{ .iterate = true });
    defer real_dir.close(rt.io);

    var iter = real_dir.iterate();
    while (try iter.next(rt.io)) |entry| {
        if (std.mem.eql(u8, entry.name, "config.toml")) continue;

        const source = try std.fs.path.join(rt.allocator, &.{ codex_home, entry.name });
        defer rt.allocator.free(source);
        const target = try std.fs.path.join(rt.allocator, &.{ overlay_home, entry.name });
        defer rt.allocator.free(target);

        std.Io.Dir.cwd().symLink(rt.io, source, target, .{
            .is_directory = entry.kind == .directory,
        }) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
}

fn writeTrustedConfig(rt: anytype, codex_home: []const u8, overlay_home: []const u8, trust_target: []const u8) !void {
    const source_config = try std.fs.path.join(rt.allocator, &.{ codex_home, "config.toml" });
    defer rt.allocator.free(source_config);
    const overlay_config = try std.fs.path.join(rt.allocator, &.{ overlay_home, "config.toml" });
    defer rt.allocator.free(overlay_config);

    const existing = std.Io.Dir.cwd().readFileAlloc(rt.io, source_config, rt.allocator, .limited(config_file_limit)) catch |err| switch (err) {
        error.FileNotFound => try rt.allocator.dupe(u8, ""),
        else => return err,
    };
    defer rt.allocator.free(existing);

    const updated = try trustedConfig(rt.allocator, existing, trust_target);
    defer rt.allocator.free(updated);
    try common.fs.writeFile(rt.io, overlay_config, updated, .{});
}

pub fn trustedConfig(allocator: std.mem.Allocator, existing: []const u8, trust_target: []const u8) ![]u8 {
    const header = try projectHeader(allocator, trust_target);
    defer allocator.free(header);

    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(allocator);
    try splitLines(allocator, existing, &lines);

    var project_index: ?usize = null;
    for (lines.items, 0..) |line, index| {
        if (std.mem.eql(u8, common.fs.trimAsciiWhitespace(line), header)) {
            project_index = index;
            break;
        }
    }

    if (project_index) |index| {
        var cursor = index + 1;
        while (cursor < lines.items.len and !isTableHeader(lines.items[cursor])) : (cursor += 1) {
            if (isTrustLevelLine(lines.items[cursor])) {
                lines.items[cursor] = trusted_line;
                return joinLines(allocator, lines.items);
            }
        }
        try lines.insert(allocator, index + 1, trusted_line);
    } else {
        if (lines.items.len != 0 and lines.items[lines.items.len - 1].len != 0) {
            try lines.append(allocator, "");
        }
        try lines.append(allocator, header);
        try lines.append(allocator, trusted_line);
    }

    return joinLines(allocator, lines.items);
}

fn projectHeader(allocator: std.mem.Allocator, trust_target: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    try output.appendSlice(allocator, "[projects.\"");
    for (trust_target) |byte| {
        switch (byte) {
            '\\' => try output.appendSlice(allocator, "\\\\"),
            '"' => try output.appendSlice(allocator, "\\\""),
            '\n' => try output.appendSlice(allocator, "\\n"),
            '\r' => try output.appendSlice(allocator, "\\r"),
            '\t' => try output.appendSlice(allocator, "\\t"),
            else => try output.append(allocator, byte),
        }
    }
    try output.appendSlice(allocator, "\"]");
    return output.toOwnedSlice(allocator);
}

fn splitLines(allocator: std.mem.Allocator, bytes: []const u8, lines: *std.ArrayList([]const u8)) !void {
    var start: usize = 0;
    while (start < bytes.len) {
        const end = std.mem.indexOfScalarPos(u8, bytes, start, '\n') orelse bytes.len;
        var line = bytes[start..end];
        if (std.mem.endsWith(u8, line, "\r")) line = line[0 .. line.len - 1];
        try lines.append(allocator, line);
        if (end == bytes.len) break;
        start = end + 1;
    }
}

fn joinLines(allocator: std.mem.Allocator, lines: []const []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    for (lines, 0..) |line, index| {
        if (index != 0) try output.append(allocator, '\n');
        try output.appendSlice(allocator, line);
    }
    try output.append(allocator, '\n');
    return output.toOwnedSlice(allocator);
}

fn isTableHeader(line: []const u8) bool {
    const trimmed = trimLeftAsciiWhitespace(line);
    return std.mem.startsWith(u8, trimmed, "[");
}

fn isTrustLevelLine(line: []const u8) bool {
    var rest = trimLeftAsciiWhitespace(line);
    if (!std.mem.startsWith(u8, rest, "trust_level")) return false;
    rest = rest["trust_level".len..];
    rest = trimLeftAsciiWhitespace(rest);
    return std.mem.startsWith(u8, rest, "=");
}

fn trimLeftAsciiWhitespace(value: []const u8) []const u8 {
    var index: usize = 0;
    while (index < value.len) : (index += 1) {
        switch (value[index]) {
            ' ', '\t', '\r', '\n' => {},
            else => break,
        }
    }
    return value[index..];
}

test "trustedConfig appends a missing project table" {
    const allocator = std.testing.allocator;
    const updated = try trustedConfig(allocator,
        \\model = "gpt-5.5"
        \\
    , "/repo");
    defer allocator.free(updated);

    try std.testing.expectEqualStrings(
        \\model = "gpt-5.5"
        \\
        \\[projects."/repo"]
        \\trust_level = "trusted"
        \\
    , updated);
}

test "trustedConfig updates an existing trust level before the next table" {
    const allocator = std.testing.allocator;
    const updated = try trustedConfig(allocator,
        \\[projects."/repo"]
        \\trust_level = "untrusted"
        \\other = true
        \\[tui]
        \\notification_condition = "always"
        \\
    , "/repo");
    defer allocator.free(updated);

    try std.testing.expectEqualStrings(
        \\[projects."/repo"]
        \\trust_level = "trusted"
        \\other = true
        \\[tui]
        \\notification_condition = "always"
        \\
    , updated);
}

test "trustedConfig inserts trust level for an existing project table" {
    const allocator = std.testing.allocator;
    const updated = try trustedConfig(allocator,
        \\[projects."/repo"]
        \\other = true
        \\[tui]
        \\
    , "/repo");
    defer allocator.free(updated);

    try std.testing.expectEqualStrings(
        \\[projects."/repo"]
        \\trust_level = "trusted"
        \\other = true
        \\[tui]
        \\
    , updated);
}

test "project headers escape TOML basic string bytes" {
    const allocator = std.testing.allocator;
    const header = try projectHeader(allocator, "/tmp/a\"b\\c");
    defer allocator.free(header);
    try std.testing.expectEqualStrings("[projects.\"/tmp/a\\\"b\\\\c\"]", header);
}

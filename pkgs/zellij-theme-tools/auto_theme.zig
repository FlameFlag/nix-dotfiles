const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");

const command = @import("command.zig");
const runtime = @import("runtime.zig");
const theme = @import("theme.zig");

pub fn run(init: std.process.Init) !u8 {
    const rt: runtime.Runtime = .{
        .allocator = init.gpa,
        .io = init.io,
        .env = init.environ_map,
    };

    const selected = try theme.detect(rt);

    var child_env = try init.environ_map.clone(init.gpa);
    defer child_env.deinit();
    try child_env.put("ZELLIJ_DEFAULT_FG", selected.colors.fg);
    try child_env.put("ZELLIJ_DEFAULT_BG", selected.colors.bg);

    const uid = try userIdString(rt);
    defer rt.allocator.free(uid);
    const socket_dir = try std.fmt.allocPrint(rt.allocator, "/tmp/zellij-{s}", .{uid});
    defer rt.allocator.free(socket_dir);
    try std.Io.Dir.cwd().createDirPath(rt.io, socket_dir);
    try child_env.put("ZELLIJ_SOCKET_DIR", socket_dir);

    const session_name = try defaultSessionName(rt);
    defer rt.allocator.free(session_name);

    return command.runInherit(rt, &.{
        "zellij",
        "options",
        "--theme",
        selected.name,
        "--default-layout",
        "compact",
        "--attach-to-session",
        "true",
        "--on-force-close",
        "quit",
        "--session-name",
        session_name,
    }, &child_env);
}

fn userIdString(rt: anytype) ![]u8 {
    return switch (builtin.os.tag) {
        .windows => windowsUserIdString(rt),
        else => std.fmt.allocPrint(rt.allocator, "{d}", .{std.c.getuid()}),
    };
}

fn windowsUserIdString(rt: anytype) ![]u8 {
    const uid = rt.env.get("UID") orelse return rt.allocator.dupe(u8, "0");
    if (!isUnsignedDecimal(uid)) return rt.allocator.dupe(u8, "0");
    return rt.allocator.dupe(u8, uid);
}

fn isUnsignedDecimal(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |byte| {
        if (byte < '0' or byte > '9') return false;
    }
    return true;
}

pub fn defaultSessionName(rt: anytype) ![]u8 {
    const cwd_raw = try std.process.currentPathAlloc(rt.io, rt.allocator);
    defer rt.allocator.free(cwd_raw);
    const cwd = try std.fs.path.resolve(rt.allocator, &.{cwd_raw});
    defer rt.allocator.free(cwd);

    const in_home = try cwdIsHome(rt, cwd);
    const raw_base = if (in_home)
        try userName(rt)
    else
        std.fs.path.basename(cwd);
    defer if (in_home) rt.allocator.free(raw_base);

    const sanitized = try sanitizeSessionName(rt.allocator, raw_base);
    errdefer rt.allocator.free(sanitized);

    if (sanitized.len != 0) return sanitized;
    rt.allocator.free(sanitized);
    return rt.allocator.dupe(u8, "session");
}

fn cwdIsHome(rt: anytype, cwd: []const u8) !bool {
    const home = rt.env.get("HOME") orelse return false;
    if (home.len == 0) return false;
    const resolved_home = try std.fs.path.resolve(rt.allocator, &.{home});
    defer rt.allocator.free(resolved_home);
    return std.mem.eql(u8, cwd, resolved_home);
}

fn userName(rt: anytype) ![]u8 {
    if (rt.env.get("USER")) |user| {
        const trimmed = std.mem.trim(u8, user, " \t\r\n");
        if (trimmed.len != 0) return rt.allocator.dupe(u8, trimmed);
    }

    const name = common.process.trimmedText(rt, &.{ "id", "-un" }) catch {
        return rt.allocator.dupe(u8, "session");
    };
    if (name.len != 0) return name;
    rt.allocator.free(name);
    return rt.allocator.dupe(u8, "session");
}

pub fn sanitizeSessionName(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    var pending_dash = false;
    for (raw) |byte| {
        if (isSessionByte(byte)) {
            if (pending_dash and output.items.len != 0) {
                try output.append(allocator, '-');
            }
            pending_dash = false;
            try output.append(allocator, byte);
        } else {
            pending_dash = true;
        }
    }

    return output.toOwnedSlice(allocator);
}

fn isSessionByte(byte: u8) bool {
    return (byte >= 'a' and byte <= 'z') or
        (byte >= 'A' and byte <= 'Z') or
        (byte >= '0' and byte <= '9') or
        byte == '_' or
        byte == '.' or
        byte == '-';
}

test "session names are squeezed and trimmed like the shell pipeline" {
    const allocator = std.testing.allocator;

    const simple = try sanitizeSessionName(allocator, "repo");
    defer allocator.free(simple);
    try std.testing.expectEqualStrings("repo", simple);

    const squeezed = try sanitizeSessionName(allocator, "  hello///there!! ");
    defer allocator.free(squeezed);
    try std.testing.expectEqualStrings("hello-there", squeezed);

    const kept = try sanitizeSessionName(allocator, "a_b.c-d");
    defer allocator.free(kept);
    try std.testing.expectEqualStrings("a_b.c-d", kept);
}

test "UID values must be decimal" {
    try std.testing.expect(isUnsignedDecimal("501"));
    try std.testing.expect(!isUnsignedDecimal(""));
    try std.testing.expect(!isUnsignedDecimal("abc"));
}

const std = @import("std");
const common = @import("common");

pub const Reason = enum {
    outdated,
    duplicate,
    off_topic,
    resolved,
    spam,
    abuse,

    /// Returns the GraphQL enum name accepted by GitHub.
    pub fn githubName(self: Reason) []const u8 {
        return reason_github_names.get(self);
    }
};

const reason_github_names = std.EnumArray(Reason, []const u8).init(.{
    .outdated = "OUTDATED",
    .duplicate = "DUPLICATE",
    .off_topic = "OFF_TOPIC",
    .resolved = "RESOLVED",
    .spam = "SPAM",
    .abuse = "ABUSE",
});

const reason_by_github_name =
    std.StaticStringMapWithEql(Reason, std.static_string_map.eqlAsciiIgnoreCase).initComptime(.{
        .{ "OUTDATED", .outdated },
        .{ "DUPLICATE", .duplicate },
        .{ "OFF_TOPIC", .off_topic },
        .{ "RESOLVED", .resolved },
        .{ "SPAM", .spam },
        .{ "ABUSE", .abuse },
    });

pub const UrlArg = struct {
    value: []const u8,
    owned: bool = false,
};

pub const Parsed = struct {
    help: bool = false,
    reason: Reason = .outdated,
    urls: std.ArrayList(UrlArg) = .empty,

    /// Frees all URLs owned by this value and deinitializes the URL list.
    pub fn deinit(self: *Parsed, allocator: std.mem.Allocator) void {
        for (self.urls.items) |item| {
            if (item.owned) allocator.free(item.value);
        }
        self.urls.deinit(allocator);
        self.* = undefined;
    }
};

/// Parses command line arguments.
///
/// URL arguments point into `args` and are not owned by the returned value.
pub fn parse(allocator: std.mem.Allocator, stderr: *std.Io.Writer, args: []const [:0]const u8) !Parsed {
    var parsed: Parsed = .{};
    errdefer parsed.deinit(allocator);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            parsed.help = true;
        } else if (std.mem.eql(u8, arg, "--reason")) {
            i += 1;
            if (i >= args.len) return fail(Parsed, "missing value for --reason", stderr, .{});
            parsed.reason = try parseReason(stderr, args[i]);
        } else if (std.mem.startsWith(u8, arg, "--reason=")) {
            parsed.reason = try parseReason(stderr, arg["--reason=".len..]);
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return fail(Parsed, "unknown option: {s}", stderr, .{arg});
        } else {
            try parsed.urls.append(allocator, .{ .value = arg });
        }
    }

    return parsed;
}

pub fn printUsage(stdout: *std.Io.Writer) !void {
    try stdout.print(
        \\Hide GitHub comments via the GraphQL minimizeComment mutation.
        \\
        \\Usage:
        \\  gh-hide-comment [--reason REASON] [url...]
        \\  gh-hide-comment https://github.com/owner/repo/pull/1#issuecomment-123
        \\  gh-hide-comment --reason DUPLICATE "$url1" "$url2"
        \\
        \\Supported reasons: OUTDATED, DUPLICATE, OFF_TOPIC, RESOLVED, SPAM, ABUSE
    , .{});
    try stdout.writeByte('\n');
    try stdout.flush();
}

/// Reads newline-delimited URLs from stdin until EOF or an empty line.
///
/// Appended URLs are owned by `urls` and freed by `Parsed.deinit`.
pub fn readUrls(allocator: std.mem.Allocator, io: std.Io, stderr: *std.Io.Writer, urls: *std.ArrayList(UrlArg)) !void {
    try stderr.print("info: Interactive mode. Paste comment URLs, blank line to quit.\n", .{});
    try stderr.flush();

    var buffer: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &buffer);
    const reader = &stdin_reader.interface;

    while (true) {
        try stderr.print("url> ", .{});
        try stderr.flush();
        const maybe_line = try reader.takeDelimiter('\n');
        const line = maybe_line orelse break;
        const trimmed = common.fs.trimAsciiWhitespace(line);
        if (trimmed.len == 0) break;
        const owned = try allocator.dupe(u8, trimmed);
        errdefer allocator.free(owned);
        try urls.append(allocator, .{ .value = owned, .owned = true });
    }
}

fn parseReason(stderr: *std.Io.Writer, input: []const u8) !Reason {
    if (reason_by_github_name.get(input)) |reason| return reason;
    return fail(
        Reason,
        "Invalid --reason '{s}'. Must be one of: OUTDATED, DUPLICATE, OFF_TOPIC, RESOLVED, SPAM, ABUSE",
        stderr,
        .{input},
    );
}

fn fail(comptime T: type, comptime fmt: []const u8, stderr: *std.Io.Writer, args: anytype) !T {
    try stderr.print("error: " ++ fmt ++ "\n", args);
    try stderr.flush();
    return error.Failure;
}

test "parse reason and borrowed urls" {
    const args = [_][:0]const u8{
        "--reason=spam",
        "https://github.com/ziglang/zig/issues/26#issuecomment-164134155",
    };

    var buffer: [1]u8 = undefined;
    var stderr: std.Io.Writer = .fixed(&buffer);
    var parsed = try parse(std.testing.allocator, &stderr, &args);
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Reason.spam, parsed.reason);
    try std.testing.expectEqual(@as(usize, 1), parsed.urls.items.len);
    try std.testing.expectEqualStrings(args[1], parsed.urls.items[0].value);
    try std.testing.expect(!parsed.urls.items[0].owned);
}

test "reason github names" {
    try std.testing.expectEqualStrings("OUTDATED", Reason.outdated.githubName());
    try std.testing.expectEqualStrings("DUPLICATE", Reason.duplicate.githubName());
    try std.testing.expectEqualStrings("OFF_TOPIC", Reason.off_topic.githubName());
    try std.testing.expectEqualStrings("RESOLVED", Reason.resolved.githubName());
    try std.testing.expectEqualStrings("SPAM", Reason.spam.githubName());
    try std.testing.expectEqualStrings("ABUSE", Reason.abuse.githubName());
}

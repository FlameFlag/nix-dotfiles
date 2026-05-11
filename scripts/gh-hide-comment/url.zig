const std = @import("std");

pub const Comment = struct {
    id: []const u8,
    kind: Kind,
    owner: []const u8,
    repo: []const u8,

    pub const Kind = enum {
        discussion_r,
        issuecomment,
    };
};

const AnchorSpec = struct {
    prefix: []const u8,
    kind: Comment.Kind,
};

const anchor_specs = [_]AnchorSpec{
    .{ .prefix = "issuecomment", .kind = .issuecomment },
    .{ .prefix = "discussion_r", .kind = .discussion_r },
};

/// Parses a GitHub issue or pull request comment URL.
///
/// Returned slices point into `input`.
pub fn parse(input: []const u8) !Comment {
    const uri = try std.Uri.parse(input);
    const host = uri.host orelse return error.NotGithubUrl;
    if (!std.ascii.eqlIgnoreCase(host.percent_encoded, "github.com")) return error.NotGithubUrl;

    const path = uri.path.percent_encoded;
    const fragment = uri.fragment orelse return error.MissingCommentAnchor;

    var parts = std.mem.splitScalar(u8, std.mem.trimStart(u8, path, "/"), '/');
    const owner = parts.next() orelse return error.InvalidRepoPath;
    const repo = parts.next() orelse return error.InvalidRepoPath;
    const route = parts.next() orelse return error.InvalidRepoPath;
    _ = parts.next() orelse return error.InvalidRepoPath;

    if (owner.len == 0 or repo.len == 0) return error.InvalidRepoPath;
    if (!std.mem.eql(u8, route, "pull") and !std.mem.eql(u8, route, "issues")) return error.InvalidRepoPath;

    return .{
        .id = try parseAnchor(fragment.percent_encoded),
        .kind = parseKind(fragment.percent_encoded) orelse return error.InvalidCommentAnchor,
        .owner = owner,
        .repo = repo,
    };
}

fn parseKind(anchor: []const u8) ?Comment.Kind {
    if (anchorSpec(anchor)) |spec| return spec.kind;
    return null;
}

fn parseAnchor(anchor: []const u8) ![]const u8 {
    const spec = anchorSpec(anchor) orelse return error.InvalidCommentAnchor;

    var id = anchor[spec.prefix.len..];
    if (std.mem.startsWith(u8, id, "-")) id = id[1..];
    if (!allDigits(id)) return error.InvalidCommentAnchor;
    return id;
}

fn anchorSpec(anchor: []const u8) ?AnchorSpec {
    for (anchor_specs) |spec| {
        if (std.mem.startsWith(u8, anchor, spec.prefix)) return spec;
    }
    return null;
}

fn allDigits(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |char| {
        if (!std.ascii.isDigit(char)) return false;
    }
    return true;
}

test "parse comment urls" {
    const issue = try parse("https://github.com/ziglang/zig/issues/26#issuecomment-164134155");
    try std.testing.expectEqualStrings("ziglang", issue.owner);
    try std.testing.expectEqualStrings("zig", issue.repo);
    try std.testing.expectEqualStrings("164134155", issue.id);
    try std.testing.expectEqual(Comment.Kind.issuecomment, issue.kind);

    const review = try parse("https://github.com/ziglang/zig/pull/96#discussion_r51070516");
    try std.testing.expectEqualStrings("51070516", review.id);
    try std.testing.expectEqual(Comment.Kind.discussion_r, review.kind);

    const no_dash = try parse("http://github.com/ziglang/zig/issues/26#issuecomment164134155");
    try std.testing.expectEqualStrings("164134155", no_dash.id);
    try std.testing.expectEqual(Comment.Kind.issuecomment, no_dash.kind);
}

const std = @import("std");

const http = @import("http.zig");
const cli = @import("cli.zig");
const url = @import("url.zig");

const CommentResponse = struct {
    node_id: []const u8,
};

const MinimizeResponse = struct {
    data: struct {
        minimizeComment: struct {
            minimizedComment: struct {
                isMinimized: bool,
                minimizedReason: []const u8,
            },
        },
    },
};

const mutation =
    \\mutation HideComment($id: ID!, $reason: ReportedContentClassifiers!) {
    \\  minimizeComment(input: { subjectId: $id, classifier: $reason }) {
    \\    minimizedComment {
    \\      isMinimized
    \\      minimizedReason
    \\    }
    \\  }
    \\}
;

pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    stderr: *std.Io.Writer,
    api: http.Client,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        stderr: *std.Io.Writer,
        env: *const std.process.Environ.Map,
        token: []const u8,
    ) Client {
        return .{
            .allocator = allocator,
            .io = io,
            .stderr = stderr,
            .api = http.Client.init(allocator, io, env, token),
        };
    }

    pub fn deinit(self: *Client) void {
        self.api.deinit();
    }

    /// Hides one GitHub comment URL.
    ///
    /// Errors are reported and converted to `false` so callers can continue with
    /// the remaining URLs.
    pub fn hide(self: *Client, comment_url: []const u8, reason: cli.Reason) !bool {
        try self.stderr.print("info: Processing {s}\n", .{comment_url});
        try self.stderr.flush();

        const comment = url.parse(comment_url) catch |err| {
            try self.stderr.print("error: {s}: {s}\n", .{ comment_url, @errorName(err) });
            try self.stderr.flush();
            return false;
        };

        const id = self.nodeId(comment) catch |err| {
            try self.stderr.print("error: {s}: {s}\n", .{ comment_url, @errorName(err) });
            try self.stderr.flush();
            return false;
        };
        defer self.allocator.free(id);

        const minimized_reason = self.minimize(id, reason) catch |err| {
            try self.stderr.print("error: {s}: {s}\n", .{ comment_url, @errorName(err) });
            try self.stderr.flush();
            return false;
        };
        defer self.allocator.free(minimized_reason);

        try self.stderr.print("success: {s}: hidden as {s}\n", .{ comment_url, minimized_reason });
        try self.stderr.flush();
        return true;
    }

    /// Fetches the GitHub GraphQL node ID for a REST comment reference.
    ///
    /// Caller owns returned memory.
    fn nodeId(self: *Client, comment: url.Comment) ![]u8 {
        const path = switch (comment.kind) {
            .issuecomment => try std.fmt.allocPrint(self.allocator, "repos/{s}/{s}/issues/comments/{s}", .{ comment.owner, comment.repo, comment.id }),
            .discussion_r => try std.fmt.allocPrint(self.allocator, "repos/{s}/{s}/pulls/comments/{s}", .{ comment.owner, comment.repo, comment.id }),
        };
        defer self.allocator.free(path);

        const response = try self.api.get(path);
        defer response.deinit(self.allocator);
        try self.expectSuccess(response);

        var parsed = try std.json.parseFromSlice(CommentResponse, self.allocator, response.body, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        return try self.allocator.dupe(u8, parsed.value.node_id);
    }

    /// Runs the GraphQL minimizeComment mutation and returns GitHub's reason.
    ///
    /// Caller owns returned memory.
    fn minimize(self: *Client, id: []const u8, reason: cli.Reason) ![]u8 {
        const body = try graphqlBody(self.allocator, id, reason);
        defer self.allocator.free(body);

        const response = try self.api.post("graphql", body);
        defer response.deinit(self.allocator);
        try self.expectSuccess(response);

        var parsed = try std.json.parseFromSlice(MinimizeResponse, self.allocator, response.body, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const minimized = parsed.value.data.minimizeComment.minimizedComment;
        if (!minimized.isMinimized) return error.UnexpectedMinimizeResponse;
        return try self.allocator.dupe(u8, minimized.minimizedReason);
    }

    fn expectSuccess(self: *Client, response: http.Response) !void {
        if (response.status.class() != .client_error and response.status.class() != .server_error) return;
        try self.stderr.print("error: GitHub API returned HTTP {d}: {s}\n", .{ @intFromEnum(response.status), response.body });
        try self.stderr.flush();
        return error.GitHubApiFailed;
    }
};

fn graphqlBody(allocator: std.mem.Allocator, id: []const u8, reason: cli.Reason) ![]u8 {
    const Variables = struct {
        id: []const u8,
        reason: []const u8,
    };
    const Body = struct {
        query: []const u8,
        variables: Variables,
    };

    return try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(Body{
        .query = mutation,
        .variables = .{
            .id = id,
            .reason = reason.githubName(),
        },
    }, .{})});
}

test "graphqlBody serializes minimizeComment variables" {
    const body = try graphqlBody(std.testing.allocator, "NODE_id", .duplicate);
    defer std.testing.allocator.free(body);

    const Parsed = struct {
        query: []const u8,
        variables: struct {
            id: []const u8,
            reason: []const u8,
        },
    };
    var parsed = try std.json.parseFromSlice(Parsed, std.testing.allocator, body, .{});
    defer parsed.deinit();

    try std.testing.expect(std.mem.find(u8, parsed.value.query, "minimizeComment") != null);
    try std.testing.expectEqualStrings("NODE_id", parsed.value.variables.id);
    try std.testing.expectEqualStrings("DUPLICATE", parsed.value.variables.reason);
}

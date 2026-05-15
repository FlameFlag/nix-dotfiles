const std = @import("std");
const common = @import("common");

const env = @import("env.zig");
const script = @import("script.zig");

const Allocator = std.mem.Allocator;
const Runtime = script.Runtime;

pub const Auth = enum {
    none,
    github,
};

const user_agent = "nix-dotfiles-zig-scripts";

pub fn extraHeaders(auth: Auth) []const std.http.Header {
    return switch (auth) {
        .none => &.{},
        .github => &.{
            .{ .name = "accept", .value = "application/vnd.github+json" },
        },
    };
}

pub const Client = struct {
    allocator: Allocator,
    rt: *Runtime,
    http: common.http.Client,

    pub fn init(rt: *Runtime) Client {
        return .{
            .allocator = rt.allocator,
            .rt = rt,
            .http = common.http.Client.init(rt),
        };
    }

    pub fn deinit(self: *Client) void {
        self.http.deinit();
        self.* = undefined;
    }

    /// Downloads a URL into memory.
    ///
    /// Caller owns returned memory.
    pub fn getBytes(self: *Client, url: []const u8, auth: Auth) ![]u8 {
        const auth_header = switch (auth) {
            .none => null,
            .github => try self.githubAuthorizationHeader(),
        };
        defer if (auth_header) |header| self.allocator.free(header);

        const response = try self.http.request(url, .{
            .user_agent = user_agent,
            .extra_headers = extraHeaders(auth),
            .privileged_headers = if (auth_header) |header| &.{
                .{ .name = "authorization", .value = header },
            } else &.{},
        });
        errdefer response.deinit(self.allocator);
        if (common.http.isHttpError(response.status)) {
            try self.rt.stderr.print("error: HTTP GET {s} returned {d}: {s}\n", .{
                url,
                @intFromEnum(response.status),
                response.body,
            });
            try self.rt.stderr.flush();
            return error.HttpRequestFailed;
        }

        return response.body;
    }

    /// Downloads a URL to `path` atomically, leaving any existing file intact on failure.
    pub fn downloadFile(self: *Client, url: []const u8, path: []const u8) !void {
        return self.http.downloadFile(url, path, .{
            .user_agent = user_agent,
            .extra_headers = extraHeaders(.none),
            .status_policy = .not_client_or_server_error,
        });
    }

    fn githubAuthorizationHeader(self: *Client) !?[]u8 {
        const token = try env.envOrNull(self.rt, "GITHUB_TOKEN") orelse return null;
        defer self.allocator.free(token);
        return @as(?[]u8, try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token}));
    }
};

test "plain downloads send only generic headers" {
    const headers = extraHeaders(.none);
    try std.testing.expectEqual(@as(usize, 0), headers.len);
}

test "github api requests send GitHub API accept header" {
    const headers = extraHeaders(.github);
    try std.testing.expectEqual(@as(usize, 1), headers.len);
    try std.testing.expectEqualStrings("accept", headers[0].name);
    try std.testing.expectEqualStrings("application/vnd.github+json", headers[0].value);
}

test "request header names and values satisfy std.http.Client checks" {
    inline for (.{ Auth.none, Auth.github }) |auth| {
        for (extraHeaders(auth)) |header| {
            try std.testing.expect(header.name.len != 0);
            try std.testing.expect(std.mem.findScalar(u8, header.name, ':') == null);
            try std.testing.expect(std.mem.find(u8, header.name, "\r\n") == null);
            try std.testing.expect(std.mem.find(u8, header.value, "\r\n") == null);
        }
    }
}

test "isHttpError classifies only client and server failures" {
    try std.testing.expect(!common.http.isHttpError(.ok));
    try std.testing.expect(!common.http.isHttpError(.temporary_redirect));
    try std.testing.expect(common.http.isHttpError(.not_found));
    try std.testing.expect(common.http.isHttpError(.internal_server_error));
}

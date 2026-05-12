const std = @import("std");

const env = @import("env.zig");

const Allocator = std.mem.Allocator;

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
    rt: *@import("../script.zig").Runtime,
    http: std.http.Client,

    pub fn init(rt: *@import("../script.zig").Runtime) Client {
        return .{
            .allocator = rt.allocator,
            .rt = rt,
            .http = .{ .allocator = rt.allocator, .io = rt.io },
        };
    }

    pub fn deinit(self: *Client) void {
        self.http.deinit();
    }

    /// Downloads a URL into memory.
    ///
    /// Caller owns returned memory.
    pub fn getText(self: *Client, url: []const u8, auth: Auth) ![]u8 {
        try self.loadEnvCertBundle();

        var body: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer body.deinit();

        const auth_header = switch (auth) {
            .none => null,
            .github => try self.githubAuthorizationHeader(),
        };
        defer if (auth_header) |header| self.allocator.free(header);

        const result = try self.http.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .response_writer = &body.writer,
            .headers = .{ .user_agent = .{ .override = user_agent } },
            .extra_headers = extraHeaders(auth),
            .privileged_headers = if (auth_header) |header| &.{
                .{ .name = "authorization", .value = header },
            } else &.{},
        });
        if (isHttpError(result.status)) {
            try self.rt.stderr.print("error: HTTP GET {s} returned {d}: {s}\n", .{ url, @intFromEnum(result.status), body.written() });
            try self.rt.stderr.flush();
            return error.HttpRequestFailed;
        }

        return try body.toOwnedSlice();
    }

    /// Downloads a URL to `path` atomically, leaving any existing file intact on failure.
    pub fn downloadFile(self: *Client, url: []const u8, path: []const u8) !void {
        try self.loadEnvCertBundle();

        if (std.fs.path.dirname(path)) |dir| {
            try std.Io.Dir.cwd().createDirPath(self.rt.io, dir);
        }

        var file = try std.Io.Dir.cwd().createFileAtomic(self.rt.io, path, .{ .replace = true });
        defer file.deinit(self.rt.io);

        var buffer: [8192]u8 = undefined;
        var writer = file.file.writer(self.rt.io, &buffer);
        const result = try self.http.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .response_writer = &writer.interface,
            .headers = .{ .user_agent = .{ .override = user_agent } },
            .extra_headers = extraHeaders(.none),
        });
        try writer.interface.flush();
        if (isHttpError(result.status)) return error.HttpRequestFailed;
        try file.replace(self.rt.io);
    }

    fn isHttpError(status: std.http.Status) bool {
        return status.class() == .client_error or status.class() == .server_error;
    }

    fn githubAuthorizationHeader(self: *Client) !?[]u8 {
        const token = try env.envOrNull(self.rt, "GITHUB_TOKEN") orelse return null;
        defer self.allocator.free(token);
        return try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token});
    }

    fn loadEnvCertBundle(self: *Client) !void {
        const path = try env.envOrNull(self.rt, "SSL_CERT_FILE") orelse return;
        defer self.allocator.free(path);
        if (path.len == 0) return;

        const now = std.Io.Clock.real.now(self.rt.io);
        try self.http.ca_bundle_lock.lock(self.rt.io);
        defer self.http.ca_bundle_lock.unlock(self.rt.io);
        self.http.ca_bundle.bytes.clearRetainingCapacity();
        self.http.ca_bundle.map.clearRetainingCapacity();
        try self.http.ca_bundle.addCertsFromFilePathAbsolute(self.allocator, self.rt.io, now, path);
        self.http.now = now;
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
            try std.testing.expect(std.mem.findPosLinear(u8, header.name, 0, "\r\n") == null);
            try std.testing.expect(std.mem.findPosLinear(u8, header.value, 0, "\r\n") == null);
        }
    }
}

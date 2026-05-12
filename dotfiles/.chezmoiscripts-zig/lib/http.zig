const std = @import("std");

const env = @import("env.zig");

const Allocator = std.mem.Allocator;

pub const Auth = enum {
    none,
    github,
};

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
            .extra_headers = if (auth_header) |header| &.{
                .{ .name = "accept", .value = "application/vnd.github+json" },
                .{ .name = "authorization", .value = header },
            } else &.{
                .{ .name = "accept", .value = "application/vnd.github+json" },
            },
        });
        if (result.status.class() == .client_error or result.status.class() == .server_error) return error.HttpRequestFailed;

        return try body.toOwnedSlice();
    }

    /// Downloads a URL to `path`, deleting the partial file on HTTP failure.
    pub fn downloadFile(self: *Client, url: []const u8, path: []const u8) !void {
        try self.loadEnvCertBundle();

        if (std.fs.path.dirname(path)) |dir| {
            try std.Io.Dir.cwd().createDirPath(self.rt.io, dir);
        }

        var file = try std.Io.Dir.cwd().createFile(self.rt.io, path, .{});
        defer file.close(self.rt.io);

        var buffer: [8192]u8 = undefined;
        var writer = file.writer(self.rt.io, &buffer);
        const result = try self.http.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .response_writer = &writer.interface,
        });
        try writer.interface.flush();
        if (result.status.class() == .client_error or result.status.class() == .server_error) {
            std.Io.Dir.cwd().deleteFile(self.rt.io, path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => {
                    try self.rt.stderr.print("warn: failed to delete partial download {s}: {s}\n", .{ path, @errorName(err) });
                    try self.rt.stderr.flush();
                },
            };
            return error.HttpRequestFailed;
        }
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

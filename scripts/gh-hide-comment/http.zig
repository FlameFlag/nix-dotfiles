const std = @import("std");

pub const Response = struct {
    body: []u8,
    status: std.http.Status,

    /// Frees the response body.
    pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    token: []const u8,
    http: std.http.Client,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        env: *const std.process.Environ.Map,
        token: []const u8,
    ) Client {
        return .{
            .allocator = allocator,
            .io = io,
            .env = env,
            .token = token,
            .http = .{ .allocator = allocator, .io = io },
        };
    }

    pub fn deinit(self: *Client) void {
        self.http.deinit();
    }

    /// Sends a GET request to a GitHub API path.
    ///
    /// Caller owns the response body.
    pub fn get(self: *Client, path: []const u8) !Response {
        const url = try std.fmt.allocPrint(self.allocator, "https://api.github.com/{s}", .{path});
        defer self.allocator.free(url);
        return self.request(.GET, url, null);
    }

    /// Sends a POST request to a GitHub API path.
    ///
    /// Caller owns the response body.
    pub fn post(self: *Client, path: []const u8, payload: []const u8) !Response {
        const url = try std.fmt.allocPrint(self.allocator, "https://api.github.com/{s}", .{path});
        defer self.allocator.free(url);
        return self.request(.POST, url, payload);
    }

    fn request(self: *Client, method: std.http.Method, url: []const u8, payload: ?[]const u8) !Response {
        try self.loadEnvCertBundle();

        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.token});
        defer self.allocator.free(auth_header);

        var body: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer body.deinit();

        const result = try self.http.fetch(.{
            .location = .{ .url = url },
            .method = method,
            .payload = payload,
            .response_writer = &body.writer,
            .extra_headers = &.{
                .{ .name = "accept", .value = "application/vnd.github+json" },
                .{ .name = "authorization", .value = auth_header },
                .{ .name = "x-github-api-version", .value = "2022-11-28" },
                .{ .name = "content-type", .value = "application/json" },
            },
        });

        return .{
            .body = try body.toOwnedSlice(),
            .status = result.status,
        };
    }

    fn loadEnvCertBundle(self: *Client) !void {
        const path = self.env.get("SSL_CERT_FILE") orelse return;
        if (path.len == 0) return;

        const now = std.Io.Clock.real.now(self.io);
        try self.http.ca_bundle_lock.lock(self.io);
        defer self.http.ca_bundle_lock.unlock(self.io);
        self.http.ca_bundle.bytes.clearRetainingCapacity();
        self.http.ca_bundle.map.clearRetainingCapacity();
        try self.http.ca_bundle.addCertsFromFilePathAbsolute(self.allocator, self.io, now, path);
        self.http.now = now;
    }
};

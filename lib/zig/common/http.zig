const std = @import("std");

const download_buffer_size = 8192;

pub const StatusPolicy = enum {
    none,
    success,
    not_client_or_server_error,
};

pub const StatusFailure = error{
    HttpRequestFailed,
    HttpClientError,
    HttpServerError,
};

pub const RequestOptions = struct {
    method: std.http.Method = .GET,
    payload: ?[]const u8 = null,
    user_agent: []const u8,
    content_type: ?[]const u8 = null,
    extra_headers: []const std.http.Header = &.{},
    privileged_headers: []const std.http.Header = &.{},
    status_policy: StatusPolicy = .success,
};

pub const Response = struct {
    body: []u8,
    status: std.http.Status,

    pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    proxy_arena: std.heap.ArenaAllocator,
    http: std.http.Client,
    prepared: bool = false,

    pub fn init(rt: anytype) Client {
        return initWith(rt.allocator, rt.io, rt.env);
    }

    pub fn initWith(
        allocator: std.mem.Allocator,
        io: std.Io,
        env_map: *const std.process.Environ.Map,
    ) Client {
        return .{
            .allocator = allocator,
            .io = io,
            .env = env_map,
            .proxy_arena = .init(allocator),
            .http = .{ .allocator = allocator, .io = io },
        };
    }

    pub fn deinit(self: *Client) void {
        self.http.deinit();
        self.proxy_arena.deinit();
        self.* = undefined;
    }

    /// Sends an HTTP request and returns its status and body.
    ///
    /// Caller owns the response body.
    pub fn request(self: *Client, url: []const u8, options: RequestOptions) !Response {
        try self.prepare();

        var body: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer body.deinit();

        const result = try self.http.fetch(.{
            .location = .{ .url = url },
            .method = options.method,
            .payload = options.payload,
            .response_writer = &body.writer,
            .headers = .{
                .user_agent = .{ .override = options.user_agent },
                .content_type = if (options.content_type) |value| .{ .override = value } else .omit,
            },
            .extra_headers = options.extra_headers,
            .privileged_headers = options.privileged_headers,
        });

        return .{
            .body = try body.toOwnedSlice(),
            .status = result.status,
        };
    }

    /// Sends an HTTP request and returns the response body when the status policy passes.
    ///
    /// Caller owns returned memory.
    pub fn bytes(self: *Client, url: []const u8, options: RequestOptions) ![]u8 {
        const response = try self.request(url, options);
        errdefer response.deinit(self.allocator);
        try expectStatus(response.status, options.status_policy);
        return response.body;
    }

    /// Downloads a URL to `path` atomically, leaving any existing file intact on failure.
    pub fn downloadFile(self: *Client, url: []const u8, path: []const u8, options: RequestOptions) !void {
        try self.prepare();

        if (std.fs.path.dirname(path)) |dir| {
            try std.Io.Dir.cwd().createDirPath(self.io, dir);
        }

        var file = try std.Io.Dir.cwd().createFileAtomic(self.io, path, .{ .replace = true });
        defer file.deinit(self.io);

        var buffer: [download_buffer_size]u8 = undefined;
        var writer = file.file.writer(self.io, &buffer);
        const result = try self.http.fetch(.{
            .location = .{ .url = url },
            .method = options.method,
            .payload = options.payload,
            .response_writer = &writer.interface,
            .headers = .{
                .user_agent = .{ .override = options.user_agent },
                .content_type = if (options.content_type) |value| .{ .override = value } else .omit,
            },
            .extra_headers = options.extra_headers,
            .privileged_headers = options.privileged_headers,
        });
        try writer.interface.flush();
        try expectStatus(result.status, options.status_policy);
        try file.replace(self.io);
    }

    fn prepare(self: *Client) !void {
        if (self.prepared) return;
        try self.http.initDefaultProxies(self.proxy_arena.allocator(), self.env);
        try loadEnvCertBundle(self.allocator, self.io, self.env, &self.http);
        self.prepared = true;
    }
};

pub fn expectStatus(status: std.http.Status, policy: StatusPolicy) !void {
    if (statusFailure(status, policy)) |err| return err;
}

pub fn isHttpError(status: std.http.Status) bool {
    return status.class() == .client_error or status.class() == .server_error;
}

pub fn statusFailure(status: std.http.Status, policy: StatusPolicy) ?StatusFailure {
    return switch (policy) {
        .none => null,
        .success => if (status.class() == .success) null else statusClassFailure(status),
        .not_client_or_server_error => if (isHttpError(status)) statusClassFailure(status) else null,
    };
}

fn statusClassFailure(status: std.http.Status) StatusFailure {
    return switch (status.class()) {
        .client_error => error.HttpClientError,
        .server_error => error.HttpServerError,
        else => error.HttpRequestFailed,
    };
}

pub fn writeStatusFailure(
    writer: *std.Io.Writer,
    method: std.http.Method,
    url: []const u8,
    response: Response,
) !void {
    try writer.print("error: HTTP {s} {s} returned {d}: {s}\n", .{
        @tagName(method),
        url,
        @intFromEnum(response.status),
        response.body,
    });
    try writer.flush();
}

pub fn loadEnvCertBundle(
    allocator: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    client: *std.http.Client,
) !void {
    const path = env_map.get("SSL_CERT_FILE") orelse return;
    if (path.len == 0) return;

    const now = std.Io.Clock.real.now(io);
    try client.ca_bundle_lock.lock(io);
    defer client.ca_bundle_lock.unlock(io);
    client.ca_bundle.bytes.clearRetainingCapacity();
    client.ca_bundle.map.clearRetainingCapacity();
    try client.ca_bundle.addCertsFromFilePathAbsolute(allocator, io, now, path);
    client.now = now;
}

test "HTTP success status policy rejects anything outside 2xx" {
    try expectStatus(.ok, .success);
    try expectStatus(.no_content, .success);
    try std.testing.expectError(error.HttpRequestFailed, expectStatus(.moved_permanently, .success));
    try std.testing.expectError(error.HttpClientError, expectStatus(.not_found, .success));
    try std.testing.expectError(error.HttpServerError, expectStatus(.internal_server_error, .success));
}

test "HTTP error status policy rejects only client and server failures" {
    try expectStatus(.ok, .not_client_or_server_error);
    try expectStatus(.temporary_redirect, .not_client_or_server_error);
    try std.testing.expectError(error.HttpClientError, expectStatus(.not_found, .not_client_or_server_error));
    try std.testing.expectError(
        error.HttpServerError,
        expectStatus(.internal_server_error, .not_client_or_server_error),
    );
}

test "HTTP status failures preserve response class" {
    try std.testing.expectEqual(null, statusFailure(.ok, .success));
    try std.testing.expectEqual(error.HttpRequestFailed, statusFailure(.moved_permanently, .success).?);
    try std.testing.expectEqual(error.HttpClientError, statusFailure(.not_found, .success).?);
    try std.testing.expectEqual(error.HttpServerError, statusFailure(.internal_server_error, .success).?);
}

test "HTTP client preparation is cached per client" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    var client = Client.initWith(std.testing.allocator, std.testing.io, &env);
    defer client.deinit();

    try client.prepare();
    try std.testing.expect(client.prepared);
    try client.prepare();
    try std.testing.expect(client.prepared);
}

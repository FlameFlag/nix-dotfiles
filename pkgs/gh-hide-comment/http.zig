const std = @import("std");
const common = @import("common");

const api_base_url = "https://api.github.com";
const accept_header = "application/vnd.github+json";
const api_version = "2022-11-28";
const user_agent = "gh-hide-comment";

pub const Response = common.http.Response;

pub const Client = struct {
    allocator: std.mem.Allocator,
    token: []const u8,
    http: common.http.Client,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        env: *const std.process.Environ.Map,
        token: []const u8,
    ) Client {
        return .{
            .allocator = allocator,
            .token = token,
            .http = common.http.Client.initWith(allocator, io, env),
        };
    }

    pub fn deinit(self: *Client) void {
        self.http.deinit();
        self.* = undefined;
    }

    /// Sends a GET request to a GitHub API path.
    ///
    /// Caller owns the response body.
    pub fn get(self: *Client, path: []const u8) !Response {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ api_base_url, path });
        defer self.allocator.free(url);
        return self.request(.GET, url, null);
    }

    /// Sends a POST request to a GitHub API path.
    ///
    /// Caller owns the response body.
    pub fn post(self: *Client, path: []const u8, payload: []const u8) !Response {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ api_base_url, path });
        defer self.allocator.free(url);
        return self.request(.POST, url, payload);
    }

    fn request(self: *Client, method: std.http.Method, url: []const u8, payload: ?[]const u8) !Response {
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.token});
        defer self.allocator.free(auth_header);

        return self.http.request(url, .{
            .method = method,
            .payload = payload,
            .user_agent = user_agent,
            .content_type = if (payload != null) "application/json" else null,
            .extra_headers = &.{
                .{ .name = "accept", .value = accept_header },
                .{ .name = "x-github-api-version", .value = api_version },
            },
            .privileged_headers = &.{
                .{ .name = "authorization", .value = auth_header },
            },
            .status_policy = .none,
        });
    }
};

const common = @import("common");

const Context = @import("context.zig").Context;

const user_agent = "nix-dotfiles-bootstrap";

pub fn getBytes(ctx: *Context, url: []const u8) ![]u8 {
    var client = common.http.Client.init(ctx);
    defer client.deinit();
    return client.bytes(url, .{ .user_agent = user_agent });
}

pub fn downloadFile(ctx: *Context, url: []const u8, path: []const u8) !void {
    var client = common.http.Client.init(ctx);
    defer client.deinit();
    try client.downloadFile(url, path, .{ .user_agent = user_agent });
}

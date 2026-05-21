const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");

const Context = @import("context.zig").Context;

const fs = common.fs;
const proc = common.process;
const user_agent = "dotfiles-bootstrap";

pub fn getBytes(ctx: *Context, url: []const u8) ![]u8 {
    if (builtin.os.tag == .windows) return getBytesPowerShell(ctx, url);

    var client = common.http.Client.init(ctx);
    defer client.deinit();
    return client.bytes(url, .{ .user_agent = user_agent });
}

pub fn downloadFile(ctx: *Context, url: []const u8, path: []const u8) !void {
    if (builtin.os.tag == .windows) return downloadFilePowerShell(ctx, url, path);

    var client = common.http.Client.init(ctx);
    defer client.deinit();
    try client.downloadFile(url, path, .{ .user_agent = user_agent });
}

fn getBytesPowerShell(ctx: *Context, url: []const u8) ![]u8 {
    const temp_dir = try fs.tempDir(ctx, "bootstrap-http");
    defer {
        fs.deleteTreeWarning(ctx.io, "temporary directory", temp_dir);
        ctx.allocator.free(temp_dir);
    }

    const path = try std.fs.path.join(ctx.allocator, &.{ temp_dir, "response.bin" });
    defer ctx.allocator.free(path);

    try downloadFilePowerShell(ctx, url, path);
    return std.Io.Dir.cwd().readFileAlloc(ctx.io, path, ctx.allocator, .limited(64 * 1024 * 1024));
}

fn downloadFilePowerShell(ctx: *Context, url: []const u8, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        try std.Io.Dir.cwd().createDirPath(ctx.io, dir);
    }

    try proc.run(ctx, &.{
        "powershell.exe",
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        "& { param([string] $Url, [string] $OutFile) $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $OutFile }",
        url,
        path,
    });
}

const std = @import("std");

const auth = @import("auth.zig");
const cli = @import("cli.zig");
const github = @import("github.zig");

pub fn main(init: std.process.Init) !u8 {
    return run(init) catch |err| {
        if (err == error.Failure) return 1;
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
        const stderr = &stderr_writer.interface;
        try stderr.print("error: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return 1;
    };
}

fn run(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    var parsed = try cli.parse(allocator, stderr, args[1..]);
    defer parsed.deinit(allocator);

    if (parsed.help) {
        try cli.printUsage(stdout);
        return 0;
    }

    if (parsed.urls.items.len == 0) {
        try cli.readUrls(allocator, init.io, stderr, &parsed.urls);
    }

    const token = try auth.token(allocator, init.io, stderr, init.environ_map);
    defer allocator.free(token);

    var client = github.Client.init(allocator, init.io, stderr, init.environ_map, token);
    defer client.deinit();

    var hidden: usize = 0;
    for (parsed.urls.items) |comment_url| {
        if (try client.hide(comment_url.value, parsed.reason)) hidden += 1;
    }

    try stderr.print("info: Done. {d}/{d} hidden.\n", .{ hidden, parsed.urls.items.len });
    try stderr.flush();
    if (hidden < parsed.urls.items.len) {
        try stderr.print("error: {d} of {d} failed\n", .{ parsed.urls.items.len - hidden, parsed.urls.items.len });
        try stderr.flush();
        return 1;
    }

    return 0;
}

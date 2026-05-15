const std = @import("std");
const common = @import("common");

const cli = @import("cli.zig");
const platform = @import("platform.zig");

pub fn main(init: std.process.Init) !u8 {
    return run(init) catch |err| {
        if (err == error.Failure) return 1;
        try common.output.stderr(init.io, "error: {s}\n", .{@errorName(err)});
        return 1;
    };
}

fn run(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const action = try cli.parse(stderr, args[1..]);
    if (action == null) {
        try cli.printUsage(stdout);
        return 0;
    }

    if (!try platform.isSupportedLenovo(init.gpa, init.io)) {
        try stderr.print("info: Lenovo conservation mode is only supported on Lenovo laptops", .{});
        try stderr.print(" with a known Linux or Windows backend; skipping.\n", .{});
        try stderr.flush();
        return 0;
    }

    const current = try platform.readMode(init.io, stderr);
    const desired = switch (action.?) {
        .status => null,
        .on => true,
        .off => false,
        .toggle => !current,
    };

    if (desired) |value| {
        if (value != current) {
            try platform.writeMode(init.io, stderr, value);
        }
        try stdout.print("Conservation Mode: {s}\n", .{cli.stateLabel(value)});
    } else {
        try stdout.print("Conservation Mode: {s}\n", .{cli.stateLabel(current)});
    }
    try stdout.flush();

    return 0;
}

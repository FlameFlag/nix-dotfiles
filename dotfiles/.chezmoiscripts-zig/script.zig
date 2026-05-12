const std = @import("std");

pub const Allocator = std.mem.Allocator;

pub const Runtime = struct {
    allocator: Allocator,
    io: std.Io,
    env: *std.process.Environ.Map,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
};

const env = @import("lib/env.zig");
const fs = @import("lib/fs.zig");
const process = @import("lib/process.zig");

pub const http = @import("lib/http.zig");
pub const macos = @import("lib/macos.zig");

pub const chezmoiContext = env.chezmoiContext;
pub const writeTextIfChanged = fs.writeTextIfChanged;
pub const command = process.command;
pub const commandQuiet = process.commandQuiet;
pub const commandText = process.commandText;
pub const commandTextOr = process.commandTextOr;
pub const hasBin = process.hasBin;
pub const writeCommandTextIfAvailable = process.writeCommandTextIfAvailable;
pub const tempDir = fs.tempDir;

test {
    std.testing.refAllDecls(@This());
}

/// Runs a chezmoi script with the shared runtime.
///
/// Script errors are logged before being returned.
pub fn mainWith(init: std.process.Init, comptime run: fn (*Runtime) anyerror!void) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);

    var rt: Runtime = .{
        .allocator = init.gpa,
        .io = init.io,
        .env = init.environ_map,
        .stdout = &stdout_writer.interface,
        .stderr = &stderr_writer.interface,
    };
    return run(&rt) catch |err| {
        try rt.stderr.print("error: {s}\n", .{@errorName(err)});
        try rt.stderr.flush();
        return err;
    };
}

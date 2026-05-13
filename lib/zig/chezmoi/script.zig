const std = @import("std");

pub const Allocator = std.mem.Allocator;

pub const Runtime = struct {
    allocator: Allocator,
    io: std.Io,
    env: *std.process.Environ.Map,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
};

const env = @import("env.zig");
const fs = @import("fs.zig");
const process = @import("process.zig");

const stderr_buffer_size = 1024;
const stdout_buffer_size = 1024;

pub const http = @import("http.zig");
pub const macos = @import("macos.zig");

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
pub fn mainWith(comptime run: fn (*Runtime) anyerror!void, init: std.process.Init) !void {
    var stdout_buffer: [stdout_buffer_size]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    var stderr_buffer: [stderr_buffer_size]u8 = undefined;
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

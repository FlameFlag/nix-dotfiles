const std = @import("std");
const common = @import("common");

pub const Allocator = std.mem.Allocator;

pub const Runtime = struct {
    allocator: Allocator,
    io: std.Io,
    env: *std.process.Environ.Map,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
};

const env = @import("env.zig");

const stderr_buffer_size = 1024;
const stdout_buffer_size = 1024;
const temp_dir_prefix = "chezmoi-script";

pub const http = @import("http.zig");
pub const macos = @import("macos.zig");

pub const Context = env.Context;
pub const chezmoiContext = env.chezmoiContext;
pub const writeTextIfChanged = common.fs.writeTextIfChanged;
pub const copyDirRecursive = common.fs.copyDirRecursive;
pub const command = common.process.run;
pub const commandQuiet = common.process.capture;
pub const commandText = common.process.text;
pub const extractTarGz = common.fs.extractTarGz;
pub const hasBin = common.process.hasBin;

/// Writes command stdout to `path` only when `bin` is available.
///
/// Returns whether `path` was updated.
pub fn writeCommandTextIfAvailable(
    rt: anytype,
    bin: []const u8,
    path: []const u8,
    argv: []const []const u8,
) !bool {
    if (!try hasBin(rt, bin)) return false;
    const output = try commandText(rt, argv);
    defer rt.allocator.free(output);
    return writeTextIfChanged(rt, path, output);
}

/// Creates a unique temporary directory for a chezmoi script.
///
/// Caller owns returned memory and is responsible for deleting the directory.
pub fn tempDir(rt: anytype) ![]u8 {
    return common.fs.tempDir(rt, temp_dir_prefix);
}

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

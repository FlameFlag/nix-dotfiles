const std = @import("std");
const script = @import("chezmoi");
const macos = script.macos;
const constants = @import("constants.zig");

pub const Application = struct {
    name: []const u8,
    executable_path: []const u8,
    app_path: []const u8,

    pub fn installed(self: Application, rt: *script.Runtime) !bool {
        return fileExists(rt, self.executable_path);
    }

    pub fn quitIfRunning(self: Application, rt: *script.Runtime) !bool {
        return quitExecutableIfRunning(rt, self.executable_path);
    }

    pub fn open(self: Application, rt: *script.Runtime) !void {
        try openApplication(rt, self.app_path);
    }
};

pub fn fileExists(rt: *script.Runtime, path: []const u8) !bool {
    std.Io.Dir.cwd().access(rt.io, path, .{}) catch |err| return switch (err) {
        error.FileNotFound => false,
        else => err,
    };
    return true;
}

pub fn quitRaycastIfRunning(rt: *script.Runtime) !bool {
    return classic_application.quitIfRunning(rt);
}

fn quitExecutableIfRunning(rt: *script.Runtime, executable_path: []const u8) !bool {
    const pids = try raycastPidsFor(rt, executable_path);
    defer rt.allocator.free(pids);
    if (pids.len == 0) return false;

    for (pids) |pid| {
        std.posix.kill(pid, .TERM) catch |err| switch (err) {
            error.ProcessNotFound => {},
            else => return err,
        };
    }
    try waitForExecutableToQuit(rt, executable_path);
    return true;
}

fn waitForExecutableToQuit(rt: *script.Runtime, executable_path: []const u8) !void {
    var attempt: usize = 0;
    while (attempt < constants.quit_poll_attempts) : (attempt += 1) {
        const pids = try raycastPidsFor(rt, executable_path);
        defer rt.allocator.free(pids);
        if (pids.len == 0) return;
        try std.Io.sleep(rt.io, .fromMilliseconds(constants.quit_poll_interval_ms), .awake);
    }
    return error.RaycastQuitTimedOut;
}

fn raycastPidsFor(rt: *script.Runtime, executable_path: []const u8) ![]std.posix.pid_t {
    return macos.pidsForExecutablePath(rt.allocator, rt.io, executable_path);
}

pub fn openRaycast(rt: *script.Runtime) !void {
    try classic_application.open(rt);
}

const classic_application: Application = .{
    .name = "Raycast",
    .executable_path = constants.raycast_bin,
    .app_path = constants.raycast_app,
};

fn openApplication(rt: *script.Runtime, app_path: []const u8) !void {
    _ = rt;
    var cf = try macos.CoreFoundation.load();
    defer cf.deinit();
    var launch_services = try macos.LaunchServices.load();
    defer launch_services.deinit();

    launch_services.openApplicationNoActivate(cf, app_path) catch |err| switch (err) {
        error.ApplicationLaunchFailed => return error.RaycastLaunchFailed,
        else => return err,
    };
}

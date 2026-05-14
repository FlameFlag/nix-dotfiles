const std = @import("std");
const script = @import("chezmoi");
const lifecycle = @import("classic/lifecycle.zig");
const constants = @import("classic/constants.zig");
const crypto = @import("classic/crypto.zig");

pub const app = "/Applications/Raycast Beta.app";
pub const bin = "/Applications/Raycast Beta.app/Contents/MacOS/Raycast Beta";
pub const domain = "com.raycast-x.macos";
pub const support_dir = "Library/Application Support/com.raycast-x.macos";
pub const backend_dir = app ++
    "/Contents/Resources/macos-app_RaycastDesktopApp.bundle/Contents/Resources/backend";
pub const native_binding_name = "data.darwin-arm64.node";

const beta_application: lifecycle.Application = .{
    .name = "Raycast Beta",
    .executable_path = bin,
    .app_path = app,
};

pub fn installed(rt: *script.Runtime) !bool {
    return beta_application.installed(rt);
}

pub fn ready(rt: *script.Runtime) !bool {
    const binding_path = try nativeBindingPath(rt);
    defer rt.allocator.free(binding_path);
    return lifecycle.fileExists(rt, binding_path);
}

pub fn apply(rt: *script.Runtime, context: anytype, config_path: []const u8) !void {
    const beta_support_dir = try std.fs.path.join(
        rt.allocator,
        &.{ context.home_dir, support_dir },
    );
    defer rt.allocator.free(beta_support_dir);

    const helper_path = try std.fs.path.join(
        rt.allocator,
        &.{ context.source_dir, ".chezmoi-lib/raycast_window_management/apply-beta.mjs" },
    );
    defer rt.allocator.free(helper_path);

    const binding_path = try nativeBindingPath(rt);
    defer rt.allocator.free(binding_path);

    try rt.stderr.print("info: Applying Raycast Beta window-management settings...\n", .{});
    try rt.stderr.flush();

    const app_was_running = try quitIfRunning(rt);
    const backend_was_running = try quitBackendIfRunning(rt);
    const password = try betaDatabasePassword(rt);
    defer rt.allocator.free(password);

    try applyConfig(rt, beta_support_dir, config_path, helper_path, binding_path, password);
    if (app_was_running or backend_was_running) try open(rt);
}

fn applyConfig(
    rt: *script.Runtime,
    beta_support_dir: []const u8,
    config_path: []const u8,
    helper_path: []const u8,
    binding_path: []const u8,
    password: []const u8,
) !void {
    const node = try nodeRuntime(rt, beta_support_dir);
    defer rt.allocator.free(node);

    var result = try script.commandQuiet(rt, &.{
        node,
        helper_path,
        beta_support_dir,
        config_path,
        binding_path,
        password,
    });
    defer result.deinit(rt.allocator);
    if (result.stdout.len > 0) try rt.stderr.writeAll(result.stdout);
    if (result.stderr.len > 0) try rt.stderr.writeAll(result.stderr);
    try rt.stderr.flush();
    if (result.exit_code != 0) return error.RaycastBetaApplyFailed;
}

fn betaDatabasePassword(rt: *script.Runtime) ![]u8 {
    return crypto.databasePasswordFor(
        rt,
        "Raycast Beta",
        "database_key",
        bin,
        .{ .first_printable_after_anchor = "com.raycast-x.deleted" },
    );
}

fn nodeRuntime(rt: *script.Runtime, beta_support_dir: []const u8) ![]u8 {
    const runtime_dir_path = try std.fs.path.join(
        rt.allocator,
        &.{ beta_support_dir, "node/runtime" },
    );
    defer rt.allocator.free(runtime_dir_path);

    var runtime_dir = try std.Io.Dir.openDirAbsolute(rt.io, runtime_dir_path, .{ .iterate = true });
    defer runtime_dir.close(rt.io);

    var best_path: ?[]u8 = null;
    var best_version: std.SemanticVersion = .{ .major = 0, .minor = 0, .patch = 0 };
    var iter = runtime_dir.iterate();
    while (try iter.next(rt.io)) |entry| {
        if (entry.kind != .directory) continue;
        const version = parseRaycastNodeRuntimeVersion(entry.name) catch continue;
        const node = try std.fs.path.join(rt.allocator, &.{ runtime_dir_path, entry.name, "bin/node" });
        errdefer rt.allocator.free(node);
        if (!try executableExists(rt, node)) {
            rt.allocator.free(node);
            continue;
        }
        if (best_path == null or version.order(best_version) == .gt) {
            if (best_path) |old| rt.allocator.free(old);
            best_path = node;
            best_version = version;
        } else {
            rt.allocator.free(node);
        }
    }
    return best_path orelse error.RaycastBetaNodeNotFound;
}

fn nativeBindingPath(rt: *script.Runtime) ![]u8 {
    return std.fs.path.join(rt.allocator, &.{ backend_dir, native_binding_name });
}

fn executableExists(rt: *script.Runtime, path: []const u8) !bool {
    std.Io.Dir.accessAbsolute(rt.io, path, .{ .execute = true }) catch |err| return switch (err) {
        error.FileNotFound => false,
        else => err,
    };
    return true;
}

fn parseRaycastNodeRuntimeVersion(name: []const u8) !std.SemanticVersion {
    const prefix = "node-v";
    const suffix = "-darwin-arm64";
    if (!std.mem.startsWith(u8, name, prefix) or !std.mem.endsWith(u8, name, suffix)) return error.InvalidVersion;
    return std.SemanticVersion.parse(name[prefix.len .. name.len - suffix.len]);
}

fn quitIfRunning(rt: *script.Runtime) !bool {
    return beta_application.quitIfRunning(rt);
}

fn quitBackendIfRunning(rt: *script.Runtime) !bool {
    const pids = try betaBackendPids(rt);
    defer rt.allocator.free(pids);
    if (pids.len == 0) return false;

    for (pids) |pid| {
        std.posix.kill(pid, .TERM) catch |err| switch (err) {
            error.ProcessNotFound => {},
            else => return err,
        };
    }
    try waitForBackendToQuit(rt);
    return true;
}

fn waitForBackendToQuit(rt: *script.Runtime) !void {
    var attempt: usize = 0;
    while (attempt < constants.quit_poll_attempts) : (attempt += 1) {
        const pids = try betaBackendPids(rt);
        defer rt.allocator.free(pids);
        if (pids.len == 0) return;
        try std.Io.sleep(rt.io, .fromMilliseconds(constants.quit_poll_interval_ms), .awake);
    }
    return error.RaycastQuitTimedOut;
}

fn betaBackendPids(rt: *script.Runtime) ![]std.posix.pid_t {
    var result = try script.commandQuiet(rt, &.{ "/usr/bin/pgrep", "-f", "Raycast Beta Backend" });
    defer result.deinit(rt.allocator);
    if (result.exit_code != 0) return &.{};

    var pids = std.ArrayList(std.posix.pid_t).empty;
    errdefer pids.deinit(rt.allocator);
    var lines = std.mem.tokenizeAny(u8, result.stdout, "\r\n");
    while (lines.next()) |line| {
        const pid = std.fmt.parseInt(std.posix.pid_t, std.mem.trim(u8, line, " \t"), 10) catch continue;
        try pids.append(rt.allocator, pid);
    }
    return pids.toOwnedSlice(rt.allocator);
}

fn open(rt: *script.Runtime) !void {
    try beta_application.open(rt);
}

test "parseRaycastNodeRuntimeVersion accepts Raycast runtime directory names" {
    const version = try parseRaycastNodeRuntimeVersion("node-v22.22.2-darwin-arm64");
    try std.testing.expectEqual(@as(usize, 22), version.major);
    try std.testing.expectEqual(@as(usize, 22), version.minor);
    try std.testing.expectEqual(@as(usize, 2), version.patch);
    try std.testing.expectError(error.InvalidVersion, parseRaycastNodeRuntimeVersion("node-v22.22.2"));
}

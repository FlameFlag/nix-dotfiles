const std = @import("std");
const script = @import("chezmoi");
const macos = script.macos;

const apply_mod = @import("classic/apply.zig");
const config_mod = @import("classic/config.zig");
const constants = @import("classic/constants.zig");
const crypto = @import("classic/crypto.zig");
const database = @import("classic/database.zig");
const lifecycle = @import("classic/lifecycle.zig");
const sqlcipher = @import("classic/sqlcipher.zig");

const RaycastPaths = struct {
    config: []u8,
    db: []u8,

    fn deinit(self: *RaycastPaths, allocator: script.Allocator) void {
        allocator.free(self.config);
        allocator.free(self.db);
        self.* = undefined;
    }
};

pub const config_relative_path = constants.config_relative_path;

pub fn installed(rt: *script.Runtime) !bool {
    return lifecycle.fileExists(rt, constants.raycast_bin);
}

pub fn ready(rt: *script.Runtime, context: anytype) !bool {
    var paths = try raycastPaths(rt, context);
    defer paths.deinit(rt.allocator);
    return lifecycle.fileExists(rt, paths.db);
}

pub fn configPath(rt: *script.Runtime, context: anytype) ![]u8 {
    return std.fs.path.join(rt.allocator, &.{ context.source_dir, config_relative_path });
}

pub fn configExists(rt: *script.Runtime, context: anytype) !bool {
    const path = try configPath(rt, context);
    defer rt.allocator.free(path);
    return configExistsAt(rt, path);
}

pub fn configExistsAt(rt: *script.Runtime, path: []const u8) !bool {
    return lifecycle.fileExists(rt, path);
}

pub fn apply(rt: *script.Runtime, context: anytype) !void {
    var paths = try raycastPaths(rt, context);
    defer paths.deinit(rt.allocator);

    if (!try canApplyConfig(rt, paths)) return;
    try ensureRaycastDefaults(rt);
    const was_running = try lifecycle.quitRaycastIfRunning(rt);
    try apply_mod.applyConfig(rt, paths);
    if (was_running) try lifecycle.openRaycast(rt);
}

fn ensureRaycastDefaults(rt: *script.Runtime) !void {
    _ = rt;
    var cf = try macos.CoreFoundation.load();
    defer cf.deinit();

    try cf.addStringToAppArrayPreference(
        constants.domain,
        "onboarding_completedTaskIdentifiers",
        "windowManagement",
    );
    try cf.addStringToAppArrayPreference(
        constants.domain,
        "commandsPreferencesExpandedItemIds",
        "builtin_package_windowManagement",
    );
}

fn raycastPaths(rt: *script.Runtime, context: anytype) !RaycastPaths {
    return .{
        .config = try std.fs.path.join(
            rt.allocator,
            &.{ context.source_dir, config_relative_path },
        ),
        .db = try std.fs.path.join(
            rt.allocator,
            &.{ context.home_dir, "Library/Application Support/com.raycast.macos/raycast-enc.sqlite" },
        ),
    };
}

fn canApplyConfig(rt: *script.Runtime, paths: RaycastPaths) !bool {
    var ok = true;
    if (!try lifecycle.fileExists(rt, paths.config)) {
        try rt.stderr.print("warn: Raycast window-management config not found: {s}\n", .{paths.config});
        ok = false;
    }
    if (!try lifecycle.fileExists(rt, paths.db)) {
        try rt.stderr.print("warn: Raycast database not found: {s}\n", .{paths.db});
        ok = false;
    }
    try rt.stderr.flush();
    return ok;
}

test {
    std.testing.refAllDecls(apply_mod);
    std.testing.refAllDecls(config_mod);
    std.testing.refAllDecls(crypto);
    std.testing.refAllDecls(database);
    std.testing.refAllDecls(lifecycle);
    std.testing.refAllDecls(sqlcipher);
}

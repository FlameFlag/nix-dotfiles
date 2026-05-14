const std = @import("std");
const builtin = @import("builtin");
const script = @import("chezmoi");

const beta = @import("beta.zig");
const classic = @import("classic.zig");

const RaycastEdition = struct {
    name: []const u8,
    installed: *const fn (*script.Runtime) anyerror!bool,
    apply: *const fn (*script.Runtime, script.Context, []const u8) anyerror!bool,
};

const editions = [_]RaycastEdition{
    .{ .name = "classic", .installed = classic.installed, .apply = applyClassic },
    .{ .name = "beta", .installed = beta.installed, .apply = applyBeta },
};

/// Applies Raycast window-management settings on macOS.
pub fn main(init: std.process.Init) !void {
    if (builtin.os.tag != .macos) return;

    try script.mainWith(run, init);
}

fn run(rt: *script.Runtime) !void {
    const context = try script.chezmoiContext(rt);
    defer context.deinit(rt.allocator);
    if (!std.mem.eql(u8, context.os, "darwin")) return;

    var installed_count: usize = 0;
    for (editions) |edition| {
        if (try edition.installed(rt)) installed_count += 1;
    }
    if (installed_count == 0) return error.RaycastNotInstalled;

    const config_path = try classic.configPath(rt, context);
    defer rt.allocator.free(config_path);
    if (!try classic.configExistsAt(rt, config_path)) {
        try rt.stderr.print("warn: Raycast window-management config not found: {s}\n", .{config_path});
        try rt.stderr.flush();
        return;
    }

    var applied = false;
    for (editions) |edition| {
        if (!try edition.installed(rt)) continue;
        applied = (try edition.apply(rt, context, config_path)) or applied;
    }

    if (!applied) return error.RaycastNotInstalled;
}

fn applyClassic(rt: *script.Runtime, context: script.Context, config_path: []const u8) !bool {
    _ = config_path;
    if (!try classic.ready(rt, context)) {
        try rt.stderr.print(
            "warn: Raycast classic is installed but its database is not ready; skipping classic\n",
            .{},
        );
        try rt.stderr.flush();
        return false;
    }
    try classic.apply(rt, context);
    return true;
}

fn applyBeta(rt: *script.Runtime, context: script.Context, config_path: []const u8) !bool {
    if (!try beta.ready(rt)) {
        try rt.stderr.print(
            "warn: Raycast Beta is installed but its native data binding is not ready: {s}/{s}\n",
            .{ beta.backend_dir, beta.native_binding_name },
        );
        try rt.stderr.flush();
        return false;
    }
    try beta.apply(rt, context, config_path);
    return true;
}

test {
    std.testing.refAllDecls(@This());
}

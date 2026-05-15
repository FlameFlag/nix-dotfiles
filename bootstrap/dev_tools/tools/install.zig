const std = @import("std");
const builtin = @import("builtin");
const bootstrap = @import("bootstrap");
const common = @import("common");

const actions = @import("actions.zig");
const catalog = @import("catalog.zig");
const host = @import("host.zig");

const Context = bootstrap.Context;
const model = bootstrap.manifest;
const ownership = bootstrap.ownership;
const output = common.output;
const package_managers = bootstrap.packages;
const proc = common.process;

pub fn all(ctx: *Context, policy: model.Policy) !void {
    var loaded = try catalog.load(ctx);
    defer loaded.deinit(ctx);

    var failures: usize = 0;
    inline for (std.enums.values(model.Phase)) |install_phase| {
        for (loaded.parsed.value.tools) |tool| {
            if (tool.phase() != install_phase) continue;
            failures += try one(ctx, policy, tool);
        }
    }
    if (failures != 0) return error.SomeToolsFailed;
}

fn one(ctx: *Context, policy: model.Policy, tool: model.Tool) !usize {
    if (!try host.supportsTool(tool, ctx)) {
        try output.stdout(ctx.io, "{s}: unsupported on this host, skipping\n", .{tool.name});
        return 0;
    }

    if (tool.isRequired()) {
        const present = proc.hasBin(ctx, tool.name) catch |err| {
            try output.stderr(ctx.io, "error: {s}: lookup failed: {s}\n", .{ tool.name, @errorName(err) });
            return 1;
        };
        if (present) {
            try output.stdout(ctx.io, "{s}: bootstrap prerequisite, skipping\n", .{tool.name});
            return 0;
        }
        try output.stderr(
            ctx.io,
            "error: {s}: missing bootstrap prerequisite; run bootstrap/bootstrap.sh\n",
            .{tool.name},
        );
        return 1;
    }

    if (policy == .install_missing) {
        if (!try shouldInstall(ctx, tool)) {
            try output.stdout(ctx.io, "{s}: present, skipping\n", .{tool.name});
            return 0;
        }
    }
    try output.stdout(ctx.io, "{s}: {s}\n", .{ tool.name, installVerb(policy, tool) });
    actions.install(ctx, tool) catch |err| {
        try output.stderr(ctx.io, "error: {s}: {s}\n", .{ tool.name, @errorName(err) });
        return 1;
    };
    return 0;
}

fn installVerb(policy: model.Policy, tool: model.Tool) []const u8 {
    if (policy == .update_all) return "updating";
    return switch (tool.action.type) {
        .toolchain => "ensuring",
        else => "installing",
    };
}

fn shouldInstall(ctx: *Context, tool: model.Tool) !bool {
    return switch (tool.action.type) {
        .toolchain => true,
        .build => true,
        .script => !try localBinsPresent(ctx, tool),
        .required => (try firstMissingBin(ctx, tool)) != null,
        .archive, .package => !try managedBinsPresent(ctx, tool),
    };
}

fn firstMissingBin(ctx: *Context, tool: model.Tool) !?[]const u8 {
    for (tool.bins) |bin| {
        const present = proc.hasBin(ctx, bin.name) catch |err| {
            try output.stderr(ctx.io, "error: {s}: lookup failed: {s}\n", .{ bin.name, @errorName(err) });
            return err;
        };
        if (!present) return bin.name;
    }
    return null;
}

fn localBinsPresent(ctx: *Context, tool: model.Tool) !bool {
    for (tool.bins) |bin| {
        if (!try ownership.localExecutableInBinDir(ctx, bin.name)) return false;
    }
    return true;
}

fn managedBinsPresent(ctx: *Context, tool: model.Tool) !bool {
    const cwd = try std.process.currentPathAlloc(ctx.io, ctx.allocator);
    defer ctx.allocator.free(cwd);

    var packages = if (tool.action.type == .package)
        try package_managers.Inventory.collect(ctx)
    else
        package_managers.Inventory.empty();
    defer if (tool.action.type == .package) packages.deinit(ctx);

    for (tool.bins) |bin| {
        const classification = try ownership.classifyBinOnPath(ctx, cwd, tool, bin.name, packages);
        if (classification != .managed) return false;
    }
    return true;
}

test "install verbs are stable user-facing labels" {
    const toolchain: model.Tool = .{
        .name = "rustup",
        .bins = &.{},
        .action = .{
            .type = .toolchain,
        },
    };
    const archive_tool: model.Tool = .{
        .name = "zls",
        .bins = &.{},
        .action = .{ .type = .archive },
    };

    try std.testing.expectEqualStrings("ensuring", installVerb(.install_missing, toolchain));
    try std.testing.expectEqualStrings("installing", installVerb(.install_missing, archive_tool));
    try std.testing.expectEqualStrings("updating", installVerb(.update_all, archive_tool));
}

fn testingContext(env: *std.process.Environ.Map, bin_dir: []const u8, opt_dir: []const u8) Context {
    return .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = env,
        .home = "/home/me",
        .bin_dir = bin_dir,
        .opt_dir = opt_dir,
    };
}

fn tmpPath(allocator: std.mem.Allocator, tmp: std.testing.TmpDir, parts: []const []const u8) ![]u8 {
    return common.testing.tmpPath(allocator, tmp, parts);
}

test "install_missing reinstalls archive bins that are external on PATH" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const external_bin = try tmpPath(std.testing.allocator, tmp, &.{"external-bin"});
    defer std.testing.allocator.free(external_bin);
    const external_tool = try tmpPath(std.testing.allocator, tmp, &.{ "external-bin", "demo" });
    defer std.testing.allocator.free(external_tool);
    try common.fs.writeExecutableFile(std.testing.io, external_tool, "");
    try env.put("PATH", external_bin);

    var ctx = testingContext(&env, "/home/me/.local/bin", "/home/me/.local/opt");
    const tool: model.Tool = .{
        .name = "demo",
        .bins = &.{.{ .name = "demo", .version_argv = &.{"demo"} }},
        .action = .{ .type = .archive },
    };

    try std.testing.expect(try shouldInstall(&ctx, tool));
}

test "install_missing skips managed archive symlinks" {
    if (builtin.os.tag == .windows) return;

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const bin_dir = try tmpPath(std.testing.allocator, tmp, &.{"bin"});
    defer std.testing.allocator.free(bin_dir);
    const opt_dir = try tmpPath(std.testing.allocator, tmp, &.{"opt"});
    defer std.testing.allocator.free(opt_dir);
    const target = try tmpPath(std.testing.allocator, tmp, &.{ "opt", "demo", "1.0.0", "demo" });
    defer std.testing.allocator.free(target);
    const link = try tmpPath(std.testing.allocator, tmp, &.{ "bin", "demo" });
    defer std.testing.allocator.free(link);

    try common.fs.writeExecutableFile(std.testing.io, target, "");
    try std.Io.Dir.cwd().createDirPath(std.testing.io, bin_dir);
    try std.Io.Dir.symLinkAbsolute(std.testing.io, target, link, .{});
    try env.put("PATH", bin_dir);

    var ctx = testingContext(&env, bin_dir, opt_dir);
    const tool: model.Tool = .{
        .name = "demo",
        .bins = &.{.{ .name = "demo", .version_argv = &.{"demo"} }},
        .action = .{ .type = .archive },
    };

    try std.testing.expect(!try shouldInstall(&ctx, tool));
}

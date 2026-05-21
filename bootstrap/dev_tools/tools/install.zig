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
        for (loaded.tools) |tool| {
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
    var plan = bootstrap.plan.InstallPlan.fromTool(ctx, tool) catch |err| {
        try output.stderr(ctx.io, "error: {s}: {s}\n", .{ tool.name, @errorName(err) });
        return 1;
    };
    defer plan.deinit(ctx.allocator);
    actions.install(ctx, plan) catch |err| {
        try output.stderr(ctx.io, "error: {s}: {s}\n", .{ tool.name, @errorName(err) });
        return 1;
    };
    return 0;
}

fn installVerb(policy: model.Policy, tool: model.Tool) []const u8 {
    if (policy == .update_all) return "updating";
    return switch (tool.action) {
        .toolchain => "ensuring",
        else => "installing",
    };
}

fn shouldInstall(ctx: *Context, tool: model.Tool) !bool {
    return switch (tool.action) {
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

    const is_package = switch (tool.action) {
        .package => true,
        else => false,
    };
    var packages = if (is_package) try package_managers.Inventory.collect(ctx) else package_managers.Inventory.empty();
    defer if (is_package) packages.deinit(ctx);

    for (tool.bins) |bin| {
        const path = try proc.pathOf(ctx, bin.name);
        defer if (path) |value| ctx.allocator.free(value);

        const classification = try ownership.classifyBin(ctx, cwd, tool, bin.name, path, packages);
        switch (classification) {
            .missing => return false,
            .external => {
                if (path) |value| {
                    if (try ownership.pathIsUnder(ctx, cwd, value, ctx.bin_dir)) continue;
                }
                return false;
            },
            .managed => if (!try binRuns(ctx, bin)) return false,
        }
    }
    switch (tool.action) {
        .archive => |archive_spec| if (!try managedAppLinksPresent(ctx, tool, archive_spec)) return false,
        else => {},
    }
    return true;
}

fn binRuns(ctx: *Context, bin: model.Bin) !bool {
    var result = try proc.capture(ctx, bin.version_argv);
    defer result.deinit(ctx.allocator);
    return result.succeeded();
}

fn managedAppLinksPresent(ctx: *Context, tool: model.Tool, archive_spec: model.Archive) !bool {
    if (builtin.os.tag != .macos) return true;

    const selected = model.selectArchivePlatform(archive_spec.platforms) catch |err| switch (err) {
        error.UnsupportedPlatform => return true,
    };
    for (selected.app_links) |app_link| {
        const link_path = try std.fs.path.join(ctx.allocator, &.{ "/Applications", app_link.name });
        defer ctx.allocator.free(link_path);

        var old_buf: [4096]u8 = undefined;
        const old_len = std.Io.Dir.cwd().readLink(ctx.io, link_path, &old_buf) catch |err| switch (err) {
            error.FileNotFound, error.NotLink => return false,
            else => return err,
        };
        const old = old_buf[0..old_len];
        if (!std.fs.path.isAbsolute(old)) return false;

        const prefix = try std.fs.path.join(ctx.allocator, &.{ ctx.opt_dir, tool.name });
        defer ctx.allocator.free(prefix);
        const normalized_prefix = try std.fs.path.resolve(ctx.allocator, &.{prefix});
        defer ctx.allocator.free(normalized_prefix);
        const normalized_old = try std.fs.path.resolve(ctx.allocator, &.{old});
        defer ctx.allocator.free(normalized_old);
        if (!std.mem.startsWith(u8, normalized_old, normalized_prefix)) return false;
        const old_is_under_prefix = normalized_old.len == normalized_prefix.len or
            std.fs.path.isSep(normalized_old[normalized_prefix.len]);
        if (!old_is_under_prefix) return false;
    }
    return true;
}

test "install verbs are stable user-facing labels" {
    const toolchain: model.Tool = .{
        .name = "demo-toolchain",
        .bins = &.{},
        .action = .{ .toolchain = .{
            .manager_bin = "manager",
            .name = "stable",
            .bin_dir = .{ .env_var = "TOOLCHAIN_HOME", .home_relative = ".toolchain/bin" },
            .components = &.{"formatter"},
            .install = .{ .unix = .{
                .url = "https://example.test",
                .file = "install.sh",
                .argv = &.{"{file}"},
            } },
            .update_argv = &.{"{manager_bin}"},
            .active_argv = &.{"{manager_bin}"},
            .default_argv = &.{"{manager_bin}"},
            .component_argv = &.{"{component}"},
        } },
    };
    const archive_tool: model.Tool = .{
        .name = "demo-archive",
        .bins = &.{},
        .action = .{ .archive = .{ .platforms = &.{} } },
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
        .action = .{ .archive = .{ .platforms = &.{} } },
    };

    try std.testing.expect(try shouldInstall(&ctx, tool));
}

test "install_missing skips local non-managed archive bins" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const bin_dir = try tmpPath(std.testing.allocator, tmp, &.{"bin"});
    defer std.testing.allocator.free(bin_dir);
    const opt_dir = try tmpPath(std.testing.allocator, tmp, &.{"opt"});
    defer std.testing.allocator.free(opt_dir);
    const tool_path = try tmpPath(std.testing.allocator, tmp, &.{ "bin", "demo" });
    defer std.testing.allocator.free(tool_path);
    try common.fs.writeExecutableFile(std.testing.io, tool_path, "");
    try env.put("PATH", bin_dir);

    var ctx = testingContext(&env, bin_dir, opt_dir);
    const tool: model.Tool = .{
        .name = "demo",
        .bins = &.{.{ .name = "demo", .version_argv = &.{tool_path} }},
        .action = .{ .archive = .{ .platforms = &.{} } },
    };

    try std.testing.expect(!try shouldInstall(&ctx, tool));
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

    try common.fs.writeExecutableFile(std.testing.io, target,
        \\#!/bin/sh
        \\exit 0
        \\
    );
    try std.Io.Dir.cwd().createDirPath(std.testing.io, bin_dir);
    try std.Io.Dir.symLinkAbsolute(std.testing.io, target, link, .{});
    try env.put("PATH", bin_dir);

    var ctx = testingContext(&env, bin_dir, opt_dir);
    const tool: model.Tool = .{
        .name = "demo",
        .bins = &.{.{ .name = "demo", .version_argv = &.{link} }},
        .action = .{ .archive = .{ .platforms = &.{} } },
    };

    try std.testing.expect(!try shouldInstall(&ctx, tool));
}

test "install_missing reinstalls managed archive symlinks that do not run" {
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

    try common.fs.writeExecutableFile(std.testing.io, target,
        \\#!/bin/sh
        \\exit 42
        \\
    );
    try std.Io.Dir.cwd().createDirPath(std.testing.io, bin_dir);
    try std.Io.Dir.symLinkAbsolute(std.testing.io, target, link, .{});
    try env.put("PATH", bin_dir);

    var ctx = testingContext(&env, bin_dir, opt_dir);
    const tool: model.Tool = .{
        .name = "demo",
        .bins = &.{.{ .name = "demo", .version_argv = &.{link} }},
        .action = .{ .archive = .{ .platforms = &.{} } },
    };

    try std.testing.expect(try shouldInstall(&ctx, tool));
}

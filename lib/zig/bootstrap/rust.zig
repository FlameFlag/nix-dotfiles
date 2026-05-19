const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");

const Context = @import("context.zig").Context;
const http = @import("http.zig");
const manifest = @import("manifest.zig");
const fs = common.fs;
const proc = common.process;

pub fn installOrUpdate(ctx: *Context, spec: manifest.Toolchain) !void {
    const resolved_toolchain = if (spec.name_env) |env_name| ctx.env.get(env_name) orelse spec.name else spec.name;
    var manager = try localManager(ctx, spec);
    defer if (manager) |path| ctx.allocator.free(path);

    if (manager == null) {
        try installManager(ctx, spec, resolved_toolchain);
        manager = try installedManagerPath(ctx, spec);
    }

    const manager_path = manager orelse return error.CommandFailed;
    const update_argv = try renderToolchainArgv(ctx, spec, spec.update_argv, .{
        .manager_bin = manager_path,
        .toolchain = resolved_toolchain,
    });
    defer freeArgv(ctx, update_argv);
    try proc.run(ctx, update_argv);

    const active_argv = try renderToolchainArgv(ctx, spec, spec.active_argv, .{
        .manager_bin = manager_path,
        .toolchain = resolved_toolchain,
    });
    defer freeArgv(ctx, active_argv);

    var active = try proc.capture(ctx, active_argv);
    defer active.deinit(ctx.allocator);
    if (active.exit_code != 0) {
        const default_argv = try renderToolchainArgv(ctx, spec, spec.default_argv, .{
            .manager_bin = manager_path,
            .toolchain = resolved_toolchain,
        });
        defer freeArgv(ctx, default_argv);
        try proc.run(ctx, default_argv);
    }
}

pub fn toolchainBinDir(ctx: *Context, spec: manifest.Toolchain) ![]u8 {
    if (spec.bin_dir.env_var) |env_var| {
        if (ctx.env.get(env_var)) |root| {
            return std.fs.path.join(ctx.allocator, &.{ root, "bin" });
        }
    }
    return std.fs.path.join(ctx.allocator, &.{ ctx.home, spec.bin_dir.home_relative });
}

fn installManager(ctx: *Context, spec: manifest.Toolchain, toolchain: []const u8) !void {
    const command = if (builtin.os.tag == .windows) spec.install.windows else spec.install.unix;
    const selected = command orelse return error.UnsupportedPlatform;

    const installer = try downloadFile(ctx, "rustup-install", selected.file, selected.url);
    defer removeDownloadedScript(ctx, installer);
    const install_argv = try renderToolchainArgv(ctx, spec, selected.argv, .{
        .file = installer,
        .toolchain = toolchain,
    });
    defer freeArgv(ctx, install_argv);
    try proc.run(ctx, install_argv);
}

fn renderToolchainArgv(
    ctx: *Context,
    spec: manifest.Toolchain,
    templates: []const []const u8,
    bindings: common.template.Bindings,
) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (argv.items) |arg| ctx.allocator.free(arg);
        argv.deinit(ctx.allocator);
    }

    for (templates) |template| {
        if (std.mem.eql(u8, template, "{components}")) {
            try appendComponentArgv(ctx, spec, &argv, bindings);
            continue;
        }
        const rendered = try common.template.Template.literal(template).render(ctx.allocator, bindings);
        errdefer ctx.allocator.free(rendered);
        try argv.append(ctx.allocator, rendered);
    }
    return argv.toOwnedSlice(ctx.allocator);
}

fn appendComponentArgv(
    ctx: *Context,
    spec: manifest.Toolchain,
    argv: *std.ArrayList([]const u8),
    bindings: common.template.Bindings,
) !void {
    for (spec.components) |component| {
        var component_bindings = bindings;
        component_bindings.component = component;
        for (spec.component_argv) |template| {
            const rendered = try common.template.Template.literal(template).render(ctx.allocator, component_bindings);
            errdefer ctx.allocator.free(rendered);
            try argv.append(ctx.allocator, rendered);
        }
    }
}

fn freeArgv(ctx: *Context, argv: []const []const u8) void {
    for (argv) |arg| ctx.allocator.free(arg);
    ctx.allocator.free(argv);
}

fn localManager(ctx: *Context, spec: manifest.Toolchain) !?[]u8 {
    const bin_dir = try toolchainBinDir(ctx, spec);
    defer ctx.allocator.free(bin_dir);
    const manager_name = try executableName(ctx, spec.manager_bin);
    defer ctx.allocator.free(manager_name);
    const candidate = try std.fs.path.join(ctx.allocator, &.{ bin_dir, manager_name });
    errdefer ctx.allocator.free(candidate);
    std.Io.Dir.cwd().access(ctx.io, candidate, .{ .execute = true }) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => {
            ctx.allocator.free(candidate);
            return null;
        },
        else => return err,
    };
    return candidate;
}

fn installedManagerPath(ctx: *Context, spec: manifest.Toolchain) ![]u8 {
    const bin_dir = try toolchainBinDir(ctx, spec);
    defer ctx.allocator.free(bin_dir);
    const manager_name = try executableName(ctx, spec.manager_bin);
    defer ctx.allocator.free(manager_name);
    return std.fs.path.join(ctx.allocator, &.{ bin_dir, manager_name });
}

fn downloadFile(ctx: *Context, prefix: []const u8, file_name: []const u8, url: []const u8) ![]u8 {
    const bytes = try http.getBytes(ctx, url);
    defer ctx.allocator.free(bytes);

    const temp_dir = try fs.tempDir(ctx, prefix);
    errdefer deleteTreeWarning(ctx, temp_dir);
    defer ctx.allocator.free(temp_dir);
    const script = try std.fs.path.join(ctx.allocator, &.{ temp_dir, file_name });
    errdefer ctx.allocator.free(script);

    try fs.writeExecutableFile(ctx.io, script, bytes);
    return script;
}

fn removeDownloadedScript(ctx: *Context, script: []u8) void {
    defer ctx.allocator.free(script);
    const dir = std.fs.path.dirname(script) orelse return;
    deleteTreeWarning(ctx, dir);
}

fn deleteTreeWarning(ctx: *Context, dir: []const u8) void {
    common.fs.deleteTreeWarning(ctx.io, "temporary installer directory", dir);
}

fn executableName(ctx: *Context, name: []const u8) ![]u8 {
    if (builtin.os.tag == .windows and std.fs.path.extension(name).len == 0) {
        return std.fmt.allocPrint(ctx.allocator, "{s}.exe", .{name});
    }
    return ctx.allocator.dupe(u8, name);
}

fn testingContext(env: *std.process.Environ.Map, home: []const u8) Context {
    return .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = env,
        .home = home,
        .bin_dir = "",
        .opt_dir = "",
    };
}

fn testingToolchain() manifest.Toolchain {
    return .{
        .manager_bin = "rustup",
        .name = "stable",
        .name_env = "BOOTSTRAP_RUST_TOOLCHAIN",
        .bin_dir = .{ .env_var = "CARGO_HOME", .home_relative = ".cargo/bin" },
        .components = &.{ "rustfmt", "clippy" },
        .install = .{
            .unix = .{
                .url = "https://sh.rustup.rs",
                .file = "install.sh",
                .argv = &.{ "sh", "{file}", "-y", "--default-toolchain", "{toolchain}", "{components}" },
            },
            .windows = .{
                .url = "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe",
                .file = "rustup-init.exe",
                .argv = &.{ "{file}", "-y", "--default-toolchain", "{toolchain}", "{components}" },
            },
        },
        .update_argv = &.{
            "{manager_bin}",
            "toolchain",
            "install",
            "{toolchain}",
            "--profile",
            "minimal",
            "{components}",
        },
        .active_argv = &.{ "{manager_bin}", "show", "active-toolchain" },
        .default_argv = &.{ "{manager_bin}", "default", "{toolchain}" },
        .component_argv = &.{ "--component", "{component}" },
    };
}

test "rustup argv templates expand requested components" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env, "/home/me");

    const argv = try renderToolchainArgv(&ctx, testingToolchain(), testingToolchain().update_argv, .{
        .manager_bin = "rustup",
        .toolchain = "stable",
    });
    defer freeArgv(&ctx, argv);

    try std.testing.expectEqualStrings("rustup", argv[0]);
    try std.testing.expectEqualStrings("toolchain", argv[1]);
    try std.testing.expectEqualStrings("stable", argv[3]);
    try std.testing.expectEqualStrings("--component", argv[6]);
    try std.testing.expectEqualStrings("rustfmt", argv[7]);
    try std.testing.expectEqualStrings("clippy", argv[9]);
}

test "toolchainBinDir honors env override and defaults under home" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env, "/home/me");

    const default_bin = try toolchainBinDir(&ctx, testingToolchain());
    defer ctx.allocator.free(default_bin);
    try std.testing.expectEqualStrings("/home/me/.cargo/bin", default_bin);

    try env.put("CARGO_HOME", "/cargo");
    const custom_bin = try toolchainBinDir(&ctx, testingToolchain());
    defer ctx.allocator.free(custom_bin);
    try std.testing.expectEqualStrings("/cargo/bin", custom_bin);
}

test "rustup executable name follows host executable suffix" {
    const expected = if (builtin.os.tag == .windows) "rustup.exe" else "rustup";
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env, "/home/me");

    const rustup_name = try executableName(&ctx, "rustup");
    defer ctx.allocator.free(rustup_name);
    try std.testing.expectEqualStrings(expected, rustup_name);
}

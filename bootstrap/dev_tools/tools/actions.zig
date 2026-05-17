const std = @import("std");
const builtin = @import("builtin");
const bootstrap = @import("bootstrap");
const common = @import("common");

const Context = bootstrap.Context;
const fs = common.fs;
const model = bootstrap.manifest;
const output = common.output;
const proc = common.process;

pub fn install(ctx: *Context, tool: model.Tool) !void {
    switch (tool.action.type) {
        .required => return error.BootstrapPrerequisite,
        .script => try installScript(ctx, tool.name, tool.action.script orelse return error.JsonFieldMissing),
        .toolchain => try installToolchain(ctx, tool.action.toolchain orelse return error.JsonFieldMissing),
        .package => try installPackage(ctx, tool.action.package orelse return error.JsonFieldMissing),
        .build => try installBuild(ctx, tool.name, tool.action.build orelse return error.JsonFieldMissing),
        .archive => {
            const spec = try bootstrap.manifest.toArchiveSpec(ctx, tool);
            defer ctx.allocator.free(spec.links);
            defer ctx.allocator.free(spec.app_links);
            try spec.install(ctx);
        },
    }
}

fn installScript(ctx: *Context, name: []const u8, script: model.Script) !void {
    const command = if (builtin.os.tag == .windows) script.windows else script.unix;
    const selected = command orelse return error.UnsupportedPlatform;

    const downloaded = try downloadFile(ctx, name, selected.file, selected.url);
    defer removeDownloadedScript(ctx, downloaded);
    const argv = try expandArgv(ctx, selected.argv, downloaded);
    defer freeArgv(ctx, argv);
    try proc.run(ctx, argv);
}

fn installToolchain(ctx: *Context, toolchain: model.Toolchain) !void {
    return switch (toolchain.manager) {
        .rustup => bootstrap.rust.installOrUpdate(ctx, toolchain),
    };
}

fn installPackage(ctx: *Context, package: model.Package) !void {
    return switch (package.manager) {
        .uv => proc.run(ctx, &.{ "uv", "tool", "install", "--upgrade", package.name }),
    };
}

fn installBuild(ctx: *Context, name: []const u8, build: model.Build) !void {
    return switch (build.system) {
        .zig => installZigBuild(ctx, name, build.path),
    };
}

fn installZigBuild(ctx: *Context, name: []const u8, relative_path: []const u8) !void {
    const root = try repoRoot(ctx);
    defer ctx.allocator.free(root);
    const build_dir = try std.fs.path.join(ctx.allocator, &.{ root, relative_path });
    defer ctx.allocator.free(build_dir);
    const prefix = try std.fs.path.join(ctx.allocator, &.{ ctx.opt_dir, name, "latest" });
    defer ctx.allocator.free(prefix);

    const zig = ctx.env.get("BOOTSTRAP_ZIG_EXE") orelse "zig";
    try proc.runInCwd(ctx, .{ .path = build_dir }, &.{ zig, "build", "install", "--prefix", prefix });

    const bin_name = try exeName(ctx, name);
    defer ctx.allocator.free(bin_name);
    const target = try std.fs.path.join(ctx.allocator, &.{ prefix, "bin", bin_name });
    defer ctx.allocator.free(target);
    try bootstrap.links.managed(ctx, name, target, bin_name);
}

fn repoRoot(ctx: *Context) ![]u8 {
    if (ctx.env.get("BOOTSTRAP_REPO_DIR")) |path| return ctx.allocator.dupe(u8, path);
    return std.process.currentPathAlloc(ctx.io, ctx.allocator);
}

fn downloadScript(ctx: *Context, prefix: []const u8, url: []const u8) ![]u8 {
    return downloadFile(ctx, prefix, "install.sh", url);
}

fn downloadFile(ctx: *Context, prefix: []const u8, file_name: []const u8, url: []const u8) ![]u8 {
    const bytes = try bootstrap.http.getBytes(ctx, url);
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

fn expandArgv(ctx: *Context, templates: []const []const u8, file: []const u8) ![]const []const u8 {
    return common.template.Template.renderSlice(ctx.allocator, templates, .{
        .file = file,
        .bin_dir = ctx.bin_dir,
        .opt_dir = ctx.opt_dir,
        .home = ctx.home,
    });
}

fn freeArgv(ctx: *Context, argv: []const []const u8) void {
    common.template.freeSlice(ctx.allocator, argv);
}

fn expandArg(ctx: *Context, template: []const u8, file: []const u8) ![]u8 {
    return common.template.Template.literal(template).render(ctx.allocator, .{
        .file = file,
        .bin_dir = ctx.bin_dir,
        .opt_dir = ctx.opt_dir,
        .home = ctx.home,
    });
}

fn deleteTreeWarning(ctx: *Context, dir: []const u8) void {
    std.Io.Dir.cwd().deleteTree(ctx.io, dir) catch |err| {
        output.stderr(ctx.io, "warning: failed to delete temporary installer directory {s}: {s}\n", .{
            dir,
            @errorName(err),
        }) catch return;
    };
}

fn exeName(ctx: *Context, name: []const u8) ![]u8 {
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

test "script argv templates expand bootstrap paths" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env, "/home/me");
    ctx.bin_dir = "/home/me/.local/bin";
    ctx.opt_dir = "/home/me/.local/opt";

    const argv = try expandArgv(&ctx, &.{ "sh", "{file}", "-b", "{bin_dir}", "--home={home}" }, "/tmp/install.sh");
    defer freeArgv(&ctx, argv);

    try std.testing.expectEqualStrings("sh", argv[0]);
    try std.testing.expectEqualStrings("/tmp/install.sh", argv[1]);
    try std.testing.expectEqualStrings("/home/me/.local/bin", argv[3]);
    try std.testing.expectEqualStrings("--home=/home/me", argv[4]);
}

test "script argv templates reject unknown placeholders" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env, "/home/me");

    try std.testing.expectError(error.UnknownTemplateVariable, expandArg(&ctx, "{unknown}", "/tmp/install.sh"));
}

test "exeName adds Windows extensions only on Windows" {
    const expected = if (builtin.os.tag == .windows) "tool.exe" else "tool";
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env, "/home/me");

    const tool_name = try exeName(&ctx, "tool");
    defer ctx.allocator.free(tool_name);
    try std.testing.expectEqualStrings(expected, tool_name);

    const existing = try exeName(&ctx, "tool.exe");
    defer ctx.allocator.free(existing);
    try std.testing.expectEqualStrings("tool.exe", existing);
}

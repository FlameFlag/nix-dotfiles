const std = @import("std");
const builtin = @import("builtin");
const bootstrap = @import("bootstrap");
const common = @import("common");

const Context = bootstrap.Context;
const fs = common.fs;
const model = bootstrap.manifest;
const output = common.output;
const plan_model = bootstrap.plan;
const proc = common.process;

pub fn install(ctx: *Context, plan: plan_model.InstallPlan) !void {
    const tool = plan.tool;
    switch (plan.action) {
        .required => return error.BootstrapPrerequisite,
        .script => |script_spec| try installScript(ctx, tool.name, script_spec),
        .toolchain => |toolchain_spec| try bootstrap.toolchain.installOrUpdate(ctx, toolchain_spec),
        .package => |package_spec| try installPackage(ctx, package_spec),
        .build => |build_spec| try installBuildCommand(ctx, tool, build_spec),
        .source_build => |source_build| try installSourceBuild(ctx, tool, source_build),
        .archive => |archive_spec| try archive_spec.install(ctx),
    }
}

fn installPackage(ctx: *Context, package_spec: model.Package) !void {
    try installCommand(ctx, package_spec.install_argv, .{
        .package = package_spec.name,
    });
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

fn installBuildCommand(ctx: *Context, tool: model.Tool, build: model.Build) !void {
    const root = try repoRoot(ctx);
    defer ctx.allocator.free(root);
    const build_dir = try std.fs.path.join(ctx.allocator, &.{ root, build.path });
    defer ctx.allocator.free(build_dir);
    const prefix = try std.fs.path.join(ctx.allocator, &.{ ctx.opt_dir, tool.name, "latest" });
    defer ctx.allocator.free(prefix);

    const argv = try common.template.Template.renderSlice(ctx.allocator, build.argv, .{
        .repo_dir = root,
        .build_dir = build_dir,
        .prefix = prefix,
        .tool = tool.name,
        .zig = ctx.env.get("BOOTSTRAP_ZIG_EXE") orelse "zig",
    });
    defer common.template.freeSlice(ctx.allocator, argv);
    try proc.runInCwd(ctx, .{ .path = build_dir }, argv);

    if (build.links.len != 0) {
        for (build.links) |link| {
            const target = try std.fs.path.join(ctx.allocator, &.{ prefix, link.path });
            defer ctx.allocator.free(target);
            try bootstrap.links.managed(ctx, tool.name, target, link.name);
        }
        return;
    }

    for (tool.bins) |bin| {
        const bin_name = try exeName(ctx, bin.name);
        defer ctx.allocator.free(bin_name);
        const target = try std.fs.path.join(ctx.allocator, &.{ prefix, "bin", bin_name });
        defer ctx.allocator.free(target);
        try bootstrap.links.managed(ctx, tool.name, target, bin_name);
    }
}

fn installSourceBuild(ctx: *Context, tool: model.Tool, source_build: model.SourceBuild) !void {
    const install_dir = try bootstrap.links.installDirPath(ctx, tool.name, source_build.version);
    defer ctx.allocator.free(install_dir);
    const temp_install_dir = try std.fmt.allocPrint(ctx.allocator, "{s}.tmp", .{install_dir});
    defer ctx.allocator.free(temp_install_dir);

    const work_dir = try fs.tempDir(ctx, "bootstrap-source-build");
    defer {
        deleteTreeWarning(ctx, work_dir);
        ctx.allocator.free(work_dir);
    }

    const archive_path = try std.fs.path.join(ctx.allocator, &.{ work_dir, source_build.archive_file });
    defer ctx.allocator.free(archive_path);
    const source_dir = try std.fs.path.join(ctx.allocator, &.{ work_dir, "source" });
    defer ctx.allocator.free(source_dir);

    const url = try common.template.Template.literal(source_build.url).render(ctx.allocator, .{
        .version = source_build.version,
        .tool = tool.name,
    });
    defer ctx.allocator.free(url);

    try bootstrap.http.downloadFile(ctx, url, archive_path);
    try bootstrap.archive.extractFile(ctx, archive_path, source_dir, source_build.kind, source_build.strip_components);

    deleteTreeIfPresent(ctx, temp_install_dir) catch |err| return err;
    errdefer deleteTreeWarning(ctx, temp_install_dir);

    const argv = try common.template.Template.renderSlice(ctx.allocator, source_build.argv, .{
        .source_dir = source_dir,
        .prefix = temp_install_dir,
        .tool = tool.name,
        .zig = ctx.env.get("BOOTSTRAP_ZIG_EXE") orelse "zig",
    });
    defer common.template.freeSlice(ctx.allocator, argv);
    try proc.runInCwd(ctx, .{ .path = source_dir }, argv);

    try deleteTreeIfPresent(ctx, install_dir);
    try std.Io.Dir.renameAbsolute(temp_install_dir, install_dir, ctx.io);

    for (source_build.links) |link| {
        const rendered_path = try common.template.Template.literal(link.path).render(ctx.allocator, .{
            .version = source_build.version,
            .tool = tool.name,
        });
        defer ctx.allocator.free(rendered_path);
        const target = try std.fs.path.join(ctx.allocator, &.{ install_dir, rendered_path });
        defer ctx.allocator.free(target);
        try bootstrap.links.managed(ctx, tool.name, target, link.name);
    }
}

fn installCommand(ctx: *Context, templates: []const []const u8, bindings: common.template.Bindings) !void {
    const argv = try common.template.Template.renderSlice(ctx.allocator, templates, bindings);
    defer common.template.freeSlice(ctx.allocator, argv);
    try proc.run(ctx, argv);
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

fn deleteTreeIfPresent(ctx: *Context, dir: []const u8) !void {
    std.Io.Dir.cwd().access(ctx.io, dir, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    try std.Io.Dir.cwd().deleteTree(ctx.io, dir);
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

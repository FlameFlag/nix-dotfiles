const std = @import("std");
const builtin = @import("builtin");
const bootstrap = @import("bootstrap");
const common = @import("common");

const Context = bootstrap.Context;
const fs = common.fs;
const model = bootstrap.manifest;
const output = common.output;
const proc = common.process;
const nix_os_release_path = "/etc/os-release";

pub fn install(ctx: *Context, tool: model.Tool) !void {
    switch (tool.action) {
        .required => return error.BootstrapPrerequisite,
        .script => |script_spec| try installScript(ctx, tool.name, script_spec),
        .toolchain => |toolchain_spec| try bootstrap.rust.installOrUpdate(ctx, toolchain_spec),
        .package => |package_spec| try installPackage(ctx, package_spec),
        .build => |build_spec| try installBuildCommand(ctx, tool, build_spec),
        .archive => {
            const spec = try bootstrap.manifest.toArchiveSpec(ctx, tool);
            defer ctx.allocator.free(spec.links);
            defer ctx.allocator.free(spec.app_links);
            try spec.install(ctx);
        },
    }
}

fn installPackage(ctx: *Context, package_spec: model.Package) !void {
    if (try installUvPackageViaNixPython(ctx, package_spec)) return;

    try installCommand(ctx, package_spec.install_argv, .{
        .package = package_spec.name,
    });
}

fn installUvPackageViaNixPython(ctx: *Context, package_spec: model.Package) !bool {
    if (package_spec.inventory != .uv) return false;
    if (!try shouldUseNixPython(ctx)) return false;

    const uv_path = try proc.pathOf(ctx, "uv") orelse return false;
    defer ctx.allocator.free(uv_path);

    try proc.run(ctx, &.{
        "nix",
        "shell",
        "nixpkgs#python3",
        "--command",
        uv_path,
        "tool",
        "install",
        "--upgrade",
        "--python",
        "python3",
        package_spec.name,
    });
    return true;
}

fn shouldUseNixPython(ctx: *Context) !bool {
    if (builtin.os.tag != .linux) return false;
    if (!try proc.hasBin(ctx, "nix")) return false;
    return isNixOs(ctx);
}

fn isNixOs(ctx: *Context) !bool {
    var buffer: [4096]u8 = undefined;
    const contents = std.Io.Dir.cwd().readFile(ctx.io, nix_os_release_path, &buffer) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return false,
        else => return err,
    };
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "ID=nixos")) return true;
    }
    return false;
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

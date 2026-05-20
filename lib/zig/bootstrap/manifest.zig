const std = @import("std");
const common = @import("common");

const archive_lib = @import("archive.zig");
const Context = @import("context.zig").Context;
const install_archive = @import("install.zig");
const platform = @import("platform.zig");

const output = common.output;

pub const Policy = enum { install_missing, update_all };
pub const Phase = enum { prerequisites, archives, packages, builds };
pub const HostOs = platform.Os;
pub const HostArch = platform.Arch;
pub const HostRequirement = enum { lenovo_laptop, not_nixos };
pub const ArchiveKind = archive_lib.Kind;

pub const Catalog = struct {
    tools: []const Tool,

    pub fn deinit(self: *Catalog, ctx: *Context) void {
        _ = ctx;
        self.* = undefined;
    }
};

pub const Tool = struct {
    name: []const u8,
    bins: []const Bin,
    platforms: ?[]const HostOs = null,
    requires: ?[]const HostRequirement = null,
    phase_override: ?Phase = null,
    action: Action,

    pub const Action = union(enum) {
        required,
        archive: Archive,
        package: Package,
        build: Build,
        script: Script,
        toolchain: Toolchain,
    };

    pub fn isRequired(self: Tool) bool {
        return switch (self.action) {
            .required => true,
            else => false,
        };
    }

    pub fn phase(self: Tool) Phase {
        if (self.phase_override) |install_phase| return install_phase;
        return switch (self.action) {
            .required, .script, .toolchain => .prerequisites,
            .archive => .archives,
            .package => .packages,
            .build => .builds,
        };
    }

    pub fn sourceLabel(self: Tool, managed: bool) []const u8 {
        return switch (self.action) {
            .required => if (managed) "bootstrap-managed" else "bootstrap-required",
            .archive, .package, .build, .script, .toolchain => if (managed) "bootstrap-managed" else "external",
        };
    }

    pub fn usesScriptInstaller(self: Tool) bool {
        return switch (self.action) {
            .script => true,
            else => false,
        };
    }

    pub fn usesBuildInstaller(self: Tool) bool {
        return switch (self.action) {
            .build => true,
            else => false,
        };
    }

    pub fn managedRoot(self: Tool, ctx: *Context) !?[]u8 {
        return switch (self.action) {
            .required, .archive, .build => try std.fs.path.join(ctx.allocator, &.{ ctx.opt_dir, self.name }),
            .package, .script, .toolchain => null,
        };
    }
};

pub const Bin = struct {
    name: []const u8,
    version_argv: []const []const u8,
};

pub const Archive = struct {
    source: ?Source = null,
    platforms: []const ArchivePlatform,
};

pub const Source = union(enum) {
    github_latest: GithubLatestSource,
    direct: DirectSource,
    command: CommandSource,
    node_latest: NodeLatestSource,
};

pub const GithubLatestSource = struct {
    repo: []const u8,
    tag_prefix: []const u8 = "",
    asset: []const u8,
};

pub const DirectSource = struct {
    version: []const u8,
    url: []const u8,
};

pub const CommandSource = struct {
    argv: []const []const u8,
    url: []const u8,
};

pub const NodeLatestSource = struct {
    index_url: []const u8,
    url: []const u8,
};

pub const Package = struct {
    name: []const u8,
    install_argv: []const []const u8,
    inventory: ?Inventory = null,

    pub const Inventory = enum { uv };
};

pub const Build = struct {
    path: []const u8,
    argv: []const []const u8,
    links: []const Link,
};

pub const Script = struct {
    unix: ?Command = null,
    windows: ?Command = null,

    pub const Command = struct {
        url: []const u8,
        file: []const u8,
        argv: []const []const u8,
    };
};

pub const Toolchain = struct {
    manager_bin: []const u8,
    name: []const u8,
    name_env: ?[]const u8 = null,
    bin_dir: BinDir,
    components: []const []const u8,
    install: Install,
    update_argv: []const []const u8,
    active_argv: []const []const u8,
    default_argv: []const []const u8,
    component_argv: []const []const u8,

    pub const BinDir = struct {
        env_var: ?[]const u8 = null,
        home_relative: []const u8,
    };

    pub const Install = struct {
        unix: ?Command = null,
        windows: ?Command = null,

        pub const Command = struct {
            url: []const u8,
            file: []const u8,
            argv: []const []const u8,
        };
    };
};

pub const Link = struct {
    name: []const u8,
    path: []const u8,
};

pub const ArchivePlatform = struct {
    when: platform.Predicate,
    platform: []const u8,
    source: ?Source = null,
    kind: archive_lib.Kind,
    strip_components: u32,
    links: []const Link,
    app_links: []const Link = &.{},
};

pub fn bin(name: []const u8, version_argv: []const []const u8) Bin {
    return .{ .name = name, .version_argv = version_argv };
}

pub fn tool(name: []const u8, bins: []const Bin, action: Tool.Action) Tool {
    return .{ .name = name, .bins = bins, .action = action };
}

pub fn required() Tool.Action {
    return .required;
}

pub fn archive(source: ?Source, platforms: []const ArchivePlatform) Tool.Action {
    return .{ .archive = .{ .source = source, .platforms = platforms } };
}

pub fn package(package_name: []const u8, install_argv: []const []const u8, inventory: ?Package.Inventory) Tool.Action {
    return .{ .package = .{ .name = package_name, .install_argv = install_argv, .inventory = inventory } };
}

pub fn uvPackage(package_name: []const u8) Tool.Action {
    return package(package_name, &.{ "uv", "tool", "install", "--upgrade", "{package}" }, .uv);
}

pub fn zigBuild(path: []const u8) Tool.Action {
    return .{ .build = .{
        .path = path,
        .argv = &.{ "{zig}", "build", "install", "--prefix", "{prefix}" },
        .links = &.{},
    } };
}

pub fn script(unix: ?Script.Command, windows: ?Script.Command) Tool.Action {
    return .{ .script = .{ .unix = unix, .windows = windows } };
}

pub fn scriptCommand(url: []const u8, file: []const u8, argv: []const []const u8) Script.Command {
    return .{ .url = url, .file = file, .argv = argv };
}

pub fn rustupToolchain(spec: Toolchain) Tool.Action {
    return .{ .toolchain = spec };
}

pub fn githubLatest(repo: []const u8, tag_prefix: []const u8, asset: []const u8) Source {
    return .{ .github_latest = .{ .repo = repo, .tag_prefix = tag_prefix, .asset = asset } };
}

pub fn direct(version: []const u8, url: []const u8) Source {
    return .{ .direct = .{ .version = version, .url = url } };
}

pub fn commandSource(argv: []const []const u8, url: []const u8) Source {
    return .{ .command = .{ .argv = argv, .url = url } };
}

pub fn nodeLatest(index_url: []const u8, url: []const u8) Source {
    return .{ .node_latest = .{ .index_url = index_url, .url = url } };
}

pub fn link(name: []const u8, path: []const u8) Link {
    return .{ .name = name, .path = path };
}

pub fn archivePlatform(
    when: platform.Predicate,
    platform_name: []const u8,
    kind: archive_lib.Kind,
    strip_components: u32,
    links: []const Link,
    app_links: []const Link,
) ArchivePlatform {
    return .{
        .when = when,
        .platform = platform_name,
        .kind = kind,
        .strip_components = strip_components,
        .links = links,
        .app_links = app_links,
    };
}

pub fn host(os: HostOs, arch: HostArch) platform.Predicate {
    return .{ .os = os, .arch = arch };
}

pub fn macosAarch64() platform.Predicate {
    return host(.macos, .aarch64);
}

pub fn linuxAarch64() platform.Predicate {
    return host(.linux, .aarch64);
}

pub fn linuxX8664() platform.Predicate {
    return host(.linux, .x86_64);
}

pub fn windowsX8664() platform.Predicate {
    return host(.windows, .x86_64);
}

pub fn validate(ctx: *Context, catalog: Catalog) !void {
    try validateTools(ctx, catalog.tools);
}

fn validateTools(ctx: *Context, tools: []const Tool) !void {
    if (tools.len == 0) return fail("tools: must not be empty", ctx, .{});

    var seen_tools = std.StringHashMap(usize).init(ctx.allocator);
    defer seen_tools.deinit();
    var seen_bins = std.StringHashMap(BinLocation).init(ctx.allocator);
    defer seen_bins.deinit();

    for (tools, 0..) |tool_entry, tool_index| {
        try validateTool(ctx, tool_entry, tool_index);

        if (seen_tools.get(tool_entry.name)) |first_index| {
            return fail(
                "tools[{d}].name: duplicate tool name also used by tools[{d}]",
                ctx,
                .{ tool_index, first_index },
            );
        }
        try seen_tools.put(tool_entry.name, tool_index);

        for (tool_entry.bins, 0..) |bin_entry, bin_index| {
            if (seen_bins.get(bin_entry.name)) |first| {
                return fail(
                    "tools[{d}].bins[{d}].name: duplicate bin name also used by tools[{d}].bins[{d}]",
                    ctx,
                    .{ tool_index, bin_index, first.tool_index, first.bin_index },
                );
            }
            try seen_bins.put(bin_entry.name, .{ .tool_index = tool_index, .bin_index = bin_index });
        }
    }
}

pub fn selectArchivePlatform(cases: []const ArchivePlatform) !ArchivePlatform {
    const current_host = platform.current();
    for (cases) |case| {
        if (current_host.matches(case.when)) return case;
    }
    return error.UnsupportedPlatform;
}

pub fn toArchiveSpec(ctx: *Context, tool_entry: Tool) !install_archive.ArchiveSpec {
    const archive_spec = switch (tool_entry.action) {
        .archive => |payload| payload,
        else => return error.WrongActionType,
    };
    const selected = try selectArchivePlatform(archive_spec.platforms);
    const spec_links = try ctx.allocator.alloc(install_archive.Link, selected.links.len);
    errdefer ctx.allocator.free(spec_links);
    for (selected.links, spec_links) |link_entry, *spec_link| {
        spec_link.* = .{ .name = link_entry.name, .path = .literal(link_entry.path) };
    }

    const app_links = try ctx.allocator.alloc(install_archive.Link, selected.app_links.len);
    errdefer ctx.allocator.free(app_links);
    for (selected.app_links, app_links) |link_entry, *app_link| {
        app_link.* = .{ .name = link_entry.name, .path = .literal(link_entry.path) };
    }

    const source = selected.source orelse archive_spec.source orelse return error.MissingArchiveSource;
    return .{
        .tool = tool_entry.name,
        .source = try archiveSource(source),
        .platform = selected.platform,
        .kind = selected.kind,
        .strip_components = selected.strip_components,
        .links = spec_links,
        .app_links = app_links,
    };
}

const BinLocation = struct {
    tool_index: usize,
    bin_index: usize,
};

fn validateTool(ctx: *Context, tool_entry: Tool, tool_index: usize) !void {
    if (tool_entry.name.len == 0) return fail("tools[{d}].name: must not be empty", ctx, .{tool_index});
    if (tool_entry.bins.len == 0) return fail("tools[{d}].bins: must not be empty", ctx, .{tool_index});
    for (tool_entry.bins, 0..) |bin_entry, bin_index| {
        if (bin_entry.name.len == 0) {
            return fail("tools[{d}].bins[{d}].name: must not be empty", ctx, .{ tool_index, bin_index });
        }
        if (bin_entry.version_argv.len == 0) {
            return fail(
                "tools[{d}].bins[{d}].version_argv: must not be empty",
                ctx,
                .{ tool_index, bin_index },
            );
        }
        for (bin_entry.version_argv, 0..) |arg, arg_index| {
            if (arg.len == 0) {
                return fail(
                    "tools[{d}].bins[{d}].version_argv[{d}]: must not be empty",
                    ctx,
                    .{ tool_index, bin_index, arg_index },
                );
            }
        }
    }

    switch (tool_entry.action) {
        .required => {},
        .archive => |archive_action| try validateArchiveAction(ctx, archive_action, tool_index),
        .package => |package_spec| {
            if (package_spec.name.len == 0) {
                return fail(actionPath("package.name") ++ ": must not be empty", ctx, .{tool_index});
            }
            try validateArgv(
                actionPath("package.install_argv"),
                ctx,
                package_spec.install_argv,
                .{tool_index},
                &.{"package"},
            );
        },
        .build => |build_spec| {
            if (build_spec.path.len == 0) {
                return fail(actionPath("build.path") ++ ": must not be empty", ctx, .{tool_index});
            }
            try validateArgv(
                actionPath("build.argv"),
                ctx,
                build_spec.argv,
                .{tool_index},
                &.{ "repo_dir", "build_dir", "prefix", "tool", "zig" },
            );
            try validateLinks(actionPath("build.links"), false, ctx, build_spec.links, .{tool_index});
        },
        .script => |script_spec| try validateScriptAction(ctx, script_spec, tool_index),
        .toolchain => |toolchain| try validateToolchainAction(ctx, toolchain, tool_index),
    }
}

fn actionPath(comptime suffix: []const u8) []const u8 {
    return "tools[{d}].action." ++ suffix;
}

fn validateToolchainAction(ctx: *Context, toolchain: Toolchain, tool_index: usize) !void {
    if (toolchain.manager_bin.len == 0) {
        return fail(actionPath("toolchain.manager_bin") ++ ": must not be empty", ctx, .{tool_index});
    }
    if (toolchain.name.len == 0) {
        return fail(actionPath("toolchain.name") ++ ": must not be empty", ctx, .{tool_index});
    }
    if (toolchain.name_env) |name_env| {
        if (name_env.len == 0) {
            return fail(actionPath("toolchain.name_env") ++ ": must not be empty", ctx, .{tool_index});
        }
    }
    if (toolchain.bin_dir.env_var) |env_var| {
        if (env_var.len == 0) {
            return fail(actionPath("toolchain.bin_dir.env_var") ++ ": must not be empty", ctx, .{tool_index});
        }
    }
    if (toolchain.bin_dir.home_relative.len == 0) {
        return fail(actionPath("toolchain.bin_dir.home_relative") ++ ": must not be empty", ctx, .{tool_index});
    }
    if (toolchain.components.len == 0) {
        return fail(actionPath("toolchain.components") ++ ": must not be empty", ctx, .{tool_index});
    }
    for (toolchain.components, 0..) |component, component_index| {
        if (component.len == 0) {
            return fail(
                actionPath("toolchain.components[{d}]") ++ ": must not be empty",
                ctx,
                .{ tool_index, component_index },
            );
        }
    }
    if (toolchain.install.unix == null and toolchain.install.windows == null) {
        return fail(actionPath("toolchain.install") ++ ": must define unix or windows command", ctx, .{tool_index});
    }
    if (toolchain.install.unix) |command| {
        try validateToolchainInstallCommand(actionPath("toolchain.install.unix"), ctx, command, .{tool_index});
    }
    if (toolchain.install.windows) |command| {
        try validateToolchainInstallCommand(actionPath("toolchain.install.windows"), ctx, command, .{tool_index});
    }
    try validateArgv(
        actionPath("toolchain.update_argv"),
        ctx,
        toolchain.update_argv,
        .{tool_index},
        &.{ "manager_bin", "toolchain", "components" },
    );
    try validateArgv(
        actionPath("toolchain.active_argv"),
        ctx,
        toolchain.active_argv,
        .{tool_index},
        &.{ "manager_bin", "toolchain" },
    );
    try validateArgv(
        actionPath("toolchain.default_argv"),
        ctx,
        toolchain.default_argv,
        .{tool_index},
        &.{ "manager_bin", "toolchain" },
    );
    try validateArgv(
        actionPath("toolchain.component_argv"),
        ctx,
        toolchain.component_argv,
        .{tool_index},
        &.{"component"},
    );
}

fn validateToolchainInstallCommand(
    comptime path_fmt: []const u8,
    ctx: *Context,
    command: Toolchain.Install.Command,
    args: anytype,
) !void {
    if (command.url.len == 0) return fail(path_fmt ++ ".url: must not be empty", ctx, args);
    if (command.file.len == 0) return fail(path_fmt ++ ".file: must not be empty", ctx, args);
    try validateArgv(
        path_fmt ++ ".argv",
        ctx,
        command.argv,
        args,
        &.{ "file", "toolchain", "components" },
    );
}

fn validateArgv(
    comptime path_fmt: []const u8,
    ctx: *Context,
    argv: []const []const u8,
    args: anytype,
    allowed: []const []const u8,
) !void {
    if (argv.len == 0) return fail(path_fmt ++ ": must not be empty", ctx, args);
    for (argv, 0..) |arg, arg_index| {
        if (arg.len == 0) return fail(path_fmt ++ "[{d}]: must not be empty", ctx, args ++ .{arg_index});
        try validateTemplate(path_fmt ++ "[{d}]", ctx, arg, args ++ .{arg_index}, allowed);
    }
}

fn validateArchiveAction(ctx: *Context, archive_spec: Archive, tool_index: usize) !void {
    if (archive_spec.source) |source| try validateSource(actionPath("source"), ctx, source, .{tool_index});
    if (archive_spec.platforms.len == 0) {
        return fail(actionPath("platforms") ++ ": must not be empty", ctx, .{tool_index});
    }
    for (archive_spec.platforms, 0..) |case, platform_index| {
        if (case.platform.len == 0) {
            return fail(
                actionPath("platforms[{d}].platform") ++ ": must not be empty",
                ctx,
                .{ tool_index, platform_index },
            );
        }
        try validateTemplate(
            actionPath("platforms[{d}].platform"),
            ctx,
            case.platform,
            .{ tool_index, platform_index },
            &.{},
        );
        if (case.source) |source| {
            try validateSource(
                actionPath("platforms[{d}].source"),
                ctx,
                source,
                .{ tool_index, platform_index },
            );
        } else if (archive_spec.source == null) {
            return fail(
                actionPath("platforms[{d}].source") ++ ": required when action." ++ "source is missing",
                ctx,
                .{ tool_index, platform_index },
            );
        }
        try validateLinks(
            actionPath("platforms[{d}].links"),
            true,
            ctx,
            case.links,
            .{ tool_index, platform_index },
        );
        try validateLinks(
            actionPath("platforms[{d}].app_links"),
            false,
            ctx,
            case.app_links,
            .{ tool_index, platform_index },
        );
    }
}

fn validateLinks(
    comptime path_fmt: []const u8,
    comptime require_non_empty: bool,
    ctx: *Context,
    entries: []const Link,
    args: anytype,
) !void {
    if (require_non_empty and entries.len == 0) {
        return fail(path_fmt ++ ": must not be empty", ctx, args);
    }
    for (entries, 0..) |link_entry, link_index| {
        if (link_entry.name.len == 0) {
            return fail(path_fmt ++ "[{d}].name: must not be empty", ctx, args ++ .{link_index});
        }
        if (link_entry.path.len == 0) {
            return fail(path_fmt ++ "[{d}].path: must not be empty", ctx, args ++ .{link_index});
        }
        try validateTemplate(
            path_fmt ++ "[{d}].path",
            ctx,
            link_entry.path,
            args ++ .{link_index},
            &.{ "version", "platform" },
        );
    }
}

fn validateScriptAction(ctx: *Context, script_spec: Script, tool_index: usize) !void {
    if (script_spec.unix == null and script_spec.windows == null) {
        return fail(actionPath("script") ++ ": must define unix or windows command", ctx, .{tool_index});
    }
    if (script_spec.unix) |command| {
        try validateScriptCommand(actionPath("script.unix"), ctx, command, .{tool_index});
    }
    if (script_spec.windows) |command| {
        try validateScriptCommand(actionPath("script.windows"), ctx, command, .{tool_index});
    }
}

fn validateScriptCommand(
    comptime path_fmt: []const u8,
    ctx: *Context,
    command: Script.Command,
    args: anytype,
) !void {
    if (command.url.len == 0) return fail(path_fmt ++ ".url: must not be empty", ctx, args);
    if (command.file.len == 0) return fail(path_fmt ++ ".file: must not be empty", ctx, args);
    if (command.argv.len == 0) return fail(path_fmt ++ ".argv: must not be empty", ctx, args);
    for (command.argv, 0..) |arg, arg_index| {
        if (arg.len == 0) return fail(path_fmt ++ ".argv[{d}]: must not be empty", ctx, args ++ .{arg_index});
        try validateTemplate(
            path_fmt ++ ".argv[{d}]",
            ctx,
            arg,
            args ++ .{arg_index},
            &.{ "file", "bin_dir", "opt_dir", "home" },
        );
    }
}

fn validateSource(comptime path_fmt: []const u8, ctx: *Context, source: Source, args: anytype) !void {
    switch (source) {
        .github_latest => |github| {
            if (github.repo.len == 0) return fail(path_fmt ++ ".repo: must not be empty", ctx, args);
            if (github.asset.len == 0) return fail(path_fmt ++ ".asset: must not be empty", ctx, args);
            try validateTemplate(path_fmt ++ ".asset", ctx, github.asset, args, &.{ "version", "platform" });
        },
        .direct => |direct_source| {
            if (direct_source.version.len == 0) return fail(path_fmt ++ ".version: must not be empty", ctx, args);
            if (direct_source.url.len == 0) return fail(path_fmt ++ ".url: must not be empty", ctx, args);
            try validateTemplate(path_fmt ++ ".url", ctx, direct_source.url, args, &.{ "version", "platform" });
        },
        .command => |command_source| {
            if (command_source.argv.len == 0) return fail(path_fmt ++ ".argv: must not be empty", ctx, args);
            if (command_source.url.len == 0) return fail(path_fmt ++ ".url: must not be empty", ctx, args);
            for (command_source.argv, 0..) |arg, arg_index| {
                if (arg.len == 0) {
                    return fail(path_fmt ++ ".argv[{d}]: must not be empty", ctx, args ++ .{arg_index});
                }
            }
            try validateTemplate(path_fmt ++ ".url", ctx, command_source.url, args, &.{ "version", "platform" });
        },
        .node_latest => |node| {
            if (node.index_url.len == 0) return fail(path_fmt ++ ".index_url: must not be empty", ctx, args);
            if (node.url.len == 0) return fail(path_fmt ++ ".url: must not be empty", ctx, args);
            try validateTemplate(path_fmt ++ ".url", ctx, node.url, args, &.{ "version", "platform" });
        },
    }
}

fn validateTemplate(
    comptime path_fmt: []const u8,
    ctx: *Context,
    template: []const u8,
    args: anytype,
    allowed: []const []const u8,
) !void {
    common.template.Template.literal(template).validate(allowed) catch |err| switch (err) {
        error.InvalidTemplate => return fail(path_fmt ++ ": invalid template placeholder", ctx, args),
        error.UnknownTemplateVariable => return fail(path_fmt ++ ": unknown template placeholder", ctx, args),
    };
}

fn archiveSource(input: Source) !install_archive.Source {
    return switch (input) {
        .github_latest => |github| .{ .github_latest = .{
            .repo = github.repo,
            .tag_prefix = github.tag_prefix,
            .asset = .literal(github.asset),
        } },
        .direct => |direct_source| .{ .direct = .{
            .version = direct_source.version,
            .url = .literal(direct_source.url),
        } },
        .command => |command_source| .{ .command = .{
            .argv = command_source.argv,
            .url = .literal(command_source.url),
        } },
        .node_latest => |node| .{ .node_latest = .{
            .index_url = node.index_url,
            .url = .literal(node.url),
        } },
    };
}

fn fail(comptime fmt: []const u8, ctx: *Context, args: anytype) error{InvalidManifest} {
    output.stderr(ctx.io, "error: manifest: " ++ fmt ++ "\n", args) catch return error.InvalidManifest;
    return error.InvalidManifest;
}

fn testingContext(env: *std.process.Environ.Map) Context {
    return .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = env,
        .home = "",
        .bin_dir = "",
        .opt_dir = "",
    };
}

fn testCatalog(tools: []const Tool) Catalog {
    return .{ .tools = tools };
}

test "catalog validation rejects duplicate tool names" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    try std.testing.expectError(error.InvalidManifest, validate(&ctx, testCatalog(&.{
        tool("same", &.{bin("one", &.{"one"})}, required()),
        tool("same", &.{bin("two", &.{"two"})}, required()),
    })));
}

test "catalog validation rejects duplicate bin names" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    try std.testing.expectError(error.InvalidManifest, validate(&ctx, testCatalog(&.{
        tool("one", &.{bin("same", &.{ "same", "--version" })}, required()),
        tool("two", &.{bin("same", &.{ "same", "--version" })}, required()),
    })));
}

test "catalog validation rejects empty argv" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    try std.testing.expectError(error.InvalidManifest, validate(&ctx, testCatalog(&.{
        tool("demo", &.{bin("demo", &.{ "demo", "" })}, required()),
    })));
}

test "archive spec maps manifest links and direct source" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);
    const tool_entry: Tool = .{
        .name = "demo",
        .bins = &.{},
        .action = archive(direct("1.2.3", "https://example.test/demo.tar.gz"), &.{.{
            .when = .{},
            .platform = "demo-platform",
            .kind = .tar_gz,
            .strip_components = 1,
            .links = &.{link("demo", "bin/demo")},
            .app_links = &.{link("Demo.app", "Demo.app")},
        }}),
    };

    const spec = try toArchiveSpec(&ctx, tool_entry);
    defer ctx.allocator.free(spec.links);
    defer ctx.allocator.free(spec.app_links);

    try std.testing.expectEqualStrings("demo", spec.tool);
    try std.testing.expectEqualStrings("demo-platform", spec.platform);
    try std.testing.expectEqual(@as(usize, 1), spec.links.len);
    try std.testing.expectEqualStrings("bin/demo", spec.links[0].path.value);
    try std.testing.expectEqual(@as(usize, 1), spec.app_links.len);
    try std.testing.expectEqualStrings("Demo.app", spec.app_links[0].path.value);
}

test "archive validation checks app link templates" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    try std.testing.expectError(error.InvalidManifest, validate(&ctx, testCatalog(&.{
        tool("demo", &.{bin("demo", &.{ "demo", "--version" })}, archive(
            direct("1.0.0", "https://example.test/demo.tar.gz"),
            &.{.{
                .when = .{},
                .platform = "demo-platform",
                .kind = .tar_gz,
                .strip_components = 1,
                .links = &.{link("demo", "bin/demo")},
                .app_links = &.{link("Demo.app", "{unknown}.app")},
            }},
        )),
    })));
}

test "archive platform source overrides action source" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);
    const tool_entry: Tool = .{
        .name = "demo",
        .bins = &.{},
        .action = archive(direct("base", "https://example.test/base.tar.gz"), &.{.{
            .when = .{},
            .platform = "demo-platform",
            .source = direct("override", "https://example.test/override.zip"),
            .kind = .zip,
            .strip_components = 1,
            .links = &.{link("demo", "bin/demo")},
        }}),
    };

    const spec = try toArchiveSpec(&ctx, tool_entry);
    defer ctx.allocator.free(spec.links);
    defer ctx.allocator.free(spec.app_links);

    switch (spec.source) {
        .direct => |direct_source| {
            try std.testing.expectEqualStrings("override", direct_source.version);
            try std.testing.expectEqualStrings("https://example.test/override.zip", direct_source.url.value);
        },
        else => return error.WrongSourceType,
    }
}

test "tool phase defaults match action type" {
    const package_tool = tool("ruff", &.{bin("ruff", &.{"ruff"})}, uvPackage("ruff"));
    const build_tool = tool(
        "gh-hide-comment",
        &.{bin("gh-hide-comment", &.{"gh-hide-comment"})},
        zigBuild("pkgs/gh-hide-comment"),
    );
    const script_tool = tool("chezmoi", &.{bin("chezmoi", &.{"chezmoi"})}, script(.{
        .url = "https://example.test",
        .file = "install.sh",
        .argv = &.{"{file}"},
    }, null));
    const archive_tool = tool(
        "zls",
        &.{bin("zls", &.{"zls"})},
        archive(direct("1", "https://example.test/zls.tar.gz"), &.{
            archivePlatform(.{}, "any", .tar_gz, 0, &.{link("zls", "zls")}, &.{}),
        }),
    );
    const toolchain_tool = tool("rustup", &.{bin("rustup", &.{"rustup"})}, rustupToolchain(.{
        .manager_bin = "rustup",
        .name = "stable",
        .bin_dir = .{ .env_var = "CARGO_HOME", .home_relative = ".cargo/bin" },
        .components = &.{"rustfmt"},
        .install = .{ .unix = .{
            .url = "https://example.test",
            .file = "install.sh",
            .argv = &.{"{file}"},
        } },
        .update_argv = &.{"{manager_bin}"},
        .active_argv = &.{"{manager_bin}"},
        .default_argv = &.{"{manager_bin}"},
        .component_argv = &.{"{component}"},
    }));
    var override_tool = archive_tool;
    override_tool.phase_override = .prerequisites;

    try std.testing.expectEqual(Phase.prerequisites, requiredTool().phase());
    try std.testing.expectEqual(Phase.prerequisites, script_tool.phase());
    try std.testing.expectEqual(Phase.prerequisites, toolchain_tool.phase());
    try std.testing.expectEqual(Phase.archives, archive_tool.phase());
    try std.testing.expectEqual(Phase.packages, package_tool.phase());
    try std.testing.expectEqual(Phase.builds, build_tool.phase());
    try std.testing.expectEqual(Phase.prerequisites, override_tool.phase());
}

test "source label behavior stays stable" {
    const required_tool = requiredTool();
    try std.testing.expect(required_tool.isRequired());
    try std.testing.expectEqualStrings("bootstrap-required", required_tool.sourceLabel(false));
    try std.testing.expectEqualStrings("bootstrap-managed", required_tool.sourceLabel(true));

    const package_tool = tool("ruff", &.{bin("ruff", &.{"ruff"})}, uvPackage("ruff"));
    try std.testing.expectEqualStrings("external", package_tool.sourceLabel(false));
    try std.testing.expectEqualStrings("bootstrap-managed", package_tool.sourceLabel(true));
}

fn requiredTool() Tool {
    return tool("zig", &.{bin("zig", &.{ "zig", "version" })}, required());
}

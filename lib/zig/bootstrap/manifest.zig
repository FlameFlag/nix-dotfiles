const std = @import("std");
const common = @import("common");

const archive = @import("archive.zig");
const Context = @import("context.zig").Context;
const install_archive = @import("install.zig");
const platform = @import("platform.zig");

const output = common.output;
const tools_json_limit = 1024 * 1024;

pub const Policy = enum { install_missing, update_all };
pub const Phase = enum { prerequisites, archives, packages, builds };
pub const HostOs = platform.Os;
pub const HostArch = platform.Arch;
pub const HostRequirement = enum { lenovo_laptop };

pub const Catalog = struct {
    json: []u8,
    parsed: std.json.Parsed(ManifestJson),

    pub fn deinit(self: *Catalog, ctx: *Context) void {
        self.parsed.deinit();
        ctx.allocator.free(self.json);
        self.* = undefined;
    }
};

pub const ManifestJson = struct {
    @"$schema": ?[]const u8 = null,
    tools: []const Tool,
};

pub const Tool = struct {
    name: []const u8,
    bins: []const Bin,
    platforms: ?[]const HostOs = null,
    requires: ?[]const HostRequirement = null,
    action: Action,

    pub const Action = struct {
        type: Type,
        phase: ?Phase = null,
        package: ?Package = null,
        build: ?Build = null,
        script: ?Script = null,
        toolchain: ?Toolchain = null,
        source: ?Source = null,
        platforms: ?[]const ArchivePlatform = null,

        pub const Type = enum { required, archive, package, build, script, toolchain };
    };

    pub fn isRequired(self: Tool) bool {
        return self.action.type == .required;
    }

    pub fn phase(self: Tool) Phase {
        if (self.action.phase) |install_phase| return install_phase;
        return switch (self.action.type) {
            .required, .script, .toolchain => .prerequisites,
            .archive => .archives,
            .package => .packages,
            .build => .builds,
        };
    }

    pub fn sourceLabel(self: Tool, managed: bool) []const u8 {
        return switch (self.action.type) {
            .required => if (managed) "bootstrap-managed" else "bootstrap-required",
            .archive, .package, .build, .script, .toolchain => if (managed) "bootstrap-managed" else "external",
        };
    }

    pub fn usesPackageManager(self: Tool, manager: Package.Manager) bool {
        if (self.action.type != .package) return false;
        const package = self.action.package orelse return false;
        return package.manager == manager;
    }

    pub fn usesToolchainManager(self: Tool, manager: Toolchain.Manager) bool {
        if (self.action.type != .toolchain) return false;
        const toolchain = self.action.toolchain orelse return false;
        return toolchain.manager == manager;
    }

    pub fn usesScriptInstaller(self: Tool) bool {
        return self.action.type == .script;
    }

    pub fn usesBuildSystem(self: Tool, system: Build.System) bool {
        if (self.action.type != .build) return false;
        const build = self.action.build orelse return false;
        return build.system == system;
    }

    pub fn managedRoot(self: Tool, ctx: *Context) !?[]u8 {
        return switch (self.action.type) {
            .required, .archive, .build => try std.fs.path.join(ctx.allocator, &.{ ctx.opt_dir, self.name }),
            .package, .script, .toolchain => null,
        };
    }
};

pub const Bin = struct {
    name: []const u8,
    version_argv: []const []const u8,
};

pub const Source = struct {
    type: Type,
    repo: ?[]const u8 = null,
    tag_prefix: []const u8 = "",
    asset: ?[]const u8 = null,
    version: ?[]const u8 = null,
    url: ?[]const u8 = null,
    argv: ?[]const []const u8 = null,
    index_url: ?[]const u8 = null,

    pub const Type = enum { github_latest, direct, command, node_latest };
};

pub const Package = struct {
    manager: Manager,
    name: []const u8,

    pub const Manager = enum { uv };
};

pub const Build = struct {
    system: System = .zig,
    path: []const u8,

    pub const System = enum { zig };
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
    manager: Manager,
    name: []const u8,
    components: []const []const u8,
    install: Install,
    update_argv: []const []const u8,
    active_argv: []const []const u8,
    default_argv: []const []const u8,
    component_argv: []const []const u8,

    pub const Manager = enum { rustup };

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
    kind: archive.Kind,
    strip_components: u32,
    links: []const Link,
    app_links: []const Link = &.{},
};

pub fn loadPath(ctx: *Context, path: []const u8) !Catalog {
    const json = try std.Io.Dir.cwd().readFileAlloc(ctx.io, path, ctx.allocator, .limited(tools_json_limit));
    errdefer ctx.allocator.free(json);

    const parsed = try std.json.parseFromSlice(ManifestJson, ctx.allocator, json, .{});
    errdefer parsed.deinit();
    try validate(ctx, parsed.value);
    return .{ .json = json, .parsed = parsed };
}

pub fn validate(ctx: *Context, manifest: ManifestJson) !void {
    if (manifest.tools.len == 0) return fail("tools: must not be empty", ctx, .{});

    var seen_tools = std.StringHashMap(usize).init(ctx.allocator);
    defer seen_tools.deinit();
    var seen_bins = std.StringHashMap(BinLocation).init(ctx.allocator);
    defer seen_bins.deinit();

    for (manifest.tools, 0..) |tool, tool_index| {
        try validateTool(ctx, tool, tool_index);

        if (seen_tools.get(tool.name)) |first_index| {
            return fail(
                "tools[{d}].name: duplicate tool name also used by tools[{d}]",
                ctx,
                .{ tool_index, first_index },
            );
        }
        try seen_tools.put(tool.name, tool_index);

        for (tool.bins, 0..) |bin, bin_index| {
            if (seen_bins.get(bin.name)) |first| {
                return fail(
                    "tools[{d}].bins[{d}].name: duplicate bin name also used by tools[{d}].bins[{d}]",
                    ctx,
                    .{ tool_index, bin_index, first.tool_index, first.bin_index },
                );
            }
            try seen_bins.put(bin.name, .{ .tool_index = tool_index, .bin_index = bin_index });
        }
    }
}

pub fn selectArchivePlatform(cases: []const ArchivePlatform) !ArchivePlatform {
    const host = platform.current();
    for (cases) |case| {
        if (host.matches(case.when)) return case;
    }
    return error.UnsupportedPlatform;
}

pub fn toArchiveSpec(ctx: *Context, tool: Tool) !install_archive.ArchiveSpec {
    const selected = try selectArchivePlatform(tool.action.platforms orelse return error.JsonFieldMissing);
    const spec_links = try ctx.allocator.alloc(install_archive.Link, selected.links.len);
    errdefer ctx.allocator.free(spec_links);
    for (selected.links, spec_links) |link, *spec_link| {
        spec_link.* = .{ .name = link.name, .path = .literal(link.path) };
    }

    const app_links = try ctx.allocator.alloc(install_archive.Link, selected.app_links.len);
    errdefer ctx.allocator.free(app_links);
    for (selected.app_links, app_links) |link, *app_link| {
        app_link.* = .{ .name = link.name, .path = .literal(link.path) };
    }

    return .{
        .tool = tool.name,
        .source = try archiveSource(selected.source orelse tool.action.source orelse return error.JsonFieldMissing),
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

fn validateTool(ctx: *Context, tool: Tool, tool_index: usize) !void {
    if (tool.name.len == 0) return fail("tools[{d}].name: must not be empty", ctx, .{tool_index});
    if (tool.bins.len == 0) return fail("tools[{d}].bins: must not be empty", ctx, .{tool_index});
    for (tool.bins, 0..) |bin, bin_index| {
        if (bin.name.len == 0) {
            return fail("tools[{d}].bins[{d}].name: must not be empty", ctx, .{ tool_index, bin_index });
        }
        if (bin.version_argv.len == 0) {
            return fail(
                "tools[{d}].bins[{d}].version_argv: must not be empty",
                ctx,
                .{ tool_index, bin_index },
            );
        }
        for (bin.version_argv, 0..) |arg, arg_index| {
            if (arg.len == 0) {
                return fail(
                    "tools[{d}].bins[{d}].version_argv[{d}]: must not be empty",
                    ctx,
                    .{ tool_index, bin_index, arg_index },
                );
            }
        }
    }

    switch (tool.action.type) {
        .required => {},
        .archive => try validateArchiveAction(ctx, tool, tool_index),
        .package => {
            const package = tool.action.package orelse return fail(
                "tools[{d}].action.package: required for package actions",
                ctx,
                .{tool_index},
            );
            if (package.name.len == 0) {
                return fail("tools[{d}].action.package.name: must not be empty", ctx, .{tool_index});
            }
        },
        .build => {
            const build = tool.action.build orelse return fail(
                "tools[{d}].action.build: required for build actions",
                ctx,
                .{tool_index},
            );
            if (build.path.len == 0) {
                return fail("tools[{d}].action.build.path: must not be empty", ctx, .{tool_index});
            }
        },
        .script => try validateScriptAction(ctx, tool, tool_index),
        .toolchain => {
            const toolchain = tool.action.toolchain orelse return fail(
                "tools[{d}].action.toolchain: required for toolchain actions",
                ctx,
                .{tool_index},
            );
            try validateToolchainAction(ctx, toolchain, tool_index);
        },
    }
}

fn validateToolchainAction(ctx: *Context, toolchain: Toolchain, tool_index: usize) !void {
    if (toolchain.name.len == 0) {
        return fail("tools[{d}].action.toolchain.name: must not be empty", ctx, .{tool_index});
    }
    if (toolchain.components.len == 0) {
        return fail("tools[{d}].action.toolchain.components: must not be empty", ctx, .{tool_index});
    }
    for (toolchain.components, 0..) |component, component_index| {
        if (component.len == 0) {
            return fail(
                "tools[{d}].action.toolchain.components[{d}]: must not be empty",
                ctx,
                .{ tool_index, component_index },
            );
        }
    }
    if (toolchain.install.unix == null and toolchain.install.windows == null) {
        return fail("tools[{d}].action.toolchain.install: must define unix or windows command", ctx, .{tool_index});
    }
    if (toolchain.install.unix) |command| {
        try validateToolchainInstallCommand("tools[{d}].action.toolchain.install.unix", ctx, command, .{tool_index});
    }
    if (toolchain.install.windows) |command| {
        try validateToolchainInstallCommand("tools[{d}].action.toolchain.install.windows", ctx, command, .{tool_index});
    }
    try validateArgv(
        "tools[{d}].action.toolchain.update_argv",
        ctx,
        toolchain.update_argv,
        .{tool_index},
        &.{ "manager_bin", "toolchain", "components" },
    );
    try validateArgv(
        "tools[{d}].action.toolchain.active_argv",
        ctx,
        toolchain.active_argv,
        .{tool_index},
        &.{ "manager_bin", "toolchain" },
    );
    try validateArgv(
        "tools[{d}].action.toolchain.default_argv",
        ctx,
        toolchain.default_argv,
        .{tool_index},
        &.{ "manager_bin", "toolchain" },
    );
    try validateArgv(
        "tools[{d}].action.toolchain.component_argv",
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

fn validateArchiveAction(ctx: *Context, tool: Tool, tool_index: usize) !void {
    if (tool.action.source == null and tool.action.platforms == null) {
        return fail(
            "tools[{d}].action.source: archive actions need a source or platform source",
            ctx,
            .{tool_index},
        );
    }
    if (tool.action.source) |source| try validateSource("tools[{d}].action.source", ctx, source, .{tool_index});
    const platforms = tool.action.platforms orelse return fail(
        "tools[{d}].action.platforms: required for archive actions",
        ctx,
        .{tool_index},
    );
    if (platforms.len == 0) {
        return fail("tools[{d}].action.platforms: must not be empty", ctx, .{tool_index});
    }
    for (platforms, 0..) |case, platform_index| {
        if (case.platform.len == 0) {
            return fail(
                "tools[{d}].action.platforms[{d}].platform: must not be empty",
                ctx,
                .{ tool_index, platform_index },
            );
        }
        try validateTemplate(
            "tools[{d}].action.platforms[{d}].platform",
            ctx,
            case.platform,
            .{ tool_index, platform_index },
            &.{},
        );
        if (case.source) |source| {
            try validateSource(
                "tools[{d}].action.platforms[{d}].source",
                ctx,
                source,
                .{ tool_index, platform_index },
            );
        } else if (tool.action.source == null) {
            return fail(
                "tools[{d}].action.platforms[{d}].source: required when action.source is missing",
                ctx,
                .{ tool_index, platform_index },
            );
        }
        try validateLinks(
            "tools[{d}].action.platforms[{d}].links",
            true,
            ctx,
            case.links,
            .{ tool_index, platform_index },
        );
        try validateLinks(
            "tools[{d}].action.platforms[{d}].app_links",
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
    for (entries, 0..) |link, link_index| {
        if (link.name.len == 0) {
            return fail(path_fmt ++ "[{d}].name: must not be empty", ctx, args ++ .{link_index});
        }
        if (link.path.len == 0) {
            return fail(path_fmt ++ "[{d}].path: must not be empty", ctx, args ++ .{link_index});
        }
        try validateTemplate(
            path_fmt ++ "[{d}].path",
            ctx,
            link.path,
            args ++ .{link_index},
            &.{ "version", "platform" },
        );
    }
}

fn validateScriptAction(ctx: *Context, tool: Tool, tool_index: usize) !void {
    const script = tool.action.script orelse return fail(
        "tools[{d}].action.script: required for script actions",
        ctx,
        .{tool_index},
    );
    if (script.unix == null and script.windows == null) {
        return fail("tools[{d}].action.script: must define unix or windows command", ctx, .{tool_index});
    }
    if (script.unix) |command| {
        try validateScriptCommand("tools[{d}].action.script.unix", ctx, command, .{tool_index});
    }
    if (script.windows) |command| {
        try validateScriptCommand("tools[{d}].action.script.windows", ctx, command, .{tool_index});
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
    switch (source.type) {
        .github_latest => {
            if (source.repo == null) return fail(path_fmt ++ ".repo: required for github_latest sources", ctx, args);
            if (source.asset == null) return fail(path_fmt ++ ".asset: required for github_latest sources", ctx, args);
            try rejectUnsupportedSourceFields(
                path_fmt,
                "github_latest",
                ctx,
                source,
                args,
                .{ .repo = true, .tag_prefix = true, .asset = true },
            );
            try validateTemplate(path_fmt ++ ".asset", ctx, source.asset.?, args, &.{ "version", "platform" });
        },
        .direct => {
            if (source.version == null) return fail(path_fmt ++ ".version: required for direct sources", ctx, args);
            if (source.url == null) return fail(path_fmt ++ ".url: required for direct sources", ctx, args);
            try rejectUnsupportedSourceFields(
                path_fmt,
                "direct",
                ctx,
                source,
                args,
                .{ .version = true, .url = true },
            );
            try validateTemplate(path_fmt ++ ".url", ctx, source.url.?, args, &.{ "version", "platform" });
        },
        .command => {
            if (source.argv == null) return fail(path_fmt ++ ".argv: required for command sources", ctx, args);
            if (source.argv.?.len == 0) return fail(path_fmt ++ ".argv: must not be empty", ctx, args);
            if (source.url == null) return fail(path_fmt ++ ".url: required for command sources", ctx, args);
            try rejectUnsupportedSourceFields(
                path_fmt,
                "command",
                ctx,
                source,
                args,
                .{ .argv = true, .url = true },
            );
            for (source.argv.?, 0..) |arg, arg_index| {
                if (arg.len == 0) {
                    return fail(path_fmt ++ ".argv[{d}]: must not be empty", ctx, args ++ .{arg_index});
                }
            }
            try validateTemplate(path_fmt ++ ".url", ctx, source.url.?, args, &.{ "version", "platform" });
        },
        .node_latest => {
            if (source.index_url == null) {
                return fail(path_fmt ++ ".index_url: required for node_latest sources", ctx, args);
            }
            if (source.url == null) return fail(path_fmt ++ ".url: required for node_latest sources", ctx, args);
            try rejectUnsupportedSourceFields(
                path_fmt,
                "node_latest",
                ctx,
                source,
                args,
                .{ .index_url = true, .url = true },
            );
            try validateTemplate(path_fmt ++ ".url", ctx, source.url.?, args, &.{ "version", "platform" });
        },
    }
}

const SourceFields = struct {
    repo: bool = false,
    tag_prefix: bool = false,
    asset: bool = false,
    version: bool = false,
    url: bool = false,
    argv: bool = false,
    index_url: bool = false,
};

fn rejectUnsupportedSourceFields(
    comptime path_fmt: []const u8,
    comptime source_type: []const u8,
    ctx: *Context,
    source: Source,
    args: anytype,
    allowed: SourceFields,
) !void {
    if (!allowed.repo and source.repo != null) return unsupportedSourceField(path_fmt, source_type, ctx, args);
    if (!allowed.tag_prefix and source.tag_prefix.len != 0) {
        return unsupportedSourceField(path_fmt, source_type, ctx, args);
    }
    if (!allowed.asset and source.asset != null) return unsupportedSourceField(path_fmt, source_type, ctx, args);
    if (!allowed.version and source.version != null) return unsupportedSourceField(path_fmt, source_type, ctx, args);
    if (!allowed.url and source.url != null) return unsupportedSourceField(path_fmt, source_type, ctx, args);
    if (!allowed.argv and source.argv != null) return unsupportedSourceField(path_fmt, source_type, ctx, args);
    if (!allowed.index_url and source.index_url != null) {
        return unsupportedSourceField(path_fmt, source_type, ctx, args);
    }
}

fn unsupportedSourceField(
    comptime path_fmt: []const u8,
    comptime source_type: []const u8,
    ctx: *Context,
    args: anytype,
) error{InvalidManifest} {
    return fail(path_fmt ++ ": contains fields that do not apply to " ++ source_type ++ " sources", ctx, args);
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
    return switch (input.type) {
        .github_latest => .{ .github_latest = .{
            .repo = input.repo orelse return error.JsonFieldMissing,
            .tag_prefix = input.tag_prefix,
            .asset = .literal(input.asset orelse return error.JsonFieldMissing),
        } },
        .direct => .{ .direct = .{
            .version = input.version orelse return error.JsonFieldMissing,
            .url = .literal(input.url orelse return error.JsonFieldMissing),
        } },
        .command => .{ .command = .{
            .argv = input.argv orelse return error.JsonFieldMissing,
            .url = .literal(input.url orelse return error.JsonFieldMissing),
        } },
        .node_latest => .{ .node_latest = .{
            .index_url = input.index_url orelse return error.JsonFieldMissing,
            .url = .literal(input.url orelse return error.JsonFieldMissing),
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

test "manifest validation rejects duplicate bin names" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    const json =
        \\{
        \\  "tools": [
        \\    {
        \\      "name": "one",
        \\      "bins": [{"name": "same", "version_argv": ["same", "--version"]}],
        \\      "action": {"type": "required"}
        \\    },
        \\    {
        \\      "name": "two",
        \\      "bins": [{"name": "same", "version_argv": ["same", "--version"]}],
        \\      "action": {"type": "required"}
        \\    }
        \\  ]
        \\}
    ;

    var parsed = try std.json.parseFromSlice(ManifestJson, ctx.allocator, json, .{});
    defer parsed.deinit();

    try std.testing.expectError(error.InvalidManifest, validate(&ctx, parsed.value));
}

test "archive spec maps manifest links and direct source" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);
    const tool: Tool = .{
        .name = "demo",
        .bins = &.{},
        .action = .{
            .type = .archive,
            .source = .{
                .type = .direct,
                .version = "1.2.3",
                .url = "https://example.test/demo.tar.gz",
            },
            .platforms = &.{.{
                .when = .{},
                .platform = "demo-platform",
                .kind = .tar_gz,
                .strip_components = 1,
                .links = &.{.{ .name = "demo", .path = "bin/demo" }},
                .app_links = &.{.{ .name = "Demo.app", .path = "Demo.app" }},
            }},
        },
    };

    const spec = try toArchiveSpec(&ctx, tool);
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

    const json =
        \\{
        \\  "tools": [{
        \\    "name": "demo",
        \\    "bins": [{"name": "demo", "version_argv": ["demo", "--version"]}],
        \\    "action": {
        \\      "type": "archive",
        \\      "source": {
        \\        "type": "direct",
        \\        "version": "1.0.0",
        \\        "url": "https://example.test/demo.tar.gz"
        \\      },
        \\      "platforms": [{
        \\        "when": {},
        \\        "platform": "demo-platform",
        \\        "kind": "tar_gz",
        \\        "strip_components": 1,
        \\        "links": [{"name": "demo", "path": "bin/demo"}],
        \\        "app_links": [{"name": "Demo.app", "path": "{unknown}.app"}]
        \\      }]
        \\    }
        \\  }]
        \\}
    ;

    var parsed = try std.json.parseFromSlice(ManifestJson, ctx.allocator, json, .{});
    defer parsed.deinit();

    try std.testing.expectError(error.InvalidManifest, validate(&ctx, parsed.value));
}

test "archive platform source overrides action source" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);
    const tool: Tool = .{
        .name = "demo",
        .bins = &.{},
        .action = .{
            .type = .archive,
            .source = .{
                .type = .direct,
                .version = "base",
                .url = "https://example.test/base.tar.gz",
            },
            .platforms = &.{.{
                .when = .{},
                .platform = "demo-platform",
                .source = .{
                    .type = .direct,
                    .version = "override",
                    .url = "https://example.test/override.zip",
                },
                .kind = .zip,
                .strip_components = 1,
                .links = &.{.{ .name = "demo", .path = "bin/demo" }},
            }},
        },
    };

    const spec = try toArchiveSpec(&ctx, tool);
    defer ctx.allocator.free(spec.links);
    defer ctx.allocator.free(spec.app_links);

    switch (spec.source) {
        .direct => |direct| {
            try std.testing.expectEqualStrings("override", direct.version);
            try std.testing.expectEqualStrings("https://example.test/override.zip", direct.url.value);
        },
        else => return error.WrongSourceType,
    }
}

test "tool metadata helpers classify actions" {
    const required: Tool = .{
        .name = "git",
        .bins = &.{},
        .action = .{ .type = .required },
    };
    try std.testing.expect(required.isRequired());
    try std.testing.expectEqual(Phase.prerequisites, required.phase());
    try std.testing.expectEqualStrings("bootstrap-required", required.sourceLabel(false));

    const package_tool: Tool = .{
        .name = "ruff",
        .bins = &.{},
        .action = .{
            .type = .package,
            .package = .{ .manager = .uv, .name = "ruff" },
        },
    };
    try std.testing.expectEqual(Phase.packages, package_tool.phase());
    try std.testing.expect(package_tool.usesPackageManager(.uv));
}

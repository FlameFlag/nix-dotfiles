const std = @import("std");

const archive_lib = @import("archive.zig");
const Context = @import("context.zig").Context;
const install_archive = @import("install.zig");
const planning = @import("manifest/plan.zig");
const platform = @import("platform.zig");
const validator = @import("manifest/validator.zig");

pub const Policy = enum { install_missing, update_all };
pub const Phase = enum { prerequisites, archives, packages, builds };
pub const HostOs = platform.Os;
pub const HostArch = platform.Arch;
pub const HostRequirement = enum { lenovo_laptop, not_nixos };
pub const ArchiveKind = archive_lib.Kind;
pub const Diagnostics = validator.Diagnostics;
pub const Diagnostic = validator.Diagnostic;

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
    version_index: VersionIndexSource,
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

pub const VersionIndexSource = struct {
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

pub fn toolchainAction(spec: Toolchain) Tool.Action {
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

pub fn versionIndex(index_url: []const u8, url: []const u8) Source {
    return .{ .version_index = .{ .index_url = index_url, .url = url } };
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

pub fn validate(catalog: Catalog, diagnostics: *Diagnostics) !void {
    try validator.validate(catalog, diagnostics);
}

pub fn writeDiagnostics(ctx: *Context, diagnostics: Diagnostics) !void {
    try diagnostics.write(ctx.io);
}

pub fn selectArchivePlatform(cases: []const ArchivePlatform) !ArchivePlatform {
    return planning.selectArchivePlatform(cases);
}

pub fn toArchiveSpec(ctx: *Context, tool_entry: Tool) !install_archive.ArchiveSpec {
    return planning.planArchive(ctx, tool_entry);
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
    var diagnostics = Diagnostics.init(std.testing.allocator);
    defer diagnostics.deinit();

    try std.testing.expectError(error.InvalidManifest, validate(testCatalog(&.{
        tool("same", &.{bin("one", &.{"one"})}, required()),
        tool("same", &.{bin("two", &.{"two"})}, required()),
    }), &diagnostics));
    try std.testing.expectEqual(@as(usize, 1), diagnostics.entries.items.len);
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.entries.items[0].message, "duplicate tool name") != null);
}

test "catalog validation rejects duplicate bin names" {
    var diagnostics = Diagnostics.init(std.testing.allocator);
    defer diagnostics.deinit();

    try std.testing.expectError(error.InvalidManifest, validate(testCatalog(&.{
        tool("one", &.{bin("same", &.{ "same", "--version" })}, required()),
        tool("two", &.{bin("same", &.{ "same", "--version" })}, required()),
    }), &diagnostics));
    try std.testing.expectEqual(@as(usize, 1), diagnostics.entries.items.len);
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.entries.items[0].message, "duplicate bin name") != null);
}

test "catalog validation rejects empty argv" {
    var diagnostics = Diagnostics.init(std.testing.allocator);
    defer diagnostics.deinit();

    try std.testing.expectError(error.InvalidManifest, validate(testCatalog(&.{
        tool("demo", &.{bin("demo", &.{ "demo", "" })}, required()),
    }), &diagnostics));
    try std.testing.expectEqual(@as(usize, 1), diagnostics.entries.items.len);
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.entries.items[0].message, "version_argv[1]") != null);
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
    var diagnostics = Diagnostics.init(std.testing.allocator);
    defer diagnostics.deinit();

    try std.testing.expectError(error.InvalidManifest, validate(testCatalog(&.{
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
    }), &diagnostics));
    try std.testing.expectEqual(@as(usize, 1), diagnostics.entries.items.len);
    try std.testing.expect(
        std.mem.indexOf(u8, diagnostics.entries.items[0].message, "unknown template placeholder") != null,
    );
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
    const toolchain_tool = tool("demo-toolchain", &.{bin("manager", &.{"manager"})}, toolchainAction(.{
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

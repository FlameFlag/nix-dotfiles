const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");

const archive = @import("archive.zig");
const Context = @import("context.zig").Context;
const http = @import("http.zig");
const links = @import("links.zig");
const proc = common.process;
const release = @import("release.zig");
const fs = common.fs;
const template = common.template;

pub const Link = struct {
    name: []const u8,
    path: Template,
};

pub const Template = template.Template;
pub const RenderArgs = template.Bindings;

pub const Source = union(enum) {
    github_latest: GithubLatest,
    github_latest_matching: GithubLatestMatching,
    direct: Direct,
    command: Command,
    version_index: VersionIndex,

    pub const GithubLatest = struct {
        repo: []const u8,
        tag_prefix: []const u8 = "",
        asset: Template,
    };

    pub const GithubLatestMatching = struct {
        repo: []const u8,
        tag_prefix: []const u8 = "",
        asset_prefix: Template,
        asset_suffix: Template,
    };

    pub const Direct = struct {
        version: []const u8,
        url: Template,
    };

    pub const Command = struct {
        argv: []const []const u8,
        url: Template,
    };

    pub const VersionIndex = struct {
        index_url: []const u8,
        url: Template,
    };
};

const ResolvedSource = struct {
    version: []const u8,
    url: []const u8,
    release: ?release.GithubRelease = null,
    owns_version: bool = false,

    fn deinit(self: *ResolvedSource, ctx: *Context) void {
        if (self.owns_version) ctx.allocator.free(self.version);
        ctx.allocator.free(self.url);
        if (self.release) |*github_release| github_release.deinit();
        self.* = undefined;
    }
};

pub const ArchiveSpec = struct {
    tool: []const u8,
    source: Source,
    platform: []const u8,
    kind: archive.Kind,
    strip_components: u32,
    links: []const Link,
    app_links: []const Link = &.{},

    pub fn install(self: ArchiveSpec, ctx: *Context) !void {
        var resolved = try resolveSource(ctx, self.source, self.platform);
        defer resolved.deinit(ctx);

        const template_args: RenderArgs = .{ .version = resolved.version, .platform = self.platform };
        const tool_links = try renderLinks(ctx, self.links, template_args);
        defer freeLinks(ctx, tool_links);
        const app_links = try renderLinks(ctx, self.app_links, template_args);
        defer freeLinks(ctx, app_links);

        try (Archive{
            .tool = self.tool,
            .version = resolved.version,
            .url = resolved.url,
            .kind = self.kind,
            .strip_components = self.strip_components,
            .links = tool_links,
            .app_links = app_links,
        }).install(ctx);
    }
};

pub const Archive = struct {
    tool: []const u8,
    version: []const u8,
    url: []const u8,
    kind: archive.Kind,
    strip_components: u32,
    links: []const links.Link,
    app_links: []const links.Link = &.{},

    pub fn install(self: Archive, ctx: *Context) !void {
        const dir = try links.installDirPath(ctx, self.tool, self.version);
        defer ctx.allocator.free(dir);
        const temp_dir = try std.fmt.allocPrint(ctx.allocator, "{s}.tmp", .{dir});
        defer ctx.allocator.free(temp_dir);
        var temp_exists = false;
        errdefer if (temp_exists) deleteTreeQuiet(ctx, temp_dir);

        const download_dir = try fs.tempDir(ctx, "bootstrap-archive");
        defer {
            deleteTreeQuiet(ctx, download_dir);
            ctx.allocator.free(download_dir);
        }
        const archive_path = try std.fs.path.join(ctx.allocator, &.{ download_dir, archiveFileName(self.kind) });
        defer ctx.allocator.free(archive_path);

        try http.downloadFile(ctx, self.url, archive_path);
        try std.Io.Dir.cwd().deleteTree(ctx.io, temp_dir);
        try archive.extractFile(ctx, archive_path, temp_dir, self.kind, self.strip_components);
        try repairExecutablePermissions(ctx, temp_dir);
        temp_exists = true;
        try std.Io.Dir.cwd().deleteTree(ctx.io, dir);
        try std.Io.Dir.renameAbsolute(temp_dir, dir, ctx.io);
        temp_exists = false;
        try links.linkMany(ctx, self.tool, dir, self.links);
        try linkApplications(ctx, dir, self.app_links);
    }
};

fn archiveFileName(kind: archive.Kind) []const u8 {
    return switch (kind) {
        .tar_xz => "archive.tar.xz",
        .tar_gz => "archive.tar.gz",
        .zip => "archive.zip",
    };
}

fn linkApplications(ctx: *Context, install_dir: []const u8, entries: []const links.Link) !void {
    if (builtin.os.tag != .macos) return;

    for (entries) |entry| {
        const target = try std.fs.path.join(ctx.allocator, &.{ install_dir, entry.path });
        defer ctx.allocator.free(target);
        const link_path = try std.fs.path.join(ctx.allocator, &.{ "/Applications", entry.name });
        defer ctx.allocator.free(link_path);

        var replace_existing = false;
        var old_buf: [4096]u8 = undefined;
        if (std.Io.Dir.cwd().readLink(ctx.io, link_path, &old_buf)) |_| {
            replace_existing = true;
        } else |err| switch (err) {
            error.FileNotFound => {},
            error.NotLink => continue,
            else => return err,
        }

        try std.Io.Dir.cwd().access(ctx.io, target, .{});
        if (replace_existing) try std.Io.Dir.cwd().deleteFile(ctx.io, link_path);
        try std.Io.Dir.symLinkAbsolute(ctx.io, target, link_path, .{});
        try proc.run(ctx, &.{
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            "-f",
            link_path,
        });
    }
}

fn deleteTreeQuiet(ctx: *Context, path: []const u8) void {
    fs.deleteTreeWarning(ctx.io, "temporary directory", path);
}

fn repairExecutablePermissions(ctx: *Context, root: []const u8) !void {
    if (builtin.os.tag == .windows) return;

    var dir = try std.Io.Dir.openDirAbsolute(ctx.io, root, .{ .iterate = true });
    defer dir.close(ctx.io);

    var walker = try dir.walk(ctx.allocator);
    defer walker.deinit();

    while (try walker.next(ctx.io)) |entry| {
        if (entry.kind != .file) continue;
        if (!try hasExecutableHeader(ctx, entry.dir, entry.basename)) continue;
        try entry.dir.setFilePermissions(ctx.io, entry.basename, .executable_file, .{});
    }
}

fn hasExecutableHeader(ctx: *Context, dir: std.Io.Dir, basename: []const u8) !bool {
    var header: [4]u8 = undefined;
    const bytes = dir.readFile(ctx.io, basename, &header) catch |err| switch (err) {
        error.AccessDenied => return false,
        else => return err,
    };
    return std.mem.startsWith(u8, bytes, "#!") or
        std.mem.startsWith(u8, bytes, "\x7fELF") or
        std.mem.startsWith(u8, bytes, "MZ") or
        isMachOMagic(bytes);
}

fn isMachOMagic(bytes: []const u8) bool {
    if (bytes.len < 4) return false;
    const magic_be = std.mem.readInt(u32, bytes[0..4], .big);
    const magic_le = std.mem.readInt(u32, bytes[0..4], .little);
    return magic_be == 0xfeedface or
        magic_be == 0xfeedfacf or
        magic_be == 0xcafebabe or
        magic_be == 0xcafebabf or
        magic_le == 0xfeedface or
        magic_le == 0xfeedfacf;
}

fn resolveSource(ctx: *Context, source: Source, target_name: []const u8) !ResolvedSource {
    return switch (source) {
        .github_latest => |github| {
            var latest = try release.latestGithub(ctx, github.repo);
            errdefer latest.deinit();

            const version = release.versionFromTag(latest.tag(), github.tag_prefix);
            const template_args: RenderArgs = .{ .version = version, .platform = target_name };
            const asset = try github.asset.render(ctx.allocator, template_args);
            defer ctx.allocator.free(asset);

            const url = try ctx.allocator.dupe(u8, try latest.assetUrl(asset));
            errdefer ctx.allocator.free(url);
            return .{
                .version = version,
                .url = url,
                .release = latest,
            };
        },
        .github_latest_matching => |github| {
            var latest = try release.latestGithub(ctx, github.repo);
            errdefer latest.deinit();

            const version = release.versionFromTag(latest.tag(), github.tag_prefix);
            const template_args: RenderArgs = .{ .version = version, .platform = target_name };
            const prefix = try github.asset_prefix.render(ctx.allocator, template_args);
            defer ctx.allocator.free(prefix);
            const suffix = try github.asset_suffix.render(ctx.allocator, template_args);
            defer ctx.allocator.free(suffix);

            const url = try ctx.allocator.dupe(u8, try latest.matchingAssetUrl(prefix, suffix));
            errdefer ctx.allocator.free(url);
            return .{
                .version = version,
                .url = url,
                .release = latest,
            };
        },
        .direct => |direct| {
            const template_args: RenderArgs = .{ .version = direct.version, .platform = target_name };
            return .{
                .version = direct.version,
                .url = try direct.url.render(ctx.allocator, template_args),
            };
        },
        .command => |command| {
            const version = try proc.trimmedText(ctx, command.argv);
            errdefer ctx.allocator.free(version);
            const template_args: RenderArgs = .{ .version = version, .platform = target_name };
            return .{
                .version = version,
                .url = try command.url.render(ctx.allocator, template_args),
                .owns_version = true,
            };
        },
        .version_index => |version_index| try resolveVersionIndex(ctx, version_index, target_name),
    };
}

fn resolveVersionIndex(ctx: *Context, source: Source.VersionIndex, target_name: []const u8) !ResolvedSource {
    const json = try http.getBytes(ctx, source.index_url);
    defer ctx.allocator.free(json);
    return resolveVersionIndexJson(ctx, source, target_name, json);
}

fn resolveVersionIndexJson(
    ctx: *Context,
    source: Source.VersionIndex,
    target_name: []const u8,
    json: []const u8,
) !ResolvedSource {
    const IndexedRelease = struct {
        version: []const u8,
    };

    var releases = try std.json.parseFromSlice(
        []const IndexedRelease,
        ctx.allocator,
        json,
        .{ .ignore_unknown_fields = true },
    );
    defer releases.deinit();

    for (releases.value) |entry| {
        const version = try ctx.allocator.dupe(u8, entry.version);
        errdefer ctx.allocator.free(version);
        const template_args: RenderArgs = .{ .version = version, .platform = target_name };
        return .{
            .version = version,
            .url = try source.url.render(ctx.allocator, template_args),
            .owns_version = true,
        };
    }
    return error.AssetNotFound;
}

fn renderLinks(ctx: *Context, entries: []const Link, args: RenderArgs) ![]links.Link {
    const rendered = try ctx.allocator.alloc(links.Link, entries.len);
    errdefer ctx.allocator.free(rendered);

    var initialized: usize = 0;
    errdefer {
        for (rendered[0..initialized]) |entry| ctx.allocator.free(entry.path);
    }

    for (entries, rendered) |entry, *out| {
        out.* = .{
            .name = entry.name,
            .path = try entry.path.render(ctx.allocator, args),
        };
        initialized += 1;
    }
    return rendered;
}

fn freeLinks(ctx: *Context, entries: []links.Link) void {
    for (entries) |entry| ctx.allocator.free(entry.path);
    ctx.allocator.free(entries);
}

test {
    std.testing.refAllDecls(@This());
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

test "templates render version and platform placeholders" {
    const rendered = try (Template.literal("tool-{version}-{platform}.tar.gz")).render(std.testing.allocator, .{
        .version = "1.2.3",
        .platform = "aarch64-macos",
    });
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings("tool-1.2.3-aarch64-macos.tar.gz", rendered);
}

test "direct archive source resolves URL from declarative data" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var resolved = try resolveSource(&ctx, .{ .direct = .{
        .version = "1.2.3",
        .url = .literal("https://example.test/tool-{version}-{platform}.tar.gz"),
    } }, "aarch64-macos");
    defer resolved.deinit(&ctx);

    try std.testing.expectEqualStrings("1.2.3", resolved.version);
    try std.testing.expectEqualStrings("https://example.test/tool-1.2.3-aarch64-macos.tar.gz", resolved.url);
}

test "version index source resolves first indexed release declaratively" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);
    const spec: Source.VersionIndex = .{
        .index_url = "unused",
        .url = .literal("https://example.test/{version}/tool-{version}-{platform}.tar.xz"),
    };
    const json =
        \\[
        \\  {"version":"v24.0.0"},
        \\  {"version":"v22.15.0"}
        \\]
    ;

    var resolved = try resolveVersionIndexJson(&ctx, spec, "darwin-arm64", json);
    defer resolved.deinit(&ctx);

    try std.testing.expectEqualStrings("v24.0.0", resolved.version);
    try std.testing.expectEqualStrings("https://example.test/v24.0.0/tool-v24.0.0-darwin-arm64.tar.xz", resolved.url);
}

test "version index source honors configured platform templates" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);
    const spec: Source.VersionIndex = .{
        .index_url = "unused",
        .url = .literal("https://example.test/{version}/tool-{version}-{platform}.tar.xz"),
    };
    const json =
        \\[
        \\  {"version":"v24.0.0"}
        \\]
    ;

    var resolved = try resolveVersionIndexJson(&ctx, spec, "linux-arm64-musl", json);
    defer resolved.deinit(&ctx);

    try std.testing.expectEqualStrings("v24.0.0", resolved.version);
    try std.testing.expectEqualStrings(
        "https://example.test/v24.0.0/tool-v24.0.0-linux-arm64-musl.tar.xz",
        resolved.url,
    );
}

test "version index source reports empty and malformed indexes" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);
    const spec: Source.VersionIndex = .{
        .index_url = "unused",
        .url = .literal("https://example.test/{version}/tool-{version}-{platform}.tar.xz"),
    };

    try std.testing.expectError(error.AssetNotFound, resolveVersionIndexJson(&ctx, spec, "darwin-arm64", "[]"));
    try std.testing.expectError(error.UnexpectedToken, resolveVersionIndexJson(&ctx, spec, "darwin-arm64", "{}"));
    try std.testing.expectError(error.MissingField, resolveVersionIndexJson(&ctx, spec, "darwin-arm64", "[{}]"));
}

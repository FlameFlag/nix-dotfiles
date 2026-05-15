const std = @import("std");
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
    direct: Direct,
    command: Command,
    node_latest: NodeLatest,

    pub const GithubLatest = struct {
        repo: []const u8,
        tag_prefix: []const u8 = "",
        asset: Template,
    };

    pub const Direct = struct {
        version: []const u8,
        url: Template,
    };

    pub const Command = struct {
        argv: []const []const u8,
        url: Template,
    };

    pub const NodeLatest = struct {
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

    pub fn install(self: ArchiveSpec, ctx: *Context) !void {
        var resolved = try resolveSource(ctx, self.source, self.platform);
        defer resolved.deinit(ctx);

        const template_args: RenderArgs = .{ .version = resolved.version, .platform = self.platform };
        const tool_links = try renderLinks(ctx, self.links, template_args);
        defer freeLinks(ctx, tool_links);

        try (Archive{
            .tool = self.tool,
            .version = resolved.version,
            .url = resolved.url,
            .kind = self.kind,
            .strip_components = self.strip_components,
            .links = tool_links,
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
        temp_exists = true;
        try std.Io.Dir.cwd().deleteTree(ctx.io, dir);
        try std.Io.Dir.renameAbsolute(temp_dir, dir, ctx.io);
        temp_exists = false;
        try links.linkMany(ctx, self.tool, dir, self.links);
    }
};

fn archiveFileName(kind: archive.Kind) []const u8 {
    return switch (kind) {
        .tar_xz => "archive.tar.xz",
        .tar_gz => "archive.tar.gz",
        .zip => "archive.zip",
    };
}

fn deleteTreeQuiet(ctx: *Context, path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(ctx.io, path) catch |err| {
        std.log.debug("failed to delete temporary directory {s}: {s}", .{ path, @errorName(err) });
    };
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
        .node_latest => |node| try resolveNodeLatest(ctx, node, target_name),
    };
}

fn resolveNodeLatest(ctx: *Context, source: Source.NodeLatest, target_name: []const u8) !ResolvedSource {
    const resolved_source = if (std.mem.endsWith(u8, target_name, "-musl"))
        Source.NodeLatest{
            .index_url = "https://unofficial-builds.nodejs.org/download/release/index.json",
            .url = .literal(
                "https://unofficial-builds.nodejs.org/download/release/{version}/node-{version}-{platform}.tar.xz",
            ),
        }
    else
        source;

    const json = try http.getBytes(ctx, resolved_source.index_url);
    defer ctx.allocator.free(json);
    return resolveNodeLatestJson(ctx, resolved_source, target_name, json);
}

fn resolveNodeLatestJson(
    ctx: *Context,
    source: Source.NodeLatest,
    target_name: []const u8,
    json: []const u8,
) !ResolvedSource {
    const NodeRelease = struct {
        version: []const u8,
    };

    var parsed = try std.json.parseFromSlice(
        []const NodeRelease,
        ctx.allocator,
        json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    for (parsed.value) |entry| {
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

test "node source resolves first indexed release declaratively" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);
    const spec: Source.NodeLatest = .{
        .index_url = "unused",
        .url = .literal("https://example.test/{version}/node-{version}-{platform}.tar.xz"),
    };
    const json =
        \\[
        \\  {"version":"v24.0.0"},
        \\  {"version":"v22.15.0"}
        \\]
    ;

    var resolved = try resolveNodeLatestJson(&ctx, spec, "darwin-arm64", json);
    defer resolved.deinit(&ctx);

    try std.testing.expectEqualStrings("v24.0.0", resolved.version);
    try std.testing.expectEqualStrings("https://example.test/v24.0.0/node-v24.0.0-darwin-arm64.tar.xz", resolved.url);
}

test "node source resolves musl release from unofficial builds URL" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);
    const spec: Source.NodeLatest = .{
        .index_url = "unused",
        .url = .literal("https://example.test/{version}/node-{version}-{platform}.tar.xz"),
    };
    const json =
        \\[
        \\  {"version":"v24.0.0"}
        \\]
    ;

    var resolved = try resolveNodeLatestJson(&ctx, spec, "linux-arm64-musl", json);
    defer resolved.deinit(&ctx);

    try std.testing.expectEqualStrings("v24.0.0", resolved.version);
    try std.testing.expectEqualStrings(
        "https://example.test/v24.0.0/node-v24.0.0-linux-arm64-musl.tar.xz",
        resolved.url,
    );
}

test "node source reports empty and malformed indexes" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);
    const spec: Source.NodeLatest = .{
        .index_url = "unused",
        .url = .literal("https://example.test/{version}/node-{version}-{platform}.tar.xz"),
    };

    try std.testing.expectError(error.AssetNotFound, resolveNodeLatestJson(&ctx, spec, "darwin-arm64", "[]"));
    try std.testing.expectError(error.UnexpectedToken, resolveNodeLatestJson(&ctx, spec, "darwin-arm64", "{}"));
    try std.testing.expectError(error.MissingField, resolveNodeLatestJson(&ctx, spec, "darwin-arm64", "[{}]"));
}

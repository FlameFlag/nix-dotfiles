const std = @import("std");

const Context = @import("../context.zig").Context;
const install_archive = @import("../install.zig");
const model = @import("../manifest.zig");
const platform = @import("../platform.zig");

pub fn selectArchivePlatform(cases: []const model.ArchivePlatform) !model.ArchivePlatform {
    const current_host = platform.current();
    for (cases) |case| {
        if (current_host.matches(case.when)) return case;
    }
    return error.UnsupportedPlatform;
}

pub fn planArchive(ctx: *Context, tool_entry: model.Tool) !install_archive.ArchiveSpec {
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

fn archiveSource(input: model.Source) !install_archive.Source {
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
        .version_index => |version_index| .{ .version_index = .{
            .index_url = version_index.index_url,
            .url = .literal(version_index.url),
        } },
    };
}

test "archive source conversion preserves source details" {
    const source = try archiveSource(model.direct("1.2.3", "https://example.test/tool.tar.gz"));
    switch (source) {
        .direct => |direct_source| {
            try std.testing.expectEqualStrings("1.2.3", direct_source.version);
            try std.testing.expectEqualStrings("https://example.test/tool.tar.gz", direct_source.url.value);
        },
        else => return error.WrongSourceType,
    }
}

test "archive platform selection rejects unsupported host" {
    try std.testing.expectError(error.UnsupportedPlatform, selectArchivePlatform(&.{
        .{
            .when = .{ .os = .linux, .arch = .x86_64 },
            .platform = "linux-x86_64",
            .kind = .tar_gz,
            .strip_components = 0,
            .links = &.{model.link("demo", "demo")},
        },
    }));
}

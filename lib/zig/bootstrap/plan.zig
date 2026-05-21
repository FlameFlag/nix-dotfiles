const std = @import("std");

const Context = @import("context.zig").Context;
const install_archive = @import("install.zig");
const manifest = @import("manifest.zig");

pub const InstallPlan = struct {
    tool: manifest.Tool,
    action: Action,

    pub const Action = union(enum) {
        required,
        archive: install_archive.ArchiveSpec,
        package: manifest.Package,
        build: manifest.Build,
        script: manifest.Script,
        source_build: manifest.SourceBuild,
        toolchain: manifest.Toolchain,
    };

    pub fn fromTool(ctx: *Context, tool: manifest.Tool) !InstallPlan {
        return .{
            .tool = tool,
            .action = switch (tool.action) {
                .required => .required,
                .archive => .{ .archive = try manifest.toArchiveSpec(ctx, tool) },
                .package => |spec| .{ .package = spec },
                .build => |spec| .{ .build = spec },
                .script => |spec| .{ .script = spec },
                .source_build => |spec| .{ .source_build = spec },
                .toolchain => |spec| .{ .toolchain = spec },
            },
        };
    }

    pub fn deinit(self: *InstallPlan, allocator: std.mem.Allocator) void {
        switch (self.action) {
            .archive => |archive_spec| {
                allocator.free(archive_spec.links);
                allocator.free(archive_spec.app_links);
            },
            else => {},
        }
        self.* = undefined;
    }
};

test "install planning resolves archive actions" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx: Context = .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = &env,
        .home = "",
        .bin_dir = "",
        .opt_dir = "",
    };
    const tool: manifest.Tool = .{
        .name = "demo",
        .bins = &.{manifest.bin("demo", &.{"demo"})},
        .action = manifest.archive(manifest.direct("1.2.3", "https://example.test/demo.zip"), &.{.{
            .when = .{},
            .platform = "any",
            .kind = .zip,
            .strip_components = 0,
            .links = &.{manifest.link("demo", "demo")},
        }}),
    };

    var plan = try InstallPlan.fromTool(&ctx, tool);
    defer plan.deinit(std.testing.allocator);
    switch (plan.action) {
        .archive => |archive_spec| {
            try std.testing.expectEqualStrings("demo", archive_spec.tool);
            try std.testing.expectEqualStrings("any", archive_spec.platform);
            try std.testing.expectEqual(@as(usize, 1), archive_spec.links.len);
        },
        else => return error.WrongActionType,
    }
}

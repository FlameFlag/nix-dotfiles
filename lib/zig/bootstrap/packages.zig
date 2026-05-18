const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");

const Context = @import("context.zig").Context;
const manifest = @import("manifest.zig");

const proc = common.process;

pub const Inventory = struct {
    state: State = .{},

    pub fn collect(ctx: *Context) !Inventory {
        return .{
            .state = .{
                .uv = try Uv.collect(ctx),
            },
        };
    }

    pub fn empty() Inventory {
        return .{};
    }

    pub fn deinit(self: *Inventory, ctx: *Context) void {
        self.state.deinit(ctx);
        self.* = undefined;
    }

    pub fn binIsManaged(self: Inventory, package: manifest.Package, bin: []const u8, path: []const u8) bool {
        return switch (package.manager) {
            .uv => if (self.state.uv) |uv| uv.binIsManaged(bin, path) else false,
        };
    }
};

const State = struct {
    uv: ?Uv = null,

    fn deinit(self: *State, ctx: *Context) void {
        if (self.uv) |*uv| uv.deinit(ctx);
        self.* = undefined;
    }
};

const Uv = struct {
    tool_list: ?[]const u8 = null,
    bins: std.StringHashMap([]const u8),

    fn init(allocator: std.mem.Allocator) Uv {
        return .{ .bins = std.StringHashMap([]const u8).init(allocator) };
    }

    fn collect(ctx: *Context) !Uv {
        var uv = Uv.init(ctx.allocator);
        errdefer uv.deinit(ctx);

        const uv_path = try proc.pathOf(ctx, "uv") orelse return uv;
        defer ctx.allocator.free(uv_path);

        uv.tool_list = try proc.trimmedText(ctx, &.{ uv_path, "tool", "list", "--show-paths" });
        try uv.parse();
        return uv;
    }

    fn testing(ctx: *Context, tool_list: []const u8) !Uv {
        var uv = Uv.init(ctx.allocator);
        errdefer uv.deinit(ctx);
        uv.tool_list = try ctx.allocator.dupe(u8, tool_list);
        try uv.parse();
        return uv;
    }

    fn deinit(self: *Uv, ctx: *Context) void {
        self.bins.deinit();
        if (self.tool_list) |value| ctx.allocator.free(value);
        self.* = undefined;
    }

    fn parse(self: *Uv) !void {
        const output_text = self.tool_list orelse return;
        var lines = std.mem.splitScalar(u8, output_text, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (!std.mem.startsWith(u8, trimmed, "- ")) continue;
            const open = std.mem.findScalarLast(u8, trimmed, '(') orelse continue;
            if (!std.mem.endsWith(u8, trimmed, ")")) continue;

            const listed_bin = std.mem.trim(u8, trimmed[2..open], " \t");
            const listed_path = trimmed[open + 1 .. trimmed.len - 1];
            try self.bins.put(listed_bin, listed_path);
        }
    }

    fn binIsManaged(self: Uv, bin: []const u8, path: []const u8) bool {
        const listed_path = self.bins.get(bin) orelse return false;
        return std.mem.eql(u8, listed_path, path);
    }
};

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

fn tmpPath(allocator: std.mem.Allocator, tmp: std.testing.TmpDir, parts: []const []const u8) ![]u8 {
    return common.testing.tmpPath(allocator, tmp, parts);
}

test "package inventory parses uv-managed bins once into a map" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var uv = try Uv.testing(&ctx,
        \\ruff v0.15.13 (/Users/example/.local/share/uv/tools/ruff)
        \\- ruff (/Users/example/.local/bin/ruff)
        \\- ruff-lsp (/Users/example/.local/bin/ruff-lsp)
    );
    defer uv.deinit(&ctx);

    const inventory: Inventory = .{ .state = .{ .uv = uv } };
    const package: manifest.Package = .{ .manager = .uv, .name = "ruff" };

    try std.testing.expect(inventory.binIsManaged(package, "ruff", "/Users/example/.local/bin/ruff"));
    try std.testing.expect(inventory.binIsManaged(package, "ruff-lsp", "/Users/example/.local/bin/ruff-lsp"));
    try std.testing.expect(!inventory.binIsManaged(package, "ruff", "/usr/bin/ruff"));
}

test "uv inventory ignores missing uv and propagates failing uv" {
    if (comptime builtin.os.tag == .windows) return;

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    try env.put("PATH", "");
    var missing = try Uv.collect(&ctx);
    defer missing.deinit(&ctx);
    try std.testing.expectEqual(@as(usize, 0), missing.bins.count());

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const bin_dir = try tmpPath(ctx.allocator, tmp, &.{"bin"});
    defer ctx.allocator.free(bin_dir);
    const uv_path = try tmpPath(ctx.allocator, tmp, &.{ "bin", "uv" });
    defer ctx.allocator.free(uv_path);
    try common.fs.writeExecutableFile(ctx.io, uv_path,
        \\#!/bin/sh
        \\exit 42
        \\
    );
    try env.put("PATH", bin_dir);

    try std.testing.expectError(error.CommandFailed, Uv.collect(&ctx));
}

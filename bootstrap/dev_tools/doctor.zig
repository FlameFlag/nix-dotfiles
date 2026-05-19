const std = @import("std");
const bootstrap = @import("bootstrap");
const common = @import("common");
const Context = bootstrap.Context;
const manifest = bootstrap.manifest;
const ownership = bootstrap.ownership;
const packages = bootstrap.packages;
const proc = common.process;
const tools = @import("tools.zig");
const host = tools.host;

const Row = struct {
    name: []const u8,
    source: []const u8,
    version: []u8,
    path: []const u8,
    owns_path: bool,

    fn deinit(self: Row, allocator: std.mem.Allocator) void {
        allocator.free(self.version);
        if (self.owns_path) allocator.free(self.path);
    }
};

pub fn run(ctx: *Context) !void {
    var catalog = try tools.loadCatalog(ctx);
    defer catalog.deinit(ctx);

    var package_inventory = try packages.Inventory.collect(ctx);
    defer package_inventory.deinit(ctx);

    const cwd = try std.process.currentPathAlloc(ctx.io, ctx.allocator);
    defer ctx.allocator.free(cwd);

    var rows: std.ArrayList(Row) = .empty;
    defer {
        for (rows.items) |row| row.deinit(ctx.allocator);
        rows.deinit(ctx.allocator);
    }

    for (catalog.tools) |tool| {
        if (!try host.supportsTool(tool, ctx)) continue;
        for (tool.bins) |bin| {
            const path = try proc.pathOf(ctx, bin.name);
            const version = if (tool.usesBuildInstaller() and path != null)
                try ctx.allocator.dupe(u8, "installed")
            else blk: {
                const raw = proc.trimmedText(ctx, bin.version_argv) catch |err|
                    try std.fmt.allocPrint(ctx.allocator, "error:{s}", .{@errorName(err)});
                break :blk try sanitizeVersion(ctx, raw);
            };

            try rows.append(ctx.allocator, .{
                .name = bin.name,
                .source = try sourceLabel(ctx, cwd, tool, bin.name, path, package_inventory),
                .version = version,
                .path = path orelse "missing",
                .owns_path = path != null,
            });
        }
    }

    try printRows(ctx, rows.items);
}

fn sourceLabel(
    ctx: *Context,
    cwd: []const u8,
    tool: manifest.Tool,
    bin: []const u8,
    path: ?[]const u8,
    package_inventory: packages.Inventory,
) ![]const u8 {
    return switch (try ownership.classifyBin(ctx, cwd, tool, bin, path, package_inventory)) {
        .missing => "missing",
        .managed => tool.sourceLabel(true),
        .external => tool.sourceLabel(false),
    };
}

fn printRows(ctx: *Context, rows: []const Row) !void {
    var buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(ctx.io, &buffer);
    const writer = &stdout.interface;

    var name_width: usize = "tool".len;
    var source_width: usize = "source".len;
    var version_width: usize = "version".len;
    for (rows) |row| {
        name_width = @max(name_width, row.name.len);
        source_width = @max(source_width, row.source.len);
        version_width = @max(version_width, row.version.len);
    }

    try printCell(writer, "tool", name_width);
    try printCell(writer, "source", source_width);
    try printCell(writer, "version", version_width);
    try writer.writeAll("path\n");

    try printRule(writer, name_width);
    try printRule(writer, source_width);
    try printRule(writer, version_width);
    try writer.writeAll("----\n");

    for (rows) |row| {
        try printCell(writer, row.name, name_width);
        try printCell(writer, row.source, source_width);
        try printCell(writer, row.version, version_width);
        try writer.print("{s}\n", .{row.path});
    }

    try writer.flush();
}

fn printCell(writer: *std.Io.Writer, value: []const u8, width: usize) !void {
    try writer.writeAll(value);
    try writer.splatByteAll(' ', width + 2 - value.len);
}

fn printRule(writer: *std.Io.Writer, width: usize) !void {
    try writer.splatByteAll('-', width);
    try writer.writeAll("  ");
}

fn sanitizeVersion(ctx: *Context, owned: []u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(ctx.allocator);
    var pending_space = false;
    for (owned) |byte| {
        if (byte == '\n' or byte == '\r') {
            pending_space = out.items.len != 0;
            continue;
        }
        if (pending_space and byte != ' ' and byte != '\t') {
            try out.append(ctx.allocator, ' ');
        }
        pending_space = false;
        try out.append(ctx.allocator, byte);
    }
    ctx.allocator.free(owned);
    return out.toOwnedSlice(ctx.allocator);
}

test "doctor versions collapse multiline output before width calculation" {
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

    const raw = try ctx.allocator.dupe(u8, "1.2.3\nabcdef\nx64");
    const sanitized = try sanitizeVersion(&ctx, raw);
    defer ctx.allocator.free(sanitized);

    try std.testing.expectEqualStrings("1.2.3 abcdef x64", sanitized);
}

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

const Status = enum { ok, failed };

const Row = struct {
    name: []const u8,
    source: []const u8,
    version: []u8,
    path: []const u8,
    owns_path: bool,
    status: Status,

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
            const path = try binPath(ctx, tool, bin.name);
            const version_status = try versionStatus(ctx, tool, bin, path);

            try rows.append(ctx.allocator, .{
                .name = bin.name,
                .source = try sourceLabel(ctx, cwd, tool, bin.name, path, package_inventory),
                .version = version_status.version,
                .path = path orelse "missing",
                .owns_path = path != null,
                .status = version_status.status,
            });
        }
    }

    try printRows(ctx, rows.items);
    for (rows.items) |row| {
        if (row.status == .failed) return error.DoctorFoundIssues;
    }
}

const VersionStatus = struct {
    version: []u8,
    status: Status,
};

fn versionStatus(ctx: *Context, tool: manifest.Tool, bin: manifest.Bin, path: ?[]const u8) !VersionStatus {
    if (path == null) {
        return .{
            .version = try ctx.allocator.dupe(u8, "missing"),
            .status = .failed,
        };
    }

    if (tool.usesBuildInstaller()) {
        return .{
            .version = try ctx.allocator.dupe(u8, "installed"),
            .status = .ok,
        };
    }

    const raw = trimmedTextAtPath(ctx, bin.version_argv, path.?) catch |err| {
        return .{
            .version = try std.fmt.allocPrint(ctx.allocator, "error:{s}", .{@errorName(err)}),
            .status = .failed,
        };
    };
    return .{
        .version = try sanitizeVersion(ctx, raw),
        .status = .ok,
    };
}

fn trimmedTextAtPath(ctx: *Context, argv_template: []const []const u8, path: []const u8) ![]u8 {
    const argv = try ctx.allocator.alloc([]const u8, argv_template.len);
    defer ctx.allocator.free(argv);
    argv[0] = if (std.mem.eql(u8, std.fs.path.basename(path), argv_template[0]) or
        std.mem.eql(u8, argv_template[0], std.fs.path.stem(std.fs.path.basename(path))))
        path
    else
        argv_template[0];
    @memcpy(argv[1..], argv_template[1..]);

    var result = try proc.capture(ctx, argv);
    defer result.deinit(ctx.allocator);
    if (result.failureError()) |err| return err;

    const stdout = common.fs.trimAsciiWhitespace(result.stdout);
    if (stdout.len != 0) return ctx.allocator.dupe(u8, stdout);
    return ctx.allocator.dupe(u8, common.fs.trimAsciiWhitespace(result.stderr));
}

fn binPath(ctx: *Context, tool: manifest.Tool, bin: []const u8) !?[]u8 {
    return switch (tool.action) {
        .toolchain => |toolchain| toolchainBinPath(ctx, toolchain, bin),
        else => proc.pathOf(ctx, bin),
    };
}

fn toolchainBinPath(ctx: *Context, toolchain: manifest.Toolchain, bin: []const u8) !?[]u8 {
    const bin_dir = try bootstrap.toolchain.toolchainBinDir(ctx, toolchain);
    defer ctx.allocator.free(bin_dir);
    const name = try executableName(ctx, bin);
    defer ctx.allocator.free(name);
    const path = try std.fs.path.join(ctx.allocator, &.{ bin_dir, name });
    errdefer ctx.allocator.free(path);

    std.Io.Dir.cwd().access(ctx.io, path, .{ .execute = true }) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => {
            ctx.allocator.free(path);
            return null;
        },
        else => return err,
    };
    return path;
}

fn executableName(ctx: *Context, name: []const u8) ![]u8 {
    if (@import("builtin").os.tag == .windows and std.fs.path.extension(name).len == 0) {
        return std.fmt.allocPrint(ctx.allocator, "{s}.exe", .{name});
    }
    return ctx.allocator.dupe(u8, name);
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

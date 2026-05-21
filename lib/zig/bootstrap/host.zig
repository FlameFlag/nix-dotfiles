const std = @import("std");
const builtin = @import("builtin");

const Context = @import("context.zig").Context;
const helpers = @import("host_helpers.zig");
const manifest = @import("manifest.zig");

const linux_dmi_vendor_path = "/sys/class/dmi/id/sys_vendor";
const linux_dmi_board_vendor_path = "/sys/class/dmi/id/board_vendor";
const linux_dmi_product_name_path = "/sys/class/dmi/id/product_name";
const linux_dmi_chassis_type_path = "/sys/class/dmi/id/chassis_type";

pub const windows_lenovo_probe_argv = helpers.windows_lenovo_probe_argv;

pub const HostFacts = struct {
    os: ?manifest.HostOs,
    arch: ?manifest.HostArch,
};

pub fn currentFacts() HostFacts {
    return .{
        .os = currentHostOs(),
        .arch = currentHostArch(),
    };
}

pub fn supportsTool(ctx: *Context, tool: manifest.Tool) !bool {
    if (tool.platforms) |allowed| {
        const host_os = currentHostOs() orelse return false;
        for (allowed) |entry| {
            if (entry == host_os) break;
        } else {
            return false;
        }
    }

    switch (tool.action) {
        .archive => |archive_spec| {
            _ = manifest.selectArchivePlatform(archive_spec.platforms) catch |err| switch (err) {
                error.UnsupportedPlatform => return false,
            };
        },
        else => {},
    }

    const requirements = tool.requires orelse return true;
    for (requirements) |requirement| {
        if (!try meetsRequirement(ctx, requirement)) return false;
    }
    return true;
}

pub fn currentHostOs() ?manifest.HostOs {
    return switch (builtin.os.tag) {
        .macos => .macos,
        .linux => .linux,
        .windows => .windows,
        else => null,
    };
}

pub fn currentHostArch() ?manifest.HostArch {
    return switch (builtin.cpu.arch) {
        .aarch64 => .aarch64,
        .x86_64 => .x86_64,
        else => null,
    };
}

pub fn meetsRequirement(ctx: *Context, requirement: manifest.HostRequirement) !bool {
    return switch (requirement) {
        .lenovo_laptop => isLenovoLaptop(ctx),
    };
}

pub fn isLenovoLaptop(ctx: *Context) !bool {
    return switch (builtin.os.tag) {
        .linux => try isLinuxLenovoLaptop(ctx),
        .windows => try isWindowsLenovoLaptop(ctx),
        else => false,
    };
}

pub fn isLinuxLenovoLaptop(ctx: *Context) !bool {
    if (!try linuxDmiIdentifiesLenovo(ctx)) return false;
    const chassis_type = try readTrimmedAbsolute(ctx, linux_dmi_chassis_type_path) orelse return false;
    defer ctx.allocator.free(chassis_type);
    return isLaptopChassisType(chassis_type);
}

pub fn linuxDmiIdentifiesLenovo(ctx: *Context) !bool {
    if (try readTrimmedAbsolute(ctx, linux_dmi_vendor_path)) |vendor| {
        defer ctx.allocator.free(vendor);
        if (isLenovoVendor(vendor)) return true;
    }
    if (try readTrimmedAbsolute(ctx, linux_dmi_board_vendor_path)) |vendor| {
        defer ctx.allocator.free(vendor);
        if (isLenovoVendor(vendor)) return true;
    }
    if (try readTrimmedAbsolute(ctx, linux_dmi_product_name_path)) |product| {
        defer ctx.allocator.free(product);
        if (helpers.isLenovoVendor(product) or helpers.isLegionModel(product)) return true;
    }
    return false;
}

fn readTrimmedAbsolute(ctx: *Context, path: []const u8) !?[]u8 {
    var file = std.Io.Dir.openFileAbsolute(ctx.io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return null,
        else => return err,
    };
    defer file.close(ctx.io);

    var read_buffer: [512]u8 = undefined;
    var reader = file.reader(ctx.io, &read_buffer);
    const contents = reader.interface.allocRemaining(ctx.allocator, .limited(4096)) catch |err| switch (err) {
        error.StreamTooLong => return error.FileTooBig,
        else => return err,
    };
    errdefer ctx.allocator.free(contents);
    const trimmed = std.mem.trim(u8, contents, " \t\r\n");
    if (trimmed.len == contents.len) return contents;
    const out = try ctx.allocator.dupe(u8, trimmed);
    ctx.allocator.free(contents);
    return out;
}

pub fn isWindowsLenovoLaptop(ctx: *Context) !bool {
    const result = std.process.run(ctx.allocator, ctx.io, .{
        .argv = windows_lenovo_probe_argv,
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer ctx.allocator.free(result.stdout);
    defer ctx.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return false,
        else => return false,
    }
    return windowsProbeOutputIsLenovoLaptop(result.stdout);
}

pub fn windowsProbeOutputIsLenovoLaptop(stdout: []const u8) bool {
    return helpers.windowsProbeOutputIsLenovoLaptop(stdout);
}

pub fn isLenovoVendor(value: []const u8) bool {
    return helpers.isLenovoVendor(value);
}

pub fn isLegionModel(value: []const u8) bool {
    return helpers.isLegionModel(value);
}

pub fn isLaptopChassisType(value: []const u8) bool {
    return helpers.isLaptopChassisType(value);
}

test "detect Lenovo vendor strings" {
    try std.testing.expect(isLenovoVendor("LENOVO"));
    try std.testing.expect(isLenovoVendor("Lenovo Group Limited"));
    try std.testing.expect(!isLenovoVendor("Dell Inc."));
    try std.testing.expect(!isLenovoVendor(""));
}

test "detect portable DMI chassis types" {
    try std.testing.expect(isLaptopChassisType("8"));
    try std.testing.expect(isLaptopChassisType("9"));
    try std.testing.expect(isLaptopChassisType("10"));
    try std.testing.expect(isLaptopChassisType("14"));
    try std.testing.expect(isLaptopChassisType("31"));
    try std.testing.expect(isLaptopChassisType("32"));
    try std.testing.expect(!isLaptopChassisType("3"));
    try std.testing.expect(!isLaptopChassisType(""));
    try std.testing.expect(!isLaptopChassisType("not-a-number"));
}

test "parse Windows Lenovo probe output" {
    try std.testing.expect(windowsProbeOutputIsLenovoLaptop("LENOVO\nLegion 5\n3,10\n"));
    try std.testing.expect(!windowsProbeOutputIsLenovoLaptop("Dell Inc.\nXPS\n10\n"));
    try std.testing.expect(!windowsProbeOutputIsLenovoLaptop("LENOVO\nThinkCentre\n3\n"));
}

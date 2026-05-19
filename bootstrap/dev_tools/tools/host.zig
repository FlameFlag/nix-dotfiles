const std = @import("std");
const builtin = @import("builtin");
const bootstrap = @import("bootstrap");
const common = @import("common");

const Context = bootstrap.Context;
const manifest = bootstrap.manifest;
const fs = common.fs;
const proc = common.process;

const linux_dmi_vendor_path = "/sys/class/dmi/id/sys_vendor";
const linux_dmi_board_vendor_path = "/sys/class/dmi/id/board_vendor";
const linux_dmi_product_name_path = "/sys/class/dmi/id/product_name";
const linux_dmi_chassis_type_path = "/sys/class/dmi/id/chassis_type";

pub fn supportsTool(tool: manifest.Tool, ctx: *Context) !bool {
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
            const host = bootstrap.platform.current();
            for (archive_spec.platforms) |case| {
                if (host.matches(case.when)) break;
            } else {
                return false;
            }
        },
        else => {},
    }

    const requirements = tool.requires orelse return true;
    for (requirements) |requirement| {
        if (!try meetsRequirement(ctx, requirement)) return false;
    }
    return true;
}

fn currentHostOs() ?manifest.HostOs {
    return switch (builtin.os.tag) {
        .macos => .macos,
        .linux => .linux,
        .windows => .windows,
        else => null,
    };
}

fn meetsRequirement(ctx: *Context, requirement: manifest.HostRequirement) !bool {
    return switch (requirement) {
        .lenovo_laptop => isLenovoLaptop(ctx),
    };
}

fn isLenovoLaptop(ctx: *Context) !bool {
    return switch (builtin.os.tag) {
        .linux => try isLinuxLenovoLaptop(ctx),
        .windows => try isWindowsLenovoLaptop(ctx),
        else => false,
    };
}

fn isLinuxLenovoLaptop(ctx: *Context) !bool {
    if (!try linuxDmiIdentifiesLenovo(ctx)) return false;
    const chassis_type = try readTrimmedAbsolute(ctx, linux_dmi_chassis_type_path) orelse return false;
    defer ctx.allocator.free(chassis_type);
    return isLaptopChassisType(chassis_type);
}

fn linuxDmiIdentifiesLenovo(ctx: *Context) !bool {
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
        if (isLenovoVendor(product) or std.ascii.findIgnoreCase(product, "legion") != null) return true;
    }
    return false;
}

fn readTrimmedAbsolute(ctx: *Context, path: []const u8) !?[]u8 {
    return fs.readTrimmedAllocOptional(ctx.allocator, ctx.io, path);
}

fn isWindowsLenovoLaptop(ctx: *Context) !bool {
    var result = proc.capture(ctx, &.{
        "pwsh",
        "-NoProfile",
        "-Command",
        "$cs = Get-CimInstance Win32_ComputerSystem; " ++
            "$en = Get-CimInstance Win32_SystemEnclosure; " ++
            "\"$($cs.Manufacturer)`n$($cs.Model)`n$($en.ChassisTypes -join ',')\"",
    }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer result.deinit(ctx.allocator);
    if (result.exit_code != 0) return false;

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    const manufacturer = fs.trimAsciiWhitespace(lines.next() orelse "");
    const model = fs.trimAsciiWhitespace(lines.next() orelse "");
    const chassis_types = fs.trimAsciiWhitespace(lines.next() orelse "");
    if (!isLenovoVendor(manufacturer) and
        !isLenovoVendor(model) and
        std.ascii.findIgnoreCase(model, "legion") == null)
    {
        return false;
    }

    var chassis_values = std.mem.splitScalar(u8, chassis_types, ',');
    while (chassis_values.next()) |raw| {
        if (isLaptopChassisType(fs.trimAsciiWhitespace(raw))) return true;
    }
    return false;
}

fn isLenovoVendor(value: []const u8) bool {
    return std.ascii.findIgnoreCase(value, "lenovo") != null;
}

fn isLaptopChassisType(value: []const u8) bool {
    const parsed = std.fmt.parseInt(u8, value, 10) catch return false;
    return switch (parsed) {
        8, 9, 10, 14, 31, 32 => true,
        else => false,
    };
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

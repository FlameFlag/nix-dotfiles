const std = @import("std");

pub const windows_lenovo_probe_argv = &.{
    "pwsh",
    "-NoProfile",
    "-Command",
    "$cs = Get-CimInstance Win32_ComputerSystem; " ++
        "$en = Get-CimInstance Win32_SystemEnclosure; " ++
        "\"$($cs.Manufacturer)`n$($cs.Model)`n$($en.ChassisTypes -join ',')\"",
};

pub fn windowsProbeOutputIsLenovoLaptop(stdout: []const u8) bool {
    var lines = std.mem.splitScalar(u8, stdout, '\n');
    const manufacturer = std.mem.trim(u8, lines.next() orelse "", " \t\r\n");
    const model = std.mem.trim(u8, lines.next() orelse "", " \t\r\n");
    const chassis_types = std.mem.trim(u8, lines.next() orelse "", " \t\r\n");
    if (!isLenovoVendor(manufacturer) and !isLenovoVendor(model) and !isLegionModel(model)) {
        return false;
    }

    var chassis_values = std.mem.splitScalar(u8, chassis_types, ',');
    while (chassis_values.next()) |raw| {
        if (isLaptopChassisType(std.mem.trim(u8, raw, " \t\r\n"))) return true;
    }
    return false;
}

pub fn isLenovoVendor(value: []const u8) bool {
    return std.ascii.findIgnoreCase(value, "lenovo") != null;
}

pub fn isLegionModel(value: []const u8) bool {
    return std.ascii.findIgnoreCase(value, "legion") != null;
}

pub fn isLaptopChassisType(value: []const u8) bool {
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

test "parse Windows Lenovo probe output" {
    try std.testing.expect(windowsProbeOutputIsLenovoLaptop("LENOVO\nLegion 5\n3,10\n"));
    try std.testing.expect(!windowsProbeOutputIsLenovoLaptop("Dell Inc.\nXPS\n10\n"));
    try std.testing.expect(!windowsProbeOutputIsLenovoLaptop("LENOVO\nThinkCentre\n3\n"));
}

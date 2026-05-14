const std = @import("std");
const raycast_window_management = @import("../raycast_window_management/main.zig");

pub fn main(init: std.process.Init) !void {
    try raycast_window_management.main(init);
}

test {
    std.testing.refAllDecls(raycast_window_management);
}

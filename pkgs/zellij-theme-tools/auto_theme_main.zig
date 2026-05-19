const std = @import("std");
const common = @import("common");

const auto_theme = @import("auto_theme.zig");

pub fn main(init: std.process.Init) !u8 {
    return auto_theme.run(init) catch |err| {
        try common.output.stderr(init.io, "error: {s}\n", .{@errorName(err)});
        return 1;
    };
}

test {
    std.testing.refAllDecls(@This());
}

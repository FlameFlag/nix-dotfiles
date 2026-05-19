const std = @import("std");
const common = @import("common");

const codex = @import("codex.zig");

pub fn main(init: std.process.Init) !u8 {
    return codex.run(init) catch |err| {
        try common.output.stderr(init.io, "error: {s}\n", .{@errorName(err)});
        return 1;
    };
}

test {
    std.testing.refAllDecls(@This());
}

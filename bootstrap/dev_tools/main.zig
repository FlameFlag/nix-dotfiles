const std = @import("std");
const bootstrap = @import("bootstrap");
const common = @import("common");

const doctor = @import("doctor.zig");
const tools = @import("tools.zig");

const Mode = enum { install, update, doctor };

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const argv0 = if (args.len > 0) args[0] else "dev_tools";
    if (args.len != 2) return usage(init, argv0);

    const mode = std.meta.stringToEnum(Mode, args[1]) orelse return usage(init, argv0);
    var ctx = try bootstrap.Context.init(init.gpa, init.io, init.environ_map);
    defer ctx.deinit();

    switch (mode) {
        .install => try tools.installAll(&ctx, .install_missing),
        .update => try tools.installAll(&ctx, .update_all),
        .doctor => try doctor.run(&ctx),
    }
}

fn usage(init: std.process.Init, bin: []const u8) !void {
    try common.output.stderr(init.io, "usage: {s} install|update|doctor\n", .{bin});
    return error.InvalidArgs;
}

test {
    std.testing.refAllDecls(@This());
}

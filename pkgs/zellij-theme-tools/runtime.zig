const std = @import("std");

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    env: *std.process.Environ.Map,
};

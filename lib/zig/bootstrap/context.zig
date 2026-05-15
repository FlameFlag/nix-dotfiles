const std = @import("std");
const common = @import("common");

pub const Context = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    env: *std.process.Environ.Map,
    home: []const u8,
    bin_dir: []const u8,
    opt_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map) !Context {
        const home_value = env.get("HOME") orelse return error.HomeMissing;
        const home = try allocator.dupe(u8, home_value);
        errdefer allocator.free(home);

        const bin_dir = try std.fs.path.join(allocator, &.{ home, ".local", "bin" });
        errdefer allocator.free(bin_dir);
        const opt_dir = try std.fs.path.join(allocator, &.{ home, ".local", "opt" });
        errdefer allocator.free(opt_dir);

        try std.Io.Dir.cwd().createDirPath(io, bin_dir);
        try std.Io.Dir.cwd().createDirPath(io, opt_dir);

        return .{
            .allocator = allocator,
            .io = io,
            .env = env,
            .home = home,
            .bin_dir = bin_dir,
            .opt_dir = opt_dir,
        };
    }

    pub fn deinit(self: *Context) void {
        self.allocator.free(self.home);
        self.allocator.free(self.bin_dir);
        self.allocator.free(self.opt_dir);
        self.* = undefined;
    }
};

fn tmpPath(allocator: std.mem.Allocator, tmp: std.testing.TmpDir, parts: []const []const u8) ![]u8 {
    return common.testing.tmpPath(allocator, tmp, parts);
}

test "context requires HOME and creates local bootstrap dirs" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    try std.testing.expectError(error.HomeMissing, Context.init(std.testing.allocator, std.testing.io, &env));

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const home = try tmpPath(std.testing.allocator, tmp, &.{"home"});
    defer std.testing.allocator.free(home);
    try env.put("HOME", home);

    var ctx = try Context.init(std.testing.allocator, std.testing.io, &env);
    defer ctx.deinit();

    try std.Io.Dir.cwd().access(std.testing.io, ctx.bin_dir, .{});
    try std.Io.Dir.cwd().access(std.testing.io, ctx.opt_dir, .{});
}

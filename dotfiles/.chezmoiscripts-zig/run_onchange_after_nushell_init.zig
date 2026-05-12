const std = @import("std");
const script = @import("script.zig");

pub fn main(init: std.process.Init) !void {
    try script.mainWith(init, run);
}

fn run(rt: *script.Runtime) !void {
    const context = try script.chezmoiContext(rt);
    defer context.deinit(rt.allocator);

    const dirs = [_][]const u8{
        ".cache/starship",
        ".cache/zoxide",
        ".local/share/atuin",
    };
    for (dirs) |dir| {
        const path = try std.fs.path.join(rt.allocator, &.{ context.home_dir, dir });
        defer rt.allocator.free(path);
        try std.Io.Dir.cwd().createDirPath(rt.io, path);
    }

    const starship_init = try std.fs.path.join(rt.allocator, &.{ context.home_dir, ".cache/starship/init.nu" });
    defer rt.allocator.free(starship_init);
    _ = try script.writeCommandTextIfAvailable(rt, "starship", starship_init, &.{ "starship", "init", "nu" });

    const zoxide_init = try std.fs.path.join(rt.allocator, &.{ context.home_dir, ".cache/zoxide/init.nu" });
    defer rt.allocator.free(zoxide_init);
    _ = try script.writeCommandTextIfAvailable(rt, "zoxide", zoxide_init, &.{ "zoxide", "init", "nushell" });

    const atuin_init = try std.fs.path.join(rt.allocator, &.{ context.home_dir, ".local/share/atuin/init.nu" });
    defer rt.allocator.free(atuin_init);
    _ = try script.writeCommandTextIfAvailable(rt, "atuin", atuin_init, &.{ "atuin", "init", "nu", "--disable-up-arrow" });

    if (std.Io.Dir.cwd().readFileAlloc(rt.io, atuin_init, rt.allocator, .limited(64 * 1024 * 1024))) |current| {
        defer rt.allocator.free(current);
        const fixed = try std.mem.replaceOwned(u8, rt.allocator, current, "$cmd e>| complete", "$cmd | complete");
        defer rt.allocator.free(fixed);
        _ = try script.writeTextIfChanged(rt, atuin_init, fixed);
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }
}

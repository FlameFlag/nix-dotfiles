const std = @import("std");
const script = @import("chezmoi");

pub fn main(init: std.process.Init) !void {
    try script.mainWith(run, init);
}

fn run(rt: *script.Runtime) !void {
    if (!try script.hasBin(rt, "code")) return;

    const context = try script.chezmoiContext(rt);
    defer context.deinit(rt.allocator);

    const extensions_file = try std.fs.path.join(
        rt.allocator,
        &.{ context.source_dir, "dot_config/Code/User/vscode-extensions.txt" },
    );
    defer rt.allocator.free(extensions_file);
    std.Io.Dir.cwd().access(rt.io, extensions_file, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };

    const listed = try script.commandText(rt, &.{ "code", "--list-extensions" });
    defer rt.allocator.free(listed);

    const wanted = try std.Io.Dir.cwd().readFileAlloc(
        rt.io,
        extensions_file,
        rt.allocator,
        .limited(64 * 1024 * 1024),
    );
    defer rt.allocator.free(wanted);

    var lines = std.mem.splitAny(u8, wanted, "\r\n");
    while (lines.next()) |raw_line| {
        const extension = std.mem.trim(u8, raw_line, " \t\r\n");
        if (extension.len == 0) continue;
        if (containsLineIgnoreCase(listed, extension)) continue;
        try script.command(rt, &.{ "code", "--install-extension", extension, "--force" });
    }
}

fn containsLineIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    var lines = std.mem.splitAny(u8, haystack, "\r\n");
    while (lines.next()) |line| {
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, line, " \t\r\n"), needle)) return true;
    }
    return false;
}

test "containsLineIgnoreCase matches whole trimmed lines only" {
    const installed = "ms-vscode.cpptools\nCatppuccin.catppuccin-vsc\r\n ziglang.vscode-zig  \n";

    try std.testing.expect(containsLineIgnoreCase(installed, "catppuccin.catppuccin-vsc"));
    try std.testing.expect(containsLineIgnoreCase(installed, "ZIGLANG.VSCODE-ZIG"));
    try std.testing.expect(!containsLineIgnoreCase(installed, "vscode"));
    try std.testing.expect(!containsLineIgnoreCase(installed, "missing.extension"));
}

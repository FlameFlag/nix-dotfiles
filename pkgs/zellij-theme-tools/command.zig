const std = @import("std");
const builtin = @import("builtin");

const supports_signal_forwarding = switch (builtin.os.tag) {
    .linux,
    .driverkit,
    .ios,
    .maccatalyst,
    .macos,
    .tvos,
    .visionos,
    .watchos,
    .freebsd,
    .netbsd,
    .openbsd,
    .haiku,
    .illumos,
    .serenity,
    => true,
    else => false,
};

pub fn runSilently(rt: anytype, argv: []const []const u8) void {
    var child = std.process.spawn(rt.io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return;
    defer child.kill(rt.io);
    _ = child.wait(rt.io) catch return;
}

pub fn runInherit(
    rt: anytype,
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map,
) !u8 {
    var signal_forwarder = SignalForwarder.install();
    defer signal_forwarder.deinit();

    var child = try std.process.spawn(rt.io, .{
        .argv = argv,
        .environ_map = environ_map,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    defer child.kill(rt.io);

    signal_forwarder.setChild(child.id);
    defer signal_forwarder.clearChild();

    return termExitStatus(try child.wait(rt.io));
}

pub fn termExitStatus(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        .signal => |sig| signalExitStatus(sig),
        .stopped => |sig| signalExitStatus(sig),
        .unknown => 1,
    };
}

fn signalExitStatus(sig: std.posix.SIG) u8 {
    const raw: u32 = @intFromEnum(sig);
    return @intCast(@min(@as(u32, 255), 128 + raw));
}

const SignalForwarder = if (supports_signal_forwarding) struct {
    old_int: std.posix.Sigaction = undefined,
    old_term: std.posix.Sigaction = undefined,
    installed: bool = false,

    fn install() SignalForwarder {
        var self: SignalForwarder = .{};
        const mask = std.posix.sigemptyset();
        const action: std.posix.Sigaction = .{
            .handler = .{ .handler = handleSignal },
            .mask = mask,
            .flags = 0,
        };
        std.posix.sigaction(.INT, &action, &self.old_int);
        std.posix.sigaction(.TERM, &action, &self.old_term);
        self.installed = true;
        return self;
    }

    fn deinit(self: *SignalForwarder) void {
        defer self.* = undefined;
        if (!self.installed) return;
        active_child_pid.store(0, .seq_cst);
        std.posix.sigaction(.INT, &self.old_int, null);
        std.posix.sigaction(.TERM, &self.old_term, null);
        self.installed = false;
    }

    fn setChild(_: *SignalForwarder, maybe_pid: ?std.process.Child.Id) void {
        if (maybe_pid) |pid| active_child_pid.store(@intCast(pid), .seq_cst);
    }

    fn clearChild(_: *SignalForwarder) void {
        active_child_pid.store(0, .seq_cst);
    }
} else struct {
    fn install() SignalForwarder {
        return .{};
    }

    fn deinit(self: *SignalForwarder) void {
        self.* = undefined;
    }

    fn setChild(_: *SignalForwarder, _: anytype) void {}
    fn clearChild(_: *SignalForwarder) void {}
};

var active_child_pid = std.atomic.Value(i32).init(0);

fn handleSignal(sig: std.posix.SIG) callconv(.c) void {
    const pid = active_child_pid.load(.seq_cst);
    if (pid > 0) {
        std.posix.kill(@intCast(pid), sig) catch return;
    }
}

test "termination status follows shell signal convention" {
    try std.testing.expectEqual(@as(u8, 0), termExitStatus(.{ .exited = 0 }));
    try std.testing.expectEqual(@as(u8, 42), termExitStatus(.{ .exited = 42 }));
    try std.testing.expectEqual(@as(u8, 130), termExitStatus(.{ .signal = .INT }));
}

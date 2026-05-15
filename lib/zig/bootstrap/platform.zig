const std = @import("std");
const builtin = @import("builtin");

pub const Os = std.Target.Os.Tag;
pub const Arch = std.Target.Cpu.Arch;

pub const Host = struct {
    os: Os,
    arch: Arch,

    pub fn matches(self: Host, predicate: Predicate) bool {
        if (predicate.os) |os| {
            if (self.os != os) return false;
        }
        if (predicate.arch) |arch| {
            if (self.arch != arch) return false;
        }
        return true;
    }
};

pub const Predicate = struct {
    os: ?Os = null,
    arch: ?Arch = null,
};

pub fn current() Host {
    return .{
        .os = builtin.os.tag,
        .arch = builtin.cpu.arch,
    };
}

test "current host is represented as structured platform facts" {
    const host = current();
    try std.testing.expect(host.matches(.{ .os = host.os }));
    try std.testing.expect(host.matches(.{ .arch = host.arch }));
    try std.testing.expect(host.matches(.{ .os = host.os, .arch = host.arch }));
}

test "host predicates require all supplied facts to match" {
    const host: Host = .{ .os = .linux, .arch = .x86_64 };

    try std.testing.expect(host.matches(.{ .os = .linux }));
    try std.testing.expect(host.matches(.{ .arch = .x86_64 }));
    try std.testing.expect(host.matches(.{ .os = .linux, .arch = .x86_64 }));
    try std.testing.expect(!host.matches(.{ .os = .macos }));
    try std.testing.expect(!host.matches(.{ .os = .linux, .arch = .aarch64 }));
}

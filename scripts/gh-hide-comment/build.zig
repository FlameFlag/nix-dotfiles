const std = @import("std");

const test_sources = [_][]const u8{
    "auth.zig",
    "cli.zig",
    "github.zig",
    "http.zig",
    "main.zig",
    "url.zig",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "gh-hide-comment",
        .root_module = module,
    });
    b.installArtifact(exe);

    const test_step = b.step("test", "Run unit tests");
    for (test_sources) |source| {
        const test_module = b.createModule(.{
            .root_source_file = b.path(source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const unit_tests = b.addTest(.{
            .root_module = test_module,
        });
        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }
}

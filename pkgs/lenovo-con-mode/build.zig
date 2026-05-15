const std = @import("std");

const common_import_name = "common";

const test_sources = [_][]const u8{
    "cli.zig",
    "linux.zig",
    "main.zig",
    "platform.zig",
    "windows.zig",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const common = b.createModule(.{
        .root_source_file = b.path("../../lib/zig/common/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const module = createModule("main.zig", b, common, target, optimize);
    const exe = b.addExecutable(.{
        .name = "lenovo-con-mode",
        .root_module = module,
    });
    b.installArtifact(exe);

    const test_step = b.step("test", "Run unit tests");
    addModuleTest(b, test_step, "test-common", common);
    inline for (test_sources) |source| {
        const test_module = createModule(source, b, common, target, optimize);
        addModuleTest(b, test_step, source, test_module);
    }
}

fn createModule(
    comptime root_source_file: []const u8,
    b: *std.Build,
    common: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(root_source_file),
        .imports = &.{
            .{ .name = common_import_name, .module = common },
        },
        .target = target,
        .optimize = optimize,
    });
}

fn addModuleTest(
    b: *std.Build,
    test_step: *std.Build.Step,
    name: []const u8,
    module: *std.Build.Module,
) void {
    const unit_tests = b.addTest(.{
        .name = name,
        .root_module = module,
    });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);
}

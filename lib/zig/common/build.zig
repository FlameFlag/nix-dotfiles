const std = @import("std");

pub const import_name = "common";
pub const repo_root_source_file = "lib/zig/common/root.zig";
pub const local_root_source_file = "root.zig";

pub const ModuleOptions = struct {
    root_source_file: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

pub fn createModule(b: *std.Build, options: ModuleOptions) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = options.root_source_file,
        .target = options.target,
        .optimize = options.optimize,
    });
}

pub fn addModuleTest(
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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_step = b.step("test", "Run common Zig unit tests");

    const module = createModule(b, .{
        .root_source_file = b.path(local_root_source_file),
        .target = target,
        .optimize = optimize,
    });
    addModuleTest(b, test_step, "test-common", module);
}

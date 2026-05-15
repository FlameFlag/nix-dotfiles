const std = @import("std");

pub const import_name = "bootstrap";
pub const repo_root_source_file = "lib/zig/bootstrap/root.zig";
pub const local_root_source_file = "root.zig";

const common_import_name = "common";

pub const ModuleOptions = struct {
    root_source_file: std.Build.LazyPath,
    common: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

pub fn createModule(b: *std.Build, options: ModuleOptions) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = options.root_source_file,
        .imports = &.{
            .{ .name = common_import_name, .module = options.common },
        },
        .target = options.target,
        .optimize = options.optimize,
    });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_step = b.step("test", "Run bootstrap Zig unit tests");

    const common = b.createModule(.{
        .root_source_file = b.path("../common/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    addModuleTest(b, test_step, "test-common", common);

    const module = createModule(b, .{
        .root_source_file = b.path(local_root_source_file),
        .common = common,
        .target = target,
        .optimize = optimize,
    });
    addModuleTest(b, test_step, "test-bootstrap", module);
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

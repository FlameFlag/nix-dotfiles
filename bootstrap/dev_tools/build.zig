const std = @import("std");

const bootstrap_import_name = "bootstrap";
const common_import_name = "common";

const TestSource = struct {
    name: []const u8,
    root: []const u8,
};

const test_sources = [_]TestSource{
    .{ .name = "doctor", .root = "doctor.zig" },
    .{ .name = "main", .root = "main.zig" },
    .{ .name = "tools", .root = "tools.zig" },
    .{ .name = "tools-actions", .root = "tools/actions.zig" },
    .{ .name = "tools-catalog", .root = "tools/catalog.zig" },
    .{ .name = "tools-host", .root = "tools/host.zig" },
    .{ .name = "tools-install", .root = "tools/install.zig" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const common = b.createModule(.{
        .root_source_file = b.path("../../lib/zig/common/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bootstrap = b.createModule(.{
        .root_source_file = b.path("../../lib/zig/bootstrap/root.zig"),
        .imports = &.{
            .{ .name = common_import_name, .module = common },
        },
        .target = target,
        .optimize = optimize,
    });

    const module = createModule("main.zig", b, common, bootstrap, target, optimize);
    const exe = b.addExecutable(.{
        .name = "dev_tools",
        .root_module = module,
    });
    b.installArtifact(exe);

    const test_step = b.step("test", "Run unit tests");
    addModuleTest(b, test_step, "test-common", common);
    addModuleTest(b, test_step, "test-bootstrap", bootstrap);
    inline for (test_sources) |source| {
        const test_module = createModule(source.root, b, common, bootstrap, target, optimize);
        addModuleTest(b, test_step, source.name, test_module);
    }
}

fn createModule(
    comptime root_source_file: []const u8,
    b: *std.Build,
    common: *std.Build.Module,
    bootstrap: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(root_source_file),
        .imports = &.{
            .{ .name = bootstrap_import_name, .module = bootstrap },
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

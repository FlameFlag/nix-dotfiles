const std = @import("std");

const common_import_name = "common";

const Executable = struct {
    name: []const u8,
    root: []const u8,
};

const executables = [_]Executable{
    .{ .name = "codex-zellij-theme", .root = "codex_main.zig" },
    .{ .name = "zellij-auto-theme", .root = "auto_theme_main.zig" },
};

const test_sources = [_][]const u8{
    "auto_theme.zig",
    "codex.zig",
    "command.zig",
    "theme.zig",
    "zellij.zig",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const common = b.createModule(.{
        .root_source_file = b.path("../../lib/zig/common/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    inline for (executables) |spec| {
        const module = createModule(spec.root, b, common, target, optimize);
        const exe = b.addExecutable(.{
            .name = spec.name,
            .root_module = module,
        });
        b.installArtifact(exe);
    }

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
        .link_libc = true,
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

const std = @import("std");
const bootstrap_build = @import("bootstrap/build.zig");
const chezmoi_build = @import("chezmoi/build.zig");
const common_build = @import("common/build.zig");

pub const ModuleKey = enum {
    common,
    chezmoi,
    bootstrap,

    pub fn importName(key: ModuleKey) []const u8 {
        return switch (key) {
            .common => common_build.import_name,
            .chezmoi => chezmoi_build.import_name,
            .bootstrap => bootstrap_build.import_name,
        };
    }
};

pub const BuildConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

pub const ModuleRegistry = struct {
    items: std.EnumArray(ModuleKey, ?*std.Build.Module) = .initFill(null),

    fn put(registry: *ModuleRegistry, key: ModuleKey, module: *std.Build.Module) void {
        registry.items.set(key, module);
    }

    pub fn get(registry: ModuleRegistry, key: ModuleKey) *std.Build.Module {
        return registry.items.get(key) orelse @panic("module registry is missing an entry");
    }
};

pub fn addModules(b: *std.Build, config: BuildConfig, test_step: *std.Build.Step) ModuleRegistry {
    var registry: ModuleRegistry = .{};

    const common = common_build.createModule(b, .{
        .root_source_file = b.path(common_build.repo_root_source_file),
        .target = config.target,
        .optimize = config.optimize,
    });
    registry.put(.common, common);
    _ = addModuleTest(b, test_step, "test-common", common);

    const chezmoi = chezmoi_build.createModule(b, .{
        .root_source_file = b.path(chezmoi_build.repo_root_source_file),
        .common = common,
        .target = config.target,
        .optimize = config.optimize,
    });
    registry.put(.chezmoi, chezmoi);
    _ = addModuleTest(b, test_step, "test-chezmoi", chezmoi);

    const bootstrap = bootstrap_build.createModule(b, .{
        .root_source_file = b.path(bootstrap_build.repo_root_source_file),
        .common = common,
        .target = config.target,
        .optimize = config.optimize,
    });
    registry.put(.bootstrap, bootstrap);
    _ = addModuleTest(b, test_step, "test-bootstrap", bootstrap);

    return registry;
}

pub fn addModuleTest(
    b: *std.Build,
    test_step: *std.Build.Step,
    name: []const u8,
    module: *std.Build.Module,
) *std.Build.Step.Compile {
    return common_build.addModuleTest(b, test_step, name, module);
}

pub fn build(b: *std.Build) void {
    const config: BuildConfig = .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };
    const test_step = b.step("test", "Run shared Zig library unit tests");

    const common = common_build.createModule(b, .{
        .root_source_file = b.path("common/" ++ common_build.local_root_source_file),
        .target = config.target,
        .optimize = config.optimize,
    });
    _ = addModuleTest(b, test_step, "test-common", common);

    const chezmoi = chezmoi_build.createModule(b, .{
        .root_source_file = b.path("chezmoi/" ++ chezmoi_build.local_root_source_file),
        .common = common,
        .target = config.target,
        .optimize = config.optimize,
    });
    _ = addModuleTest(b, test_step, "test-chezmoi", chezmoi);

    const bootstrap = bootstrap_build.createModule(b, .{
        .root_source_file = b.path("bootstrap/" ++ bootstrap_build.local_root_source_file),
        .common = common,
        .target = config.target,
        .optimize = config.optimize,
    });
    _ = addModuleTest(b, test_step, "test-bootstrap", bootstrap);
}

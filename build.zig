const std = @import("std");
const builtin = @import("builtin");
const zig_lib = @import("lib/zig/build.zig");

const ModuleKey = zig_lib.ModuleKey;

const linux_dmi_vendor_path = "/sys/class/dmi/id/sys_vendor";
const linux_dmi_board_vendor_path = "/sys/class/dmi/id/board_vendor";
const linux_dmi_product_name_path = "/sys/class/dmi/id/product_name";
const linux_dmi_chassis_type_path = "/sys/class/dmi/id/chassis_type";

const InstallPolicy = enum {
    never,
    tool,
    lenovo_tool,
    chezmoi_hook,
};

const TestFile = struct {
    name: []const u8,
    root: []const u8,
};

const ExecutableSpec = struct {
    name: []const u8,
    root: []const u8,
    imports: []const ModuleKey = &.{},
    frameworks: []const []const u8 = &.{},
    link_libc: bool = false,
    install: InstallPolicy = .never,
    extra_tests: []const TestFile = &.{},
};

const executables = [_]ExecutableSpec{
    .{
        .name = "run_once_zed_install_catppuccin_theme",
        .root = "dotfiles/.chezmoi-lib/scripts/run_once_zed_install_catppuccin_theme.zig",
        .imports = &.{.chezmoi},
        .install = .chezmoi_hook,
    },
    .{
        .name = "run_onchange_after_install-vs-extensions",
        .root = "dotfiles/.chezmoi-lib/scripts/run_onchange_after_install-vs-extensions.zig",
        .imports = &.{.chezmoi},
        .install = .chezmoi_hook,
    },
    .{
        .name = "run_onchange_after_nushell_init",
        .root = "dotfiles/.chezmoi-lib/scripts/run_onchange_after_nushell_init.zig",
        .imports = &.{.chezmoi},
        .install = .chezmoi_hook,
    },
    .{
        .name = "run_onchange_after_raycast_window_management",
        .root = "dotfiles/.chezmoi-lib/raycast_window_management/main.zig",
        .imports = &.{.chezmoi},
        .install = .chezmoi_hook,
    },
    .{
        .name = "run_onchange_after_yazi_init",
        .root = "dotfiles/.chezmoi-lib/scripts/run_onchange_after_yazi_init.zig",
        .imports = &.{.chezmoi},
        .install = .chezmoi_hook,
    },
    .{
        .name = "run_onchange_after_zsh_bash_init",
        .root = "dotfiles/.chezmoi-lib/scripts/run_onchange_after_zsh_bash_init.zig",
        .imports = &.{.chezmoi},
        .install = .chezmoi_hook,
    },
    .{
        .name = "gh-hide-comment",
        .root = "pkgs/gh-hide-comment/main.zig",
        .imports = &.{.common},
        .install = .tool,
        .extra_tests = &.{
            .{ .name = "gh-hide-comment-auth", .root = "pkgs/gh-hide-comment/auth.zig" },
            .{ .name = "gh-hide-comment-cli", .root = "pkgs/gh-hide-comment/cli.zig" },
            .{ .name = "gh-hide-comment-github", .root = "pkgs/gh-hide-comment/github.zig" },
            .{ .name = "gh-hide-comment-http", .root = "pkgs/gh-hide-comment/http.zig" },
            .{ .name = "gh-hide-comment-url", .root = "pkgs/gh-hide-comment/url.zig" },
        },
    },
    .{
        .name = "lenovo-con-mode",
        .root = "pkgs/lenovo-con-mode/main.zig",
        .imports = &.{.common},
        .install = .lenovo_tool,
        .extra_tests = &.{
            .{ .name = "lenovo-con-mode-cli", .root = "pkgs/lenovo-con-mode/cli.zig" },
            .{ .name = "lenovo-con-mode-constants", .root = "pkgs/lenovo-con-mode/constants.zig" },
            .{ .name = "lenovo-con-mode-linux", .root = "pkgs/lenovo-con-mode/linux.zig" },
            .{ .name = "lenovo-con-mode-platform", .root = "pkgs/lenovo-con-mode/platform.zig" },
            .{ .name = "lenovo-con-mode-windows", .root = "pkgs/lenovo-con-mode/windows.zig" },
        },
    },
    .{
        .name = "dev_tools",
        .root = "bootstrap/dev_tools/main.zig",
        .imports = &.{ .bootstrap, .common },
        .extra_tests = &.{
            .{ .name = "dev-tools-doctor", .root = "bootstrap/dev_tools/doctor.zig" },
            .{ .name = "dev-tools-tools", .root = "bootstrap/dev_tools/tools.zig" },
        },
    },
};

const BuildConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    install_chezmoi_hooks: bool,
};

pub fn build(b: *std.Build) void {
    const config: BuildConfig = .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .install_chezmoi_hooks = b.option(
            bool,
            "install-chezmoi-hooks",
            "Install compiled chezmoi hook scripts with the default install step",
        ) orelse false,
    };

    const check_step = b.step("check", "Compile all Zig executables without installing them");
    const test_step = b.step("test", "Run all Zig unit tests");
    const tools_step = b.step("tools", "Install command-line Zig tools for the selected target");
    const hooks_step = b.step("chezmoi-hooks", "Install compiled chezmoi hook scripts");

    const registry = zig_lib.addModules(b, .{
        .target = config.target,
        .optimize = config.optimize,
    }, test_step);

    inline for (executables) |spec| {
        addExecutable(spec, b, check_step, test_step, tools_step, hooks_step, config, registry);
    }
}

fn addExecutable(
    comptime spec: ExecutableSpec,
    b: *std.Build,
    check_step: *std.Build.Step,
    test_step: *std.Build.Step,
    tools_step: *std.Build.Step,
    hooks_step: *std.Build.Step,
    config: BuildConfig,
    registry: zig_lib.ModuleRegistry,
) void {
    const module = createRootModule(spec.root, spec.imports, spec.link_libc, b, config, registry);
    inline for (spec.frameworks) |framework| {
        module.linkFramework(framework, .{});
    }
    const exe = b.addExecutable(.{
        .name = spec.name,
        .root_module = module,
    });

    check_step.dependOn(&exe.step);
    const module_test = zig_lib.addModuleTest(b, test_step, b.fmt("test-{s}", .{spec.name}), module);
    _ = module_test;

    inline for (spec.extra_tests) |test_file| {
        const test_module = createRootModule(test_file.root, spec.imports, spec.link_libc, b, config, registry);
        inline for (spec.frameworks) |framework| {
            test_module.linkFramework(framework, .{});
        }
        const extra_test = zig_lib.addModuleTest(b, test_step, test_file.name, test_module);
        _ = extra_test;
    }

    addInstallEdges(b, tools_step, hooks_step, config, exe, spec.install);
}

fn createRootModule(
    comptime root: []const u8,
    comptime import_keys: []const ModuleKey,
    comptime link_libc: bool,
    b: *std.Build,
    config: BuildConfig,
    registry: zig_lib.ModuleRegistry,
) *std.Build.Module {
    var imports: [import_keys.len]std.Build.Module.Import = undefined;
    inline for (import_keys, 0..) |key, index| {
        imports[index] = .{
            .name = key.importName(),
            .module = registry.get(key),
        };
    }

    return b.createModule(.{
        .root_source_file = b.path(root),
        .imports = imports[0..],
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = link_libc,
    });
}

fn addInstallEdges(
    b: *std.Build,
    tools_step: *std.Build.Step,
    hooks_step: *std.Build.Step,
    config: BuildConfig,
    exe: *std.Build.Step.Compile,
    policy: InstallPolicy,
) void {
    if (policy == .never) return;
    if (policy == .lenovo_tool and !isLenovoToolTarget(b, config.target.result.os.tag)) return;

    const install = b.addInstallArtifact(exe, .{});

    switch (policy) {
        .never => unreachable,
        .tool, .lenovo_tool => {
            tools_step.dependOn(&install.step);
            b.getInstallStep().dependOn(&install.step);
        },
        .chezmoi_hook => {
            hooks_step.dependOn(&install.step);
            if (config.install_chezmoi_hooks) {
                b.getInstallStep().dependOn(&install.step);
            }
        },
    }
}

fn isLenovoToolTarget(b: *std.Build, os_tag: std.Target.Os.Tag) bool {
    if (os_tag != .linux and os_tag != .windows) return false;
    return isLenovoLaptopHost(b);
}

fn isLenovoLaptopHost(b: *std.Build) bool {
    return switch (builtin.os.tag) {
        .linux => isLinuxLenovoLaptopHost(b),
        .windows => isWindowsLenovoLaptopHost(b),
        else => false,
    };
}

fn isLinuxLenovoLaptopHost(b: *std.Build) bool {
    if (!linuxDmiIdentifiesLenovo(b)) return false;

    var chassis_buffer: [256]u8 = undefined;
    const chassis_type = readTrimmedAbsolute(b, linux_dmi_chassis_type_path, &chassis_buffer) orelse return false;
    return isLaptopChassisType(chassis_type);
}

fn linuxDmiIdentifiesLenovo(b: *std.Build) bool {
    var vendor_buffer: [256]u8 = undefined;
    if (readTrimmedAbsolute(b, linux_dmi_vendor_path, &vendor_buffer)) |vendor| {
        if (isLenovoVendor(vendor)) return true;
    }

    var board_vendor_buffer: [256]u8 = undefined;
    if (readTrimmedAbsolute(b, linux_dmi_board_vendor_path, &board_vendor_buffer)) |vendor| {
        if (isLenovoVendor(vendor)) return true;
    }

    var product_buffer: [256]u8 = undefined;
    if (readTrimmedAbsolute(b, linux_dmi_product_name_path, &product_buffer)) |product| {
        if (isLenovoVendor(product) or std.ascii.findIgnoreCase(product, "legion") != null) return true;
    }

    return false;
}

fn readTrimmedAbsolute(b: *std.Build, path: []const u8, buffer: []u8) ?[]const u8 {
    const contents = std.Io.Dir.cwd().readFile(b.graph.io, path, buffer) catch return null;
    return std.mem.trim(u8, contents, " \t\r\n");
}

fn isWindowsLenovoLaptopHost(b: *std.Build) bool {
    const result = std.process.run(b.allocator, b.graph.io, .{
        .argv = &.{
            "pwsh",
            "-NoProfile",
            "-Command",
            "$cs = Get-CimInstance Win32_ComputerSystem; " ++
                "$en = Get-CimInstance Win32_SystemEnclosure; " ++
                "\"$($cs.Manufacturer)`n$($cs.Model)`n$($en.ChassisTypes -join ',')\"",
        },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    }) catch return false;
    defer b.allocator.free(result.stdout);
    defer b.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return false,
        else => return false,
    }

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    const manufacturer = std.mem.trim(u8, lines.next() orelse "", " \t\r\n");
    const model = std.mem.trim(u8, lines.next() orelse "", " \t\r\n");
    const chassis_types = std.mem.trim(u8, lines.next() orelse "", " \t\r\n");
    if (!isLenovoVendor(manufacturer) and
        !isLenovoVendor(model) and
        std.ascii.findIgnoreCase(model, "legion") == null)
    {
        return false;
    }

    var chassis_values = std.mem.splitScalar(u8, chassis_types, ',');
    while (chassis_values.next()) |raw| {
        if (isLaptopChassisType(std.mem.trim(u8, raw, " \t\r\n"))) return true;
    }
    return false;
}

fn isLenovoVendor(value: []const u8) bool {
    return std.ascii.findIgnoreCase(value, "lenovo") != null;
}

fn isLaptopChassisType(value: []const u8) bool {
    const parsed = std.fmt.parseInt(u8, value, 10) catch return false;
    return switch (parsed) {
        8, 9, 10, 14, 31, 32 => true,
        else => false,
    };
}

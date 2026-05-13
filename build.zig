const std = @import("std");

const ZigExecutable = struct {
    name: []const u8,
    path: []const u8,
    link_libc: bool = true,
};

const chezmoi_scripts = [_]ZigExecutable{
    .{
        .name = "run_once_zed_install_catppuccin_theme",
        .path = "dotfiles/.chezmoiscripts/run_once_zed_install_catppuccin_theme.zig",
    },
    .{
        .name = "run_onchange_after_install-vs-extensions",
        .path = "dotfiles/.chezmoiscripts/run_onchange_after_install-vs-extensions.zig",
    },
    .{
        .name = "run_onchange_after_nushell_init",
        .path = "dotfiles/.chezmoiscripts/run_onchange_after_nushell_init.zig",
    },
    .{
        .name = "run_onchange_after_raycast_window_management",
        .path = "dotfiles/.chezmoiscripts/run_onchange_after_raycast_window_management.zig",
    },
    .{
        .name = "run_onchange_after_yazi_init",
        .path = "dotfiles/.chezmoiscripts/run_onchange_after_yazi_init.zig",
    },
    .{
        .name = "run_onchange_after_zsh_bash_init",
        .path = "dotfiles/.chezmoiscripts/run_onchange_after_zsh_bash_init.zig",
    },
};

const package_scripts = [_]ZigExecutable{
    .{ .name = "gh-hide-comment", .path = "scripts/gh-hide-comment/main.zig" },
    .{ .name = "lenovo-con-mode", .path = "scripts/lenovo-con-mode/main.zig", .link_libc = false },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const check_step = b.step("check", "Compile Zig scripts without installing them");
    const test_step = b.step("test", "Run Zig unit tests");

    const chezmoi = b.createModule(.{
        .root_source_file = b.path("lib/zig/chezmoi/script.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const chezmoi_tests = b.addTest(.{
        .root_module = chezmoi,
    });
    test_step.dependOn(&b.addRunArtifact(chezmoi_tests).step);

    for (chezmoi_scripts) |script| {
        addScript(b, check_step, test_step, target, optimize, script, chezmoi);
    }

    for (package_scripts) |script| {
        addScript(b, check_step, test_step, target, optimize, script, null);
    }
}

fn addScript(
    b: *std.Build,
    check_step: *std.Build.Step,
    test_step: *std.Build.Step,
    target: anytype,
    optimize: std.builtin.OptimizeMode,
    script: ZigExecutable,
    chezmoi: ?*std.Build.Module,
) void {
    const module = b.createModule(.{
        .root_source_file = b.path(script.path),
        .target = target,
        .optimize = optimize,
        .link_libc = script.link_libc,
    });
    if (chezmoi) |dependency| module.addImport("chezmoi", dependency);

    const exe = b.addExecutable(.{
        .name = script.name,
        .root_module = module,
    });
    check_step.dependOn(&exe.step);

    const unit_tests = b.addTest(.{
        .root_module = module,
    });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);
}

const std = @import("std");
const common = @import("common");

const model = @import("../manifest.zig");

pub const Diagnostics = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Diagnostic) = .empty,

    pub fn init(allocator: std.mem.Allocator) Diagnostics {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Diagnostics) void {
        for (self.entries.items) |entry| entry.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn add(self: *Diagnostics, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        errdefer self.allocator.free(message);
        try self.entries.append(self.allocator, .{ .message = message });
    }

    pub fn write(self: Diagnostics, io: std.Io) !void {
        for (self.entries.items) |entry| {
            try common.output.stderr(io, "error: manifest: {s}\n", .{entry.message});
        }
    }
};

pub const Diagnostic = struct {
    message: []const u8,

    fn deinit(self: Diagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
};

pub fn validate(catalog: model.Catalog, diagnostics: *Diagnostics) !void {
    try validateTools(catalog.tools, diagnostics);
}

fn validateTools(tools: []const model.Tool, diagnostics: *Diagnostics) !void {
    if (tools.len == 0) return fail(diagnostics, "tools: must not be empty", .{});

    var seen_tools = std.StringHashMap(usize).init(diagnostics.allocator);
    defer seen_tools.deinit();
    var seen_bins = std.StringHashMap(BinLocation).init(diagnostics.allocator);
    defer seen_bins.deinit();

    for (tools, 0..) |tool_entry, tool_index| {
        try validateTool(tool_entry, tool_index, diagnostics);

        if (seen_tools.get(tool_entry.name)) |first_index| {
            return fail(
                diagnostics,
                "tools[{d}].name: duplicate tool name also used by tools[{d}]",
                .{ tool_index, first_index },
            );
        }
        try seen_tools.put(tool_entry.name, tool_index);

        for (tool_entry.bins, 0..) |bin_entry, bin_index| {
            if (seen_bins.get(bin_entry.name)) |first| {
                return fail(
                    diagnostics,
                    "tools[{d}].bins[{d}].name: duplicate bin name also used by tools[{d}].bins[{d}]",
                    .{ tool_index, bin_index, first.tool_index, first.bin_index },
                );
            }
            try seen_bins.put(bin_entry.name, .{ .tool_index = tool_index, .bin_index = bin_index });
        }
    }
}

const BinLocation = struct {
    tool_index: usize,
    bin_index: usize,
};

fn validateTool(tool_entry: model.Tool, tool_index: usize, diagnostics: *Diagnostics) !void {
    if (tool_entry.name.len == 0) return fail(diagnostics, "tools[{d}].name: must not be empty", .{tool_index});
    if (tool_entry.bins.len == 0) return fail(diagnostics, "tools[{d}].bins: must not be empty", .{tool_index});
    for (tool_entry.bins, 0..) |bin_entry, bin_index| {
        if (bin_entry.name.len == 0) {
            return fail(diagnostics, "tools[{d}].bins[{d}].name: must not be empty", .{ tool_index, bin_index });
        }
        if (bin_entry.version_argv.len == 0) {
            return fail(
                diagnostics,
                "tools[{d}].bins[{d}].version_argv: must not be empty",
                .{ tool_index, bin_index },
            );
        }
        for (bin_entry.version_argv, 0..) |arg, arg_index| {
            if (arg.len == 0) {
                return fail(
                    diagnostics,
                    "tools[{d}].bins[{d}].version_argv[{d}]: must not be empty",
                    .{ tool_index, bin_index, arg_index },
                );
            }
        }
    }

    switch (tool_entry.action) {
        .required => {},
        .archive => |archive_action| try validateArchiveAction(archive_action, tool_index, diagnostics),
        .package => |package_spec| {
            if (package_spec.name.len == 0) {
                return fail(diagnostics, actionPath("package.name") ++ ": must not be empty", .{tool_index});
            }
            try validateArgv(
                actionPath("package.install_argv"),
                package_spec.install_argv,
                .{tool_index},
                &.{"package"},
                diagnostics,
            );
        },
        .build => |build_spec| {
            if (build_spec.path.len == 0) {
                return fail(diagnostics, actionPath("build.path") ++ ": must not be empty", .{tool_index});
            }
            try validateArgv(
                actionPath("build.argv"),
                build_spec.argv,
                .{tool_index},
                &.{ "repo_dir", "build_dir", "prefix", "tool", "zig" },
                diagnostics,
            );
            try validateLinks(actionPath("build.links"), false, build_spec.links, .{tool_index}, diagnostics);
        },
        .script => |script_spec| try validateScriptAction(script_spec, tool_index, diagnostics),
        .toolchain => |toolchain| try validateToolchainAction(toolchain, tool_index, diagnostics),
    }
}

fn actionPath(comptime suffix: []const u8) []const u8 {
    return "tools[{d}].action." ++ suffix;
}

fn validateToolchainAction(toolchain: model.Toolchain, tool_index: usize, diagnostics: *Diagnostics) !void {
    if (toolchain.manager_bin.len == 0) {
        return fail(diagnostics, actionPath("toolchain.manager_bin") ++ ": must not be empty", .{tool_index});
    }
    if (toolchain.name.len == 0) {
        return fail(diagnostics, actionPath("toolchain.name") ++ ": must not be empty", .{tool_index});
    }
    if (toolchain.name_env) |name_env| {
        if (name_env.len == 0) {
            return fail(diagnostics, actionPath("toolchain.name_env") ++ ": must not be empty", .{tool_index});
        }
    }
    if (toolchain.bin_dir.env_var) |env_var| {
        if (env_var.len == 0) {
            return fail(diagnostics, actionPath("toolchain.bin_dir.env_var") ++ ": must not be empty", .{tool_index});
        }
    }
    if (toolchain.bin_dir.home_relative.len == 0) {
        return fail(diagnostics, actionPath("toolchain.bin_dir.home_relative") ++ ": must not be empty", .{tool_index});
    }
    if (toolchain.components.len == 0) {
        return fail(diagnostics, actionPath("toolchain.components") ++ ": must not be empty", .{tool_index});
    }
    for (toolchain.components, 0..) |component, component_index| {
        if (component.len == 0) {
            return fail(
                diagnostics,
                actionPath("toolchain.components[{d}]") ++ ": must not be empty",
                .{ tool_index, component_index },
            );
        }
    }
    if (toolchain.install.unix == null and toolchain.install.windows == null) {
        return fail(
            diagnostics,
            actionPath("toolchain.install") ++ ": must define unix or windows command",
            .{tool_index},
        );
    }
    if (toolchain.install.unix) |command| {
        try validateToolchainInstallCommand(
            actionPath("toolchain.install.unix"),
            command,
            .{tool_index},
            diagnostics,
        );
    }
    if (toolchain.install.windows) |command| {
        try validateToolchainInstallCommand(
            actionPath("toolchain.install.windows"),
            command,
            .{tool_index},
            diagnostics,
        );
    }
    try validateArgv(
        actionPath("toolchain.update_argv"),
        toolchain.update_argv,
        .{tool_index},
        &.{ "manager_bin", "toolchain", "components" },
        diagnostics,
    );
    try validateArgv(
        actionPath("toolchain.active_argv"),
        toolchain.active_argv,
        .{tool_index},
        &.{ "manager_bin", "toolchain" },
        diagnostics,
    );
    try validateArgv(
        actionPath("toolchain.default_argv"),
        toolchain.default_argv,
        .{tool_index},
        &.{ "manager_bin", "toolchain" },
        diagnostics,
    );
    try validateArgv(
        actionPath("toolchain.component_argv"),
        toolchain.component_argv,
        .{tool_index},
        &.{"component"},
        diagnostics,
    );
}

fn validateToolchainInstallCommand(
    comptime path_fmt: []const u8,
    command: model.Toolchain.Install.Command,
    args: anytype,
    diagnostics: *Diagnostics,
) !void {
    if (command.url.len == 0) return fail(diagnostics, path_fmt ++ ".url: must not be empty", args);
    if (command.file.len == 0) return fail(diagnostics, path_fmt ++ ".file: must not be empty", args);
    try validateArgv(
        path_fmt ++ ".argv",
        command.argv,
        args,
        &.{ "file", "toolchain", "components" },
        diagnostics,
    );
}

fn validateArchiveAction(archive_spec: model.Archive, tool_index: usize, diagnostics: *Diagnostics) !void {
    if (archive_spec.source) |source| try validateSource(actionPath("source"), source, .{tool_index}, diagnostics);
    if (archive_spec.platforms.len == 0) {
        return fail(diagnostics, actionPath("platforms") ++ ": must not be empty", .{tool_index});
    }
    for (archive_spec.platforms, 0..) |case, platform_index| {
        if (case.platform.len == 0) {
            return fail(
                diagnostics,
                actionPath("platforms[{d}].platform") ++ ": must not be empty",
                .{ tool_index, platform_index },
            );
        }
        try validateTemplate(
            actionPath("platforms[{d}].platform"),
            case.platform,
            .{ tool_index, platform_index },
            &.{},
            diagnostics,
        );
        if (case.source) |source| {
            try validateSource(
                actionPath("platforms[{d}].source"),
                source,
                .{ tool_index, platform_index },
                diagnostics,
            );
        } else if (archive_spec.source == null) {
            return fail(
                diagnostics,
                actionPath("platforms[{d}].source") ++ ": required when action.source is missing",
                .{ tool_index, platform_index },
            );
        }
        try validateLinks(
            actionPath("platforms[{d}].links"),
            true,
            case.links,
            .{ tool_index, platform_index },
            diagnostics,
        );
        try validateLinks(
            actionPath("platforms[{d}].app_links"),
            false,
            case.app_links,
            .{ tool_index, platform_index },
            diagnostics,
        );
    }
}

fn validateLinks(
    comptime path_fmt: []const u8,
    comptime require_non_empty: bool,
    entries: []const model.Link,
    args: anytype,
    diagnostics: *Diagnostics,
) !void {
    if (require_non_empty and entries.len == 0) {
        return fail(diagnostics, path_fmt ++ ": must not be empty", args);
    }
    for (entries, 0..) |link_entry, link_index| {
        if (link_entry.name.len == 0) {
            return fail(diagnostics, path_fmt ++ "[{d}].name: must not be empty", args ++ .{link_index});
        }
        if (link_entry.path.len == 0) {
            return fail(diagnostics, path_fmt ++ "[{d}].path: must not be empty", args ++ .{link_index});
        }
        try validateTemplate(
            path_fmt ++ "[{d}].path",
            link_entry.path,
            args ++ .{link_index},
            &.{ "version", "platform" },
            diagnostics,
        );
    }
}

fn validateScriptAction(script_spec: model.Script, tool_index: usize, diagnostics: *Diagnostics) !void {
    if (script_spec.unix == null and script_spec.windows == null) {
        return fail(diagnostics, actionPath("script") ++ ": must define unix or windows command", .{tool_index});
    }
    if (script_spec.unix) |command| {
        try validateScriptCommand(actionPath("script.unix"), command, .{tool_index}, diagnostics);
    }
    if (script_spec.windows) |command| {
        try validateScriptCommand(actionPath("script.windows"), command, .{tool_index}, diagnostics);
    }
}

fn validateScriptCommand(
    comptime path_fmt: []const u8,
    command: model.Script.Command,
    args: anytype,
    diagnostics: *Diagnostics,
) !void {
    if (command.url.len == 0) return fail(diagnostics, path_fmt ++ ".url: must not be empty", args);
    if (command.file.len == 0) return fail(diagnostics, path_fmt ++ ".file: must not be empty", args);
    try validateArgv(
        path_fmt ++ ".argv",
        command.argv,
        args,
        &.{ "file", "bin_dir", "opt_dir", "home" },
        diagnostics,
    );
}

fn validateSource(comptime path_fmt: []const u8, source: model.Source, args: anytype, diagnostics: *Diagnostics) !void {
    switch (source) {
        .github_latest => |github| {
            if (github.repo.len == 0) return fail(diagnostics, path_fmt ++ ".repo: must not be empty", args);
            if (github.asset.len == 0) return fail(diagnostics, path_fmt ++ ".asset: must not be empty", args);
            try validateTemplate(path_fmt ++ ".asset", github.asset, args, &.{ "version", "platform" }, diagnostics);
        },
        .direct => |direct_source| {
            if (direct_source.version.len == 0) {
                return fail(diagnostics, path_fmt ++ ".version: must not be empty", args);
            }
            if (direct_source.url.len == 0) return fail(diagnostics, path_fmt ++ ".url: must not be empty", args);
            try validateTemplate(path_fmt ++ ".url", direct_source.url, args, &.{ "version", "platform" }, diagnostics);
        },
        .command => |command_source| {
            try validateArgv(path_fmt ++ ".argv", command_source.argv, args, &.{}, diagnostics);
            if (command_source.url.len == 0) return fail(diagnostics, path_fmt ++ ".url: must not be empty", args);
            try validateTemplate(
                path_fmt ++ ".url",
                command_source.url,
                args,
                &.{ "version", "platform" },
                diagnostics,
            );
        },
        .version_index => |version_index| {
            if (version_index.index_url.len == 0) {
                return fail(diagnostics, path_fmt ++ ".index_url: must not be empty", args);
            }
            if (version_index.url.len == 0) return fail(diagnostics, path_fmt ++ ".url: must not be empty", args);
            try validateTemplate(path_fmt ++ ".url", version_index.url, args, &.{ "version", "platform" }, diagnostics);
        },
    }
}

fn validateArgv(
    comptime path_fmt: []const u8,
    argv: []const []const u8,
    args: anytype,
    allowed: []const []const u8,
    diagnostics: *Diagnostics,
) !void {
    if (argv.len == 0) return fail(diagnostics, path_fmt ++ ": must not be empty", args);
    for (argv, 0..) |arg, arg_index| {
        if (arg.len == 0) return fail(diagnostics, path_fmt ++ "[{d}]: must not be empty", args ++ .{arg_index});
        try validateTemplate(path_fmt ++ "[{d}]", arg, args ++ .{arg_index}, allowed, diagnostics);
    }
}

fn validateTemplate(
    comptime path_fmt: []const u8,
    template: []const u8,
    args: anytype,
    allowed: []const []const u8,
    diagnostics: *Diagnostics,
) !void {
    common.template.Template.literal(template).validate(allowed) catch |err| switch (err) {
        error.InvalidTemplate => return fail(diagnostics, path_fmt ++ ": invalid template placeholder", args),
        error.UnknownTemplateVariable => return fail(diagnostics, path_fmt ++ ": unknown template placeholder", args),
    };
}

fn fail(diagnostics: *Diagnostics, comptime fmt: []const u8, args: anytype) error{ OutOfMemory, InvalidManifest } {
    try diagnostics.add(fmt, args);
    return error.InvalidManifest;
}

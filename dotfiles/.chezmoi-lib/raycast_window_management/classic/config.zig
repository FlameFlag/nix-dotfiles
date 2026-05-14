const std = @import("std");
const script = @import("chezmoi");
const constants = @import("constants.zig");
const Database = @import("database.zig").Database;

pub const WindowConfig = struct {
    parsed: std.json.Parsed(WindowConfigJson),

    pub fn deinit(self: *WindowConfig) void {
        self.parsed.deinit();
        self.* = undefined;
    }
};

pub const WindowConfigJson = struct {
    hotkeys: ?std.json.ArrayHashMap(?[]const u8) = null,
    disabledCommands: ?[]const []const u8 = null,
};

pub fn loadConfig(rt: *script.Runtime, path: []const u8) !WindowConfig {
    const contents = try std.Io.Dir.cwd().readFileAlloc(
        rt.io,
        path,
        rt.allocator,
        .limited(constants.config_read_limit),
    );
    defer rt.allocator.free(contents);

    var config = try parseWindowConfig(rt.allocator, contents);
    errdefer config.deinit();

    try validateConfig(config);

    return config;
}

fn parseWindowConfig(allocator: script.Allocator, contents: []const u8) !WindowConfig {
    return .{ .parsed = try std.json.parseFromSlice(WindowConfigJson, allocator, contents, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) };
}

pub fn validateConfig(config: WindowConfig) !void {
    if (config.parsed.value.hotkeys) |hotkeys| {
        var iterator = hotkeys.map.iterator();
        while (iterator.next()) |entry| try validateCommand(entry.key_ptr.*);
    }
    if (config.parsed.value.disabledCommands) |disabled_commands| {
        for (disabled_commands) |command| try validateCommand(command);
    }
}

fn validateCommand(command: []const u8) !void {
    if (!std.mem.startsWith(u8, command, constants.command_prefix)) return error.InvalidRaycastConfig;
}

pub fn warnMissingConfiguredCommands(
    rt: *script.Runtime,
    known_commands: *const std.array_hash_map.String(void),
    config: WindowConfig,
) !void {
    var missing = try collectMissingConfiguredCommands(rt.allocator, known_commands, config);
    defer missing.deinit(rt.allocator);

    for (missing.keys()) |command| {
        try rt.stderr.print(
            "warn: Raycast command not found in local database yet; update may be skipped: {s}\n",
            .{command},
        );
    }
    if (missing.count() > 0) try rt.stderr.flush();
}

fn collectMissingConfiguredCommands(
    allocator: script.Allocator,
    known_commands: *const std.array_hash_map.String(void),
    config: WindowConfig,
) !std.array_hash_map.String(void) {
    var missing: std.array_hash_map.String(void) = .empty;
    errdefer missing.deinit(allocator);

    if (config.parsed.value.hotkeys) |hotkeys| {
        var iterator = hotkeys.map.iterator();
        while (iterator.next()) |entry| {
            try putMissingCommand(allocator, &missing, known_commands, entry.key_ptr.*);
        }
    }
    if (config.parsed.value.disabledCommands) |disabled_commands| {
        for (disabled_commands) |command| {
            try putMissingCommand(allocator, &missing, known_commands, command);
        }
    }

    return missing;
}

fn putMissingCommand(
    allocator: script.Allocator,
    missing: *std.array_hash_map.String(void),
    known_commands: *const std.array_hash_map.String(void),
    command: []const u8,
) !void {
    if (known_commands.contains(command) or missing.contains(command)) return;
    try missing.put(allocator, command, {});
}

pub fn deinitOwnedKeySet(allocator: script.Allocator, set: *std.array_hash_map.String(void)) void {
    for (set.keys()) |key| allocator.free(key);
    set.deinit(allocator);
}

pub fn applyHotkeys(db: Database, maybe_hotkeys: ?std.json.ArrayHashMap(?[]const u8)) !void {
    const hotkeys = maybe_hotkeys orelse return;
    var iterator = hotkeys.map.iterator();
    while (iterator.next()) |entry| {
        try db.run("UPDATE search SET hotkey = ? WHERE key = ?", &.{ entry.value_ptr.*, entry.key_ptr.* });
    }
}

pub fn upsertDisabledCommands(
    rt: *script.Runtime,
    db: Database,
    disabled_commands: []const []const u8,
) !void {
    const configuration = try std.fmt.allocPrint(rt.allocator, "{f}", .{std.json.fmt(.{
        .disabledCommands = disabled_commands,
    }, .{ .whitespace = .minified })});
    defer rt.allocator.free(configuration);

    try db.run(
        \\INSERT INTO raycastConfiguration (extensionId, configuration, updatedAt)
        \\VALUES (?, ?, strftime('%Y-%m-%d %H:%M:%f', 'now'))
        \\ON CONFLICT(extensionId) DO UPDATE SET
        \\    configuration = excluded.configuration,
        \\    updatedAt = excluded.updatedAt
    , &.{ constants.extension_id, configuration });
}

test "validateConfig allows only Raycast window-management command keys" {
    const valid_json =
        \\{
        \\  "hotkeys": {
        \\    "builtin_command_windowManagement_leftHalf": "cmd+left",
        \\    "builtin_command_windowManagement_rightHalf": null
        \\  },
        \\  "disabledCommands": ["builtin_command_windowManagement_center"]
        \\}
    ;
    var valid: WindowConfig = .{
        .parsed = try std.json.parseFromSlice(
            WindowConfigJson,
            std.testing.allocator,
            valid_json,
            .{},
        ),
    };
    defer valid.deinit();
    try validateConfig(valid);

    const invalid_json =
        \\{"disabledCommands":["builtin_command_otherExtension"]}
    ;
    var invalid: WindowConfig = .{
        .parsed = try std.json.parseFromSlice(
            WindowConfigJson,
            std.testing.allocator,
            invalid_json,
            .{},
        ),
    };
    defer invalid.deinit();
    try std.testing.expectError(error.InvalidRaycastConfig, validateConfig(invalid));
}

test "parseWindowConfig owns strings after source buffer is freed" {
    const config_json =
        \\{
        \\  "hotkeys": {
        \\    "builtin_command_windowManagementLeftHalf": "cmd+left"
        \\  }
        \\}
    ;
    const buffer = try std.testing.allocator.dupe(u8, config_json);
    var config = try parseWindowConfig(std.testing.allocator, buffer);
    std.testing.allocator.free(buffer);
    defer config.deinit();

    var iterator = config.parsed.value.hotkeys.?.map.iterator();
    const entry = iterator.next() orelse return error.TestExpectedHotkey;
    try std.testing.expectEqualStrings("builtin_command_windowManagementLeftHalf", entry.key_ptr.*);
    try std.testing.expectEqualStrings("cmd+left", entry.value_ptr.*.?);
}

test "collectMissingConfiguredCommands reports unknown local database rows without duplicates" {
    const config_json =
        \\{
        \\  "hotkeys": {
        \\    "builtin_command_windowManagementLeftHalf": "cmd+left",
        \\    "builtin_command_windowManagementRightHalf": "cmd+right"
        \\  },
        \\  "disabledCommands": [
        \\    "builtin_command_windowManagementRightHalf",
        \\    "builtin_command_windowManagementTopHalf"
        \\  ]
        \\}
    ;
    var config: WindowConfig = .{
        .parsed = try std.json.parseFromSlice(
            WindowConfigJson,
            std.testing.allocator,
            config_json,
            .{},
        ),
    };
    defer config.deinit();

    var known_commands: std.array_hash_map.String(void) = .empty;
    defer known_commands.deinit(std.testing.allocator);
    try known_commands.put(std.testing.allocator, "builtin_command_windowManagementLeftHalf", {});

    var missing = try collectMissingConfiguredCommands(std.testing.allocator, &known_commands, config);
    defer missing.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), missing.count());
    try std.testing.expectEqualStrings("builtin_command_windowManagementRightHalf", missing.keys()[0]);
    try std.testing.expectEqualStrings("builtin_command_windowManagementTopHalf", missing.keys()[1]);
}

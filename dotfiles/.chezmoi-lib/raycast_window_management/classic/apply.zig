const std = @import("std");
const script = @import("chezmoi");

const constants = @import("constants.zig");
const config_mod = @import("config.zig");
const crypto = @import("crypto.zig");
const db_mod = @import("database.zig");
const sql = @import("sqlcipher.zig");

const Database = db_mod.Database;
const WindowConfig = config_mod.WindowConfig;

pub fn applyConfig(rt: *script.Runtime, paths: anytype) !void {
    try rt.stderr.print("info: Applying Raycast window-management settings...\n", .{});
    try rt.stderr.flush();
    const password = try crypto.databasePassword(rt);
    defer rt.allocator.free(password);

    var config = try config_mod.loadConfig(rt, paths.config);
    defer config.deinit();

    var sqlcipher = try sql.SqlCipher.load(rt);
    defer sqlcipher.deinit();

    const db = try Database.open(&sqlcipher, rt.allocator, paths.db, password);
    defer db.close();

    try applyWindowConfig(rt, db, config);
}

/// Applies only validated commands and commits all database changes together.
fn applyWindowConfig(rt: *script.Runtime, db: Database, config: WindowConfig) !void {
    var known_commands = try loadKnownCommands(rt, db);
    defer config_mod.deinitOwnedKeySet(rt.allocator, &known_commands);
    try config_mod.warnMissingConfiguredCommands(rt, &known_commands, config);

    try db.exec("BEGIN");
    errdefer db.rollbackWithWarning();
    try db.run("UPDATE search SET hotkey = NULL WHERE key LIKE ?", &.{constants.command_prefix ++ "%"});
    try config_mod.applyHotkeys(db, config.parsed.value.hotkeys);
    try config_mod.upsertDisabledCommands(rt, db, config.parsed.value.disabledCommands orelse &.{});
    try db.exec("COMMIT");
}

fn loadKnownCommands(rt: *script.Runtime, db: Database) !std.array_hash_map.String(void) {
    var known_commands: std.array_hash_map.String(void) = .empty;
    errdefer config_mod.deinitOwnedKeySet(rt.allocator, &known_commands);

    var statement = try db.prepare("SELECT key FROM search WHERE key LIKE ?");
    defer statement.finalize();
    try statement.bindAll(&.{constants.command_prefix ++ "%"});

    while (try statement.step() == .row) {
        const key = try rt.allocator.dupe(u8, try statement.text(0));
        errdefer rt.allocator.free(key);
        try known_commands.put(rt.allocator, key, {});
    }

    return known_commands;
}

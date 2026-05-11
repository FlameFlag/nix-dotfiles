const std = @import("std");
const builtin = @import("builtin");
const script = @import("script.zig");

const domain = "com.raycast.macos";
const raycast_bin = "/Applications/Raycast.app/Contents/MacOS/Raycast";
const extension_id = "builtin_package_windowManagement";
const command_prefix = "builtin_command_windowManagement";

const sqlite_ok = 0;
const sqlite_row = 100;
const sqlite_done = 101;
const sqlite_transient: ?*const anyopaque = @ptrFromInt(std.math.maxInt(usize));

const sqlite3 = opaque {};
const sqlite3_stmt = opaque {};

const RaycastPaths = struct {
    config: []u8,
    db: []u8,

    fn deinit(self: RaycastPaths, allocator: script.Allocator) void {
        allocator.free(self.config);
        allocator.free(self.db);
    }
};

const WindowConfig = struct {
    parsed: std.json.Parsed(WindowConfigJson),

    fn deinit(self: *WindowConfig) void {
        self.parsed.deinit();
    }
};

const WindowConfigJson = struct {
    hotkeys: ?std.json.ArrayHashMap(?[]const u8) = null,
    disabledCommands: ?[]const []const u8 = null,
};

const Database = struct {
    sqlcipher: *SqlCipher,
    handle: ?*sqlite3,

    /// Opens Raycast's SQLCipher database and applies the key pragma.
    fn open(sqlcipher: *SqlCipher, allocator: script.Allocator, path: []const u8, password: []const u8) !Database {
        const db_path = try allocator.dupeZ(u8, path);
        defer allocator.free(db_path);

        var handle: ?*sqlite3 = null;
        try expectSql(sqlcipher.open(db_path, &handle), handle, sqlcipher);
        errdefer _ = sqlcipher.close(handle);

        var db: Database = .{ .sqlcipher = sqlcipher, .handle = handle };
        const pragma = try std.fmt.allocPrint(allocator, "PRAGMA key = \"{s}\"", .{password});
        defer allocator.free(pragma);
        const pragma_z = try allocator.dupeZ(u8, pragma);
        defer allocator.free(pragma_z);
        try db.exec(pragma_z);
        return db;
    }

    fn close(self: Database) void {
        _ = self.sqlcipher.close(self.handle);
    }

    fn exec(self: Database, sql: [:0]const u8) !void {
        var message: ?[*:0]u8 = null;
        const rc = self.sqlcipher.exec(self.handle, sql, null, null, &message);
        defer if (message) |value| self.sqlcipher.free(value);
        try expectSql(rc, self.handle, self.sqlcipher);
    }

    fn prepare(self: Database, sql: [:0]const u8) !Statement {
        var handle: ?*sqlite3_stmt = null;
        try expectSql(self.sqlcipher.prepare_v2(self.handle, sql, -1, &handle, null), self.handle, self.sqlcipher);
        return .{ .db = self, .handle = handle };
    }

    fn run(self: Database, sql: [:0]const u8, values: []const ?[]const u8) !void {
        var statement = try self.prepare(sql);
        defer statement.finalize();
        try statement.bindAll(values);
        try statement.expectDone();
    }

    fn transaction(self: Database, comptime body: fn (Database) anyerror!void) !void {
        try self.exec("BEGIN");
        errdefer self.exec("ROLLBACK") catch {};
        try body(self);
        try self.exec("COMMIT");
    }
};

const Statement = struct {
    db: Database,
    handle: ?*sqlite3_stmt,

    fn finalize(self: Statement) void {
        _ = self.db.sqlcipher.finalize(self.handle);
    }

    fn bindAll(self: Statement, values: []const ?[]const u8) !void {
        for (values, 1..) |value, index| {
            try self.bind(@intCast(index), value);
        }
    }

    fn bind(self: Statement, index: c_int, value: ?[]const u8) !void {
        const rc = if (value) |bytes|
            self.db.sqlcipher.bind_text(self.handle, index, bytes.ptr, @intCast(bytes.len), sqlite_transient)
        else
            self.db.sqlcipher.bind_null(self.handle, index);
        try expectSql(rc, self.db.handle, self.db.sqlcipher);
    }

    fn step(self: Statement) !StepResult {
        const rc = self.db.sqlcipher.step(self.handle);
        return switch (rc) {
            sqlite_row => .row,
            sqlite_done => .done,
            else => {
                try expectSql(rc, self.db.handle, self.db.sqlcipher);
                return error.UnexpectedRaycastDatabase;
            },
        };
    }

    fn expectDone(self: Statement) !void {
        if (try self.step() == .done) return;
        return error.UnexpectedRaycastDatabase;
    }

    fn text(self: Statement, column: c_int) ![]const u8 {
        const value = self.db.sqlcipher.column_text(self.handle, column) orelse return error.UnexpectedRaycastDatabase;
        return std.mem.span(value);
    }
};

const StepResult = enum { row, done };

const SqlCipher = struct {
    lib: std.DynLib,
    stderr: *std.Io.Writer,
    open: *const fn ([*:0]const u8, *?*sqlite3) callconv(.c) c_int,
    close: *const fn (?*sqlite3) callconv(.c) c_int,
    exec: *const fn (?*sqlite3, [*:0]const u8, ?*const fn (?*anyopaque, c_int, ?[*]?[*:0]u8, ?[*]?[*:0]u8) callconv(.c) c_int, ?*anyopaque, *?[*:0]u8) callconv(.c) c_int,
    errmsg: *const fn (?*sqlite3) callconv(.c) [*:0]const u8,
    free: *const fn (?*anyopaque) callconv(.c) void,
    prepare_v2: *const fn (?*sqlite3, [*:0]const u8, c_int, *?*sqlite3_stmt, ?*[*:0]const u8) callconv(.c) c_int,
    step: *const fn (?*sqlite3_stmt) callconv(.c) c_int,
    finalize: *const fn (?*sqlite3_stmt) callconv(.c) c_int,
    bind_text: *const fn (?*sqlite3_stmt, c_int, [*]const u8, c_int, ?*const anyopaque) callconv(.c) c_int,
    bind_null: *const fn (?*sqlite3_stmt, c_int) callconv(.c) c_int,
    column_text: *const fn (?*sqlite3_stmt, c_int) callconv(.c) ?[*:0]const u8,

    /// Loads SQLCipher from the environment or common system locations.
    fn load(rt: *script.Runtime) !SqlCipher {
        var lib = if (rt.env.get("SQLCIPHER_LIB")) |path|
            std.DynLib.open(path) catch try openSqlCipherFromDefaults(rt)
        else
            try openSqlCipherFromDefaults(rt);
        errdefer lib.close();

        return .{
            .lib = lib,
            .stderr = rt.stderr,
            .open = try lookup(@TypeOf(@as(SqlCipher, undefined).open), &lib, "sqlite3_open"),
            .close = try lookup(@TypeOf(@as(SqlCipher, undefined).close), &lib, "sqlite3_close"),
            .exec = try lookup(@TypeOf(@as(SqlCipher, undefined).exec), &lib, "sqlite3_exec"),
            .errmsg = try lookup(@TypeOf(@as(SqlCipher, undefined).errmsg), &lib, "sqlite3_errmsg"),
            .free = try lookup(@TypeOf(@as(SqlCipher, undefined).free), &lib, "sqlite3_free"),
            .prepare_v2 = try lookup(@TypeOf(@as(SqlCipher, undefined).prepare_v2), &lib, "sqlite3_prepare_v2"),
            .step = try lookup(@TypeOf(@as(SqlCipher, undefined).step), &lib, "sqlite3_step"),
            .finalize = try lookup(@TypeOf(@as(SqlCipher, undefined).finalize), &lib, "sqlite3_finalize"),
            .bind_text = try lookup(@TypeOf(@as(SqlCipher, undefined).bind_text), &lib, "sqlite3_bind_text"),
            .bind_null = try lookup(@TypeOf(@as(SqlCipher, undefined).bind_null), &lib, "sqlite3_bind_null"),
            .column_text = try lookup(@TypeOf(@as(SqlCipher, undefined).column_text), &lib, "sqlite3_column_text"),
        };
    }

    fn deinit(self: *SqlCipher) void {
        self.lib.close();
    }

    fn lookup(comptime T: type, lib: *std.DynLib, comptime name: [:0]const u8) !T {
        return lib.lookup(T, name) orelse error.SqlCipherSymbolMissing;
    }

    fn openSqlCipherFromDefaults(rt: *script.Runtime) !std.DynLib {
        const candidates = [_][]const u8{
            "libsqlcipher.dylib",
            "libsqlcipher.0.dylib",
            "libsqlcipher.so",
            "/run/current-system/sw/lib/libsqlcipher.dylib",
            "/run/current-system/sw/lib/libsqlcipher.so",
        };
        for (candidates) |path| {
            if (std.DynLib.open(path)) |lib| return lib else |_| {}
        }

        if (rt.env.get("USER")) |user| {
            const path = try std.fmt.allocPrint(rt.allocator, "/etc/profiles/per-user/{s}/lib/libsqlcipher.dylib", .{user});
            defer rt.allocator.free(path);
            if (std.DynLib.open(path)) |lib| return lib else |_| {}
        }

        return error.SqlCipherNotFound;
    }
};

/// Applies Raycast window-management settings on macOS.
pub fn main(init: std.process.Init) !void {
    if (builtin.os.tag != .macos) return;

    try script.mainWith(init, run);
}

fn run(rt: *script.Runtime) !void {
    const context = try script.chezmoiContext(rt);
    defer context.deinit(rt.allocator);
    if (!std.mem.eql(u8, context.os, "darwin")) return;

    try ensureRaycastDefaults(rt);
    const paths = try raycastPaths(rt, context);
    defer paths.deinit(rt.allocator);
    if (!try canApplyConfig(rt, paths)) return;
    if (!fileExists(rt, raycast_bin)) return error.RaycastNotInstalled;

    const was_running = try quitRaycastIfRunning(rt);
    try tryApplyConfig(rt, paths);
    if (was_running) {
        var result = try script.commandQuiet(rt, &.{ "open", "-ga", "Raycast" });
        result.deinit(rt.allocator);
    }
}

fn ensureRaycastDefaults(rt: *script.Runtime) !void {
    try arrayAddOnce(rt, "onboarding_completedTaskIdentifiers", "windowManagement");
    try arrayAddOnce(rt, "commandsPreferencesExpandedItemIds", "builtin_package_windowManagement");
}

fn arrayContains(rt: *script.Runtime, key: []const u8, value: []const u8) !bool {
    const output = try script.commandTextOr(rt, &.{ "defaults", "read", domain, key }, "");
    defer rt.allocator.free(output);
    var lines = std.mem.splitAny(u8, output, "\r\n");
    while (lines.next()) |line| {
        var trimmed = std.mem.trim(u8, line, " \t,");
        trimmed = std.mem.trim(u8, trimmed, "\"");
        if (std.mem.eql(u8, trimmed, value)) return true;
    }
    return false;
}

fn arrayAddOnce(rt: *script.Runtime, key: []const u8, value: []const u8) !void {
    if (try arrayContains(rt, key, value)) return;
    try script.command(rt, &.{ "defaults", "write", domain, key, "-array-add", value });
}

fn raycastPaths(rt: *script.Runtime, context: anytype) !RaycastPaths {
    return .{
        .config = try std.fs.path.join(rt.allocator, &.{ context.source_dir, "dot_config/raycast/window-management.json" }),
        .db = try std.fs.path.join(rt.allocator, &.{ context.home_dir, "Library/Application Support/com.raycast.macos/raycast-enc.sqlite" }),
    };
}

fn canApplyConfig(rt: *script.Runtime, paths: RaycastPaths) !bool {
    var ok = true;
    if (!fileExists(rt, paths.config)) {
        try rt.stderr.print("warn: Raycast window-management config not found: {s}\n", .{paths.config});
        try rt.stderr.flush();
        ok = false;
    }
    if (!fileExists(rt, paths.db)) {
        try rt.stderr.print("warn: Raycast database not found: {s}\n", .{paths.db});
        try rt.stderr.flush();
        ok = false;
    }
    return ok;
}

fn fileExists(rt: *script.Runtime, path: []const u8) bool {
    std.Io.Dir.cwd().access(rt.io, path, .{}) catch return false;
    return true;
}

/// Derives the SQLCipher key from Raycast's keychain entry and app salt.
///
/// Caller owns returned memory.
fn databasePassword(rt: *script.Runtime) ![]u8 {
    const key_raw = try script.commandTextOr(rt, &.{ "security", "find-generic-password", "-s", "Raycast", "-a", "database_key", "-w" }, "");
    defer rt.allocator.free(key_raw);
    const key = std.mem.trim(u8, key_raw, " \t\r\n");
    if (key.len == 0) return error.RaycastDatabaseKeyNotFound;

    const salt = try extractSalt(rt);
    defer rt.allocator.free(salt);
    const joined = try std.fmt.allocPrint(rt.allocator, "{s}{s}", .{ key, salt });
    defer rt.allocator.free(joined);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(joined, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return try rt.allocator.dupe(u8, &hex);
}

/// Extracts Raycast's database salt from the application binary.
///
/// Caller owns returned memory.
fn extractSalt(rt: *script.Runtime) ![]u8 {
    const output = try script.commandText(rt, &.{ "strings", "-a", raycast_bin });
    defer rt.allocator.free(output);

    var previous: []const u8 = "";
    var lines = std.mem.splitAny(u8, output, "\r\n");
    while (lines.next()) |line| {
        if (std.mem.eql(u8, previous, "copyDatabaseEncryptionPassphraseToClipboard()") and isAsciiSalt(line)) {
            return try rt.allocator.dupe(u8, line);
        }
        if (line.len > 0) previous = line;
    }
    return error.RaycastSaltNotFound;
}

fn isAsciiSalt(value: []const u8) bool {
    if (value.len != 32) return false;
    for (value) |char| {
        if (char < '!' or char > '~') return false;
    }
    return true;
}

fn quitRaycastIfRunning(rt: *script.Runtime) !bool {
    var running = try script.commandQuiet(rt, &.{ "pgrep", "-qx", "Raycast" });
    const is_running = running.exit_code == 0;
    running.deinit(rt.allocator);
    if (!is_running) return false;

    var quit = try script.commandQuiet(rt, &.{ "osascript", "-e", "tell application \"Raycast\" to quit" });
    quit.deinit(rt.allocator);
    try waitForRaycastToQuit(rt);
    return true;
}

fn waitForRaycastToQuit(rt: *script.Runtime) !void {
    var attempt: usize = 0;
    while (attempt < 30) : (attempt += 1) {
        var result = try script.commandQuiet(rt, &.{ "pgrep", "-qx", "Raycast" });
        const still_running = result.exit_code == 0;
        result.deinit(rt.allocator);
        if (!still_running) return;
        try std.Io.sleep(rt.io, .fromMilliseconds(200), .awake);
    }
    return error.RaycastQuitTimedOut;
}

fn tryApplyConfig(rt: *script.Runtime, paths: RaycastPaths) !void {
    applyConfig(rt, paths) catch |err| {
        try rt.stderr.print("warn: Failed to apply Raycast window-management settings: {s}\n", .{@errorName(err)});
        try rt.stderr.flush();
    };
}

fn applyConfig(rt: *script.Runtime, paths: RaycastPaths) !void {
    try rt.stderr.print("info: Applying Raycast window-management settings...\n", .{});
    try rt.stderr.flush();
    const password = try databasePassword(rt);
    defer rt.allocator.free(password);

    var config = try loadConfig(rt, paths.config);
    defer config.deinit();

    var sqlcipher = try SqlCipher.load(rt);
    defer sqlcipher.deinit();

    const db = try Database.open(&sqlcipher, rt.allocator, paths.db, password);
    defer db.close();

    try applyWindowConfig(rt, db, config);
}

fn loadConfig(rt: *script.Runtime, path: []const u8) !WindowConfig {
    const contents = try std.Io.Dir.cwd().readFileAlloc(rt.io, path, rt.allocator, .limited(64 * 1024 * 1024));
    defer rt.allocator.free(contents);

    var config: WindowConfig = .{ .parsed = try std.json.parseFromSlice(WindowConfigJson, rt.allocator, contents, .{
        .ignore_unknown_fields = true,
    }) };
    errdefer config.deinit();

    try validateConfig(config);

    return config;
}

/// Applies only validated commands and commits all database changes together.
fn applyWindowConfig(rt: *script.Runtime, db: Database, config: WindowConfig) !void {
    var known_commands = try loadKnownCommands(rt, db);
    defer deinitOwnedKeySet(rt.allocator, &known_commands);

    if (config.parsed.value.hotkeys) |hotkeys| {
        var iterator = hotkeys.map.iterator();
        while (iterator.next()) |entry| {
            if (!known_commands.contains(entry.key_ptr.*)) return error.RaycastCommandNotFound;
        }
    }
    if (config.parsed.value.disabledCommands) |disabled_commands| {
        for (disabled_commands) |command| {
            if (!known_commands.contains(command)) return error.RaycastCommandNotFound;
        }
    }

    try db.exec("BEGIN");
    errdefer db.exec("ROLLBACK") catch {};
    try db.run("UPDATE search SET hotkey = NULL WHERE key LIKE ?", &.{command_prefix ++ "%"});
    try applyHotkeys(db, config.parsed.value.hotkeys);
    try upsertDisabledCommands(rt, db, config.parsed.value.disabledCommands orelse &.{});
    try db.exec("COMMIT");
}

fn loadKnownCommands(rt: *script.Runtime, db: Database) !std.array_hash_map.String(void) {
    var known_commands: std.array_hash_map.String(void) = .empty;
    errdefer deinitOwnedKeySet(rt.allocator, &known_commands);

    var statement = try db.prepare("SELECT key FROM search WHERE key LIKE ?");
    defer statement.finalize();
    try statement.bindAll(&.{command_prefix ++ "%"});

    while (try statement.step() == .row) {
        const key = try rt.allocator.dupe(u8, try statement.text(0));
        errdefer rt.allocator.free(key);
        try known_commands.put(rt.allocator, key, {});
    }

    return known_commands;
}

fn deinitOwnedKeySet(allocator: script.Allocator, set: *std.array_hash_map.String(void)) void {
    for (set.keys()) |key| allocator.free(key);
    set.deinit(allocator);
}

fn validateConfig(config: WindowConfig) !void {
    if (config.parsed.value.hotkeys) |hotkeys| {
        var iterator = hotkeys.map.iterator();
        while (iterator.next()) |entry| try validateCommand(entry.key_ptr.*);
    }
    if (config.parsed.value.disabledCommands) |disabled_commands| {
        for (disabled_commands) |command| try validateCommand(command);
    }
}

fn validateCommand(command: []const u8) !void {
    if (!std.mem.startsWith(u8, command, command_prefix)) return error.InvalidRaycastConfig;
}

fn applyHotkeys(db: Database, maybe_hotkeys: ?std.json.ArrayHashMap(?[]const u8)) !void {
    const hotkeys = maybe_hotkeys orelse return;
    var iterator = hotkeys.map.iterator();
    while (iterator.next()) |entry| {
        try db.run("UPDATE search SET hotkey = ? WHERE key = ?", &.{ entry.value_ptr.*, entry.key_ptr.* });
    }
}

fn upsertDisabledCommands(rt: *script.Runtime, db: Database, disabled_commands: []const []const u8) !void {
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
    , &.{ extension_id, configuration });
}

fn expectSql(rc: c_int, db: ?*sqlite3, sqlcipher: *SqlCipher) !void {
    if (rc == sqlite_ok or rc == sqlite_row or rc == sqlite_done) return;
    if (db) |handle| {
        try sqlcipher.stderr.print("warn: SQLCipher error: {s}\n", .{sqlcipher.errmsg(handle)});
        try sqlcipher.stderr.flush();
    }
    return error.SqlCipherFailed;
}

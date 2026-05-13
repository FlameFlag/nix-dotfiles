const std = @import("std");
const builtin = @import("builtin");
const script = @import("chezmoi");
const macos = script.macos;

const domain = "com.raycast.macos";
const raycast_bin = "/Applications/Raycast.app/Contents/MacOS/Raycast";
const raycast_app = "/Applications/Raycast.app";
const extension_id = "builtin_package_windowManagement";
const command_prefix = "builtin_command_windowManagement";

const app_binary_read_limit = 512 * 1024 * 1024;
const config_read_limit = 64 * 1024 * 1024;
const quit_poll_attempts = 30;
const quit_poll_interval_ms = 200;

const sqlite_ok = 0;
const sqlite_row = 100;
const sqlite_done = 101;
const sqlite_transient: ?*const anyopaque = @ptrFromInt(std.math.maxInt(usize));

const sqlite3 = opaque {};
const sqlite3_stmt = opaque {};

const RaycastPaths = struct {
    config: []u8,
    db: []u8,

    fn deinit(self: *RaycastPaths, allocator: script.Allocator) void {
        allocator.free(self.config);
        allocator.free(self.db);
        self.* = undefined;
    }
};

const WindowConfig = struct {
    parsed: std.json.Parsed(WindowConfigJson),

    fn deinit(self: *WindowConfig) void {
        self.parsed.deinit();
        self.* = undefined;
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
    fn open(
        sqlcipher: *SqlCipher,
        allocator: script.Allocator,
        path: []const u8,
        password: []const u8,
    ) !Database {
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
        const rc = self.sqlcipher.close(self.handle);
        if (rc != sqlite_ok) {
            self.sqlcipher.stderr.print(
                "warn: SQLCipher close failed: {s}\n",
                .{self.sqlcipher.errmsg(self.handle)},
            ) catch |err| warnWriteFailed(err);
            self.sqlcipher.stderr.flush() catch |err| warnWriteFailed(err);
        }
    }

    fn exec(self: Database, sql: [:0]const u8) !void {
        var message: ?[*:0]u8 = null;
        const rc = self.sqlcipher.exec(self.handle, sql, null, null, &message);
        defer if (message) |value| self.sqlcipher.free(value);
        try expectSql(rc, self.handle, self.sqlcipher);
    }

    fn prepare(self: Database, sql: [:0]const u8) !Statement {
        var handle: ?*sqlite3_stmt = null;
        try expectSql(
            self.sqlcipher.prepare_v2(self.handle, sql, -1, &handle, null),
            self.handle,
            self.sqlcipher,
        );
        return .{ .db = self, .handle = handle };
    }

    fn run(self: Database, sql: [:0]const u8, values: []const ?[]const u8) !void {
        var statement = try self.prepare(sql);
        defer statement.finalize();
        try statement.bindAll(values);
        try statement.expectDone();
    }

    fn transaction(comptime body: fn (Database) anyerror!void, self: Database) !void {
        try self.exec("BEGIN");
        errdefer self.rollbackWithWarning();
        try body(self);
        try self.exec("COMMIT");
    }

    fn rollbackWithWarning(self: Database) void {
        self.exec("ROLLBACK") catch |err| {
            self.sqlcipher.stderr.print(
                "warn: failed to roll back Raycast database transaction: {s}\n",
                .{@errorName(err)},
            ) catch |write_err| warnWriteFailed(write_err);
            self.sqlcipher.stderr.flush() catch |write_err| warnWriteFailed(write_err);
        };
    }
};

const Statement = struct {
    db: Database,
    handle: ?*sqlite3_stmt,

    fn finalize(self: Statement) void {
        const rc = self.db.sqlcipher.finalize(self.handle);
        if (rc != sqlite_ok) {
            self.db.sqlcipher.stderr.print(
                "warn: SQLCipher statement finalize failed: {s}\n",
                .{self.db.sqlcipher.errmsg(self.db.handle)},
            ) catch |err| warnWriteFailed(err);
            self.db.sqlcipher.stderr.flush() catch |err| warnWriteFailed(err);
        }
    }

    fn bindAll(self: Statement, values: []const ?[]const u8) !void {
        for (values, 1..) |value, index| {
            try self.bind(@intCast(index), value);
        }
    }

    fn bind(self: Statement, index: c_int, value: ?[]const u8) !void {
        const rc = if (value) |bytes|
            self.db.sqlcipher.bind_text(
                self.handle,
                index,
                bytes.ptr,
                @intCast(bytes.len),
                sqlite_transient,
            )
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
        const value = self.db.sqlcipher.column_text(
            self.handle,
            column,
        ) orelse return error.UnexpectedRaycastDatabase;
        return std.mem.span(value);
    }
};

const StepResult = enum { row, done };

const SqlCipher = struct {
    lib: std.DynLib,
    stderr: *std.Io.Writer,
    open: *const fn ([*:0]const u8, *?*sqlite3) callconv(.c) c_int,
    close: *const fn (?*sqlite3) callconv(.c) c_int,
    exec: *const fn (
        ?*sqlite3,
        [*:0]const u8,
        ?*const fn (
            ?*anyopaque,
            c_int,
            ?[*]?[*:0]u8,
            ?[*]?[*:0]u8,
        ) callconv(.c) c_int,
        ?*anyopaque,
        *?[*:0]u8,
    ) callconv(.c) c_int,
    errmsg: *const fn (?*sqlite3) callconv(.c) [*:0]const u8,
    free: *const fn (?*anyopaque) callconv(.c) void,
    prepare_v2: *const fn (
        ?*sqlite3,
        [*:0]const u8,
        c_int,
        *?*sqlite3_stmt,
        ?*[*:0]const u8,
    ) callconv(.c) c_int,
    step: *const fn (?*sqlite3_stmt) callconv(.c) c_int,
    finalize: *const fn (?*sqlite3_stmt) callconv(.c) c_int,
    bind_text: *const fn (
        ?*sqlite3_stmt,
        c_int,
        [*]const u8,
        c_int,
        ?*const anyopaque,
    ) callconv(.c) c_int,
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
            .open = try lookup(@TypeOf(@as(SqlCipher, undefined).open), "sqlite3_open", &lib),
            .close = try lookup(@TypeOf(@as(SqlCipher, undefined).close), "sqlite3_close", &lib),
            .exec = try lookup(@TypeOf(@as(SqlCipher, undefined).exec), "sqlite3_exec", &lib),
            .errmsg = try lookup(@TypeOf(@as(SqlCipher, undefined).errmsg), "sqlite3_errmsg", &lib),
            .free = try lookup(@TypeOf(@as(SqlCipher, undefined).free), "sqlite3_free", &lib),
            .prepare_v2 = try lookup(
                @TypeOf(@as(SqlCipher, undefined).prepare_v2),
                "sqlite3_prepare_v2",
                &lib,
            ),
            .step = try lookup(@TypeOf(@as(SqlCipher, undefined).step), "sqlite3_step", &lib),
            .finalize = try lookup(
                @TypeOf(@as(SqlCipher, undefined).finalize),
                "sqlite3_finalize",
                &lib,
            ),
            .bind_text = try lookup(
                @TypeOf(@as(SqlCipher, undefined).bind_text),
                "sqlite3_bind_text",
                &lib,
            ),
            .bind_null = try lookup(
                @TypeOf(@as(SqlCipher, undefined).bind_null),
                "sqlite3_bind_null",
                &lib,
            ),
            .column_text = try lookup(
                @TypeOf(@as(SqlCipher, undefined).column_text),
                "sqlite3_column_text",
                &lib,
            ),
        };
    }

    fn deinit(self: *SqlCipher) void {
        self.lib.close();
        self.* = undefined;
    }

    fn lookup(comptime T: type, comptime name: [:0]const u8, lib: *std.DynLib) !T {
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
            const path = try std.fmt.allocPrint(
                rt.allocator,
                "/etc/profiles/per-user/{s}/lib/libsqlcipher.dylib",
                .{user},
            );
            defer rt.allocator.free(path);
            if (std.DynLib.open(path)) |lib| return lib else |_| {}
        }

        if (try openSqlCipherFromNixStore(rt)) |lib| return lib;

        return error.SqlCipherNotFound;
    }
};

fn openSqlCipherFromNixStore(rt: anytype) !?std.DynLib {
    var store = std.Io.Dir.openDirAbsolute(rt.io, "/nix/store", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer store.close(rt.io);

    var iter = store.iterate();
    while (try iter.next(rt.io)) |entry| {
        if (entry.kind != .directory or !isSqlCipherNixStoreOutput(entry.name)) continue;

        const path = try std.fmt.allocPrint(
            rt.allocator,
            "/nix/store/{s}/lib/libsqlcipher.dylib",
            .{entry.name},
        );
        defer rt.allocator.free(path);
        if (std.DynLib.open(path)) |lib| return lib else |_| {}
    }

    return null;
}

fn isSqlCipherNixStoreOutput(name: []const u8) bool {
    const dash = std.mem.indexOfScalar(u8, name, '-') orelse return false;
    return std.mem.startsWith(u8, name[dash + 1 ..], "sqlcipher-");
}

fn warnWriteFailed(err: anyerror) void {
    std.debug.print("warn: failed to write warning: {s}\n", .{@errorName(err)});
}

/// Applies Raycast window-management settings on macOS.
pub fn main(init: std.process.Init) !void {
    if (builtin.os.tag != .macos) return;

    try script.mainWith(run, init);
}

fn run(rt: *script.Runtime) !void {
    const context = try script.chezmoiContext(rt);
    defer context.deinit(rt.allocator);
    if (!std.mem.eql(u8, context.os, "darwin")) return;

    try ensureRaycastDefaults(rt);
    var paths = try raycastPaths(rt, context);
    defer paths.deinit(rt.allocator);
    if (!try canApplyConfig(rt, paths)) return;
    if (!try fileExists(rt, raycast_bin)) return error.RaycastNotInstalled;

    const was_running = try quitRaycastIfRunning(rt);
    try applyConfig(rt, paths);
    if (was_running) {
        try openRaycast(rt);
    }
}

fn ensureRaycastDefaults(rt: *script.Runtime) !void {
    _ = rt;
    var cf = try macos.CoreFoundation.load();
    defer cf.deinit();

    try cf.addStringToAppArrayPreference(
        domain,
        "onboarding_completedTaskIdentifiers",
        "windowManagement",
    );
    try cf.addStringToAppArrayPreference(
        domain,
        "commandsPreferencesExpandedItemIds",
        "builtin_package_windowManagement",
    );
}

fn raycastPaths(rt: *script.Runtime, context: anytype) !RaycastPaths {
    return .{
        .config = try std.fs.path.join(
            rt.allocator,
            &.{ context.source_dir, "dot_config/raycast/window-management.json" },
        ),
        .db = try std.fs.path.join(
            rt.allocator,
            &.{ context.home_dir, "Library/Application Support/com.raycast.macos/raycast-enc.sqlite" },
        ),
    };
}

fn canApplyConfig(rt: *script.Runtime, paths: RaycastPaths) !bool {
    var ok = true;
    if (!try fileExists(rt, paths.config)) {
        try rt.stderr.print("warn: Raycast window-management config not found: {s}\n", .{paths.config});
        try rt.stderr.flush();
        ok = false;
    }
    if (!try fileExists(rt, paths.db)) {
        try rt.stderr.print("warn: Raycast database not found: {s}\n", .{paths.db});
        try rt.stderr.flush();
        ok = false;
    }
    return ok;
}

fn fileExists(rt: *script.Runtime, path: []const u8) !bool {
    std.Io.Dir.cwd().access(rt.io, path, .{}) catch |err| return switch (err) {
        error.FileNotFound => false,
        else => err,
    };
    return true;
}

/// Derives the SQLCipher key from Raycast's keychain entry and app salt.
///
/// Caller owns returned memory.
fn databasePassword(rt: *script.Runtime) ![]u8 {
    var security = try macos.Security.load();
    defer security.deinit();
    const key = security.genericPassword(rt.allocator, "Raycast", "database_key") catch |err| switch (err) {
        error.KeychainPasswordNotFound => return error.RaycastDatabaseKeyNotFound,
        else => return err,
    };
    defer rt.allocator.free(key);

    const salt = try extractSalt(rt);
    defer rt.allocator.free(salt);
    return databasePasswordFromParts(rt.allocator, key, salt);
}

fn databasePasswordFromParts(allocator: script.Allocator, key: []const u8, salt: []const u8) ![]u8 {
    const joined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ key, salt });
    defer allocator.free(joined);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(joined, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return allocator.dupe(u8, &hex);
}

/// Extracts Raycast's database salt from the application binary.
///
/// Caller owns returned memory.
fn extractSalt(rt: *script.Runtime) ![]u8 {
    const contents = try std.Io.Dir.cwd().readFileAlloc(
        rt.io,
        raycast_bin,
        rt.allocator,
        .limited(app_binary_read_limit),
    );
    defer rt.allocator.free(contents);
    return (try findSaltAfterPassphraseSymbol(rt.allocator, contents)) orelse error.RaycastSaltNotFound;
}

fn findSaltAfterPassphraseSymbol(allocator: script.Allocator, contents: []const u8) !?[]u8 {
    var previous: []const u8 = "";
    var index: usize = 0;
    while (index < contents.len) {
        while (index < contents.len and !isPrintableAscii(contents[index])) : (index += 1) {}
        const start = index;
        while (index < contents.len and isPrintableAscii(contents[index])) : (index += 1) {}
        const string_run = contents[start..index];
        if (string_run.len >= 4) {
            if (std.mem.eql(
                u8,
                previous,
                "copyDatabaseEncryptionPassphraseToClipboard()",
            ) and isAsciiSalt(string_run)) {
                return @as(?[]u8, try allocator.dupe(u8, string_run));
            }
            previous = string_run;
        }
    }
    return null;
}

fn isPrintableAscii(char: u8) bool {
    return char >= ' ' and char <= '~';
}

fn isAsciiSalt(value: []const u8) bool {
    if (value.len != 32) return false;
    for (value) |char| {
        if (char < '!' or char > '~') return false;
    }
    return true;
}

fn quitRaycastIfRunning(rt: *script.Runtime) !bool {
    const pids = try raycastPids(rt);
    defer rt.allocator.free(pids);
    if (pids.len == 0) return false;

    for (pids) |pid| {
        std.posix.kill(pid, .TERM) catch |err| switch (err) {
            error.ProcessNotFound => {},
            else => return err,
        };
    }
    try waitForRaycastToQuit(rt);
    return true;
}

fn waitForRaycastToQuit(rt: *script.Runtime) !void {
    var attempt: usize = 0;
    while (attempt < quit_poll_attempts) : (attempt += 1) {
        const pids = try raycastPids(rt);
        defer rt.allocator.free(pids);
        if (pids.len == 0) return;
        try std.Io.sleep(rt.io, .fromMilliseconds(quit_poll_interval_ms), .awake);
    }
    return error.RaycastQuitTimedOut;
}

fn raycastPids(rt: *script.Runtime) ![]std.posix.pid_t {
    return macos.pidsForExecutablePath(rt.allocator, rt.io, raycast_bin);
}

fn openRaycast(rt: *script.Runtime) !void {
    _ = rt;
    var cf = try macos.CoreFoundation.load();
    defer cf.deinit();
    var launch_services = try macos.LaunchServices.load();
    defer launch_services.deinit();

    launch_services.openApplicationNoActivate(cf, raycast_app) catch |err| switch (err) {
        error.ApplicationLaunchFailed => return error.RaycastLaunchFailed,
        else => return err,
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
    const contents = try std.Io.Dir.cwd().readFileAlloc(rt.io, path, rt.allocator, .limited(config_read_limit));
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

/// Applies only validated commands and commits all database changes together.
fn applyWindowConfig(rt: *script.Runtime, db: Database, config: WindowConfig) !void {
    var known_commands = try loadKnownCommands(rt, db);
    defer deinitOwnedKeySet(rt.allocator, &known_commands);
    try warnMissingConfiguredCommands(rt, &known_commands, config);

    try db.exec("BEGIN");
    errdefer db.rollbackWithWarning();
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

fn warnMissingConfiguredCommands(
    rt: *script.Runtime,
    known_commands: *const std.array_hash_map.String(void),
    config: WindowConfig,
) !void {
    var missing = try collectMissingConfiguredCommands(rt.allocator, known_commands, config);
    defer missing.deinit(rt.allocator);

    for (missing.items) |command| {
        try rt.stderr.print(
            "warn: Raycast command not found in local database yet; update may be skipped: {s}\n",
            .{command},
        );
    }
    if (missing.items.len > 0) try rt.stderr.flush();
}

fn collectMissingConfiguredCommands(
    allocator: script.Allocator,
    known_commands: *const std.array_hash_map.String(void),
    config: WindowConfig,
) !std.ArrayList([]const u8) {
    var missing: std.ArrayList([]const u8) = .empty;
    errdefer missing.deinit(allocator);

    if (config.parsed.value.hotkeys) |hotkeys| {
        var iterator = hotkeys.map.iterator();
        while (iterator.next()) |entry| {
            try appendMissingCommand(allocator, &missing, known_commands, entry.key_ptr.*);
        }
    }
    if (config.parsed.value.disabledCommands) |disabled_commands| {
        for (disabled_commands) |command| {
            try appendMissingCommand(allocator, &missing, known_commands, command);
        }
    }

    return missing;
}

fn appendMissingCommand(
    allocator: script.Allocator,
    missing: *std.ArrayList([]const u8),
    known_commands: *const std.array_hash_map.String(void),
    command: []const u8,
) !void {
    if (known_commands.contains(command)) return;
    for (missing.items) |existing| {
        if (std.mem.eql(u8, existing, command)) return;
    }
    try missing.append(allocator, command);
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

fn upsertDisabledCommands(
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

test "isAsciiSalt accepts exactly 32 printable ASCII bytes" {
    try std.testing.expect(isAsciiSalt("0123456789abcdef0123456789ABCDEF"));
    try std.testing.expect(!isAsciiSalt("short"));
    try std.testing.expect(!isAsciiSalt("0123456789abcdef0123456789ABCDE"));
    try std.testing.expect(!isAsciiSalt("0123456789abcdef0123456789ABC\n"));
}

test "isPrintableAscii matches strings printable runs" {
    try std.testing.expect(isPrintableAscii(' '));
    try std.testing.expect(isPrintableAscii('~'));
    try std.testing.expect(!isPrintableAscii('\n'));
    try std.testing.expect(!isPrintableAscii(0x7f));
}

test "findSaltAfterPassphraseSymbol reads printable strings like strings -a" {
    const contents =
        "noise\x00" ++
        "copyDatabaseEncryptionPassphraseToClipboard()\x00" ++
        "0123456789abcdef0123456789ABCDEF\x00";
    const salt = try findSaltAfterPassphraseSymbol(
        std.testing.allocator,
        contents,
    ) orelse return error.TestExpectedSalt;
    defer std.testing.allocator.free(salt);

    try std.testing.expectEqualStrings("0123456789abcdef0123456789ABCDEF", salt);
}

test "findSaltAfterPassphraseSymbol rejects missing and invalid salt candidates" {
    try std.testing.expectEqual(
        null,
        try findSaltAfterPassphraseSymbol(
            std.testing.allocator,
            "copyDatabaseEncryptionPassphraseToClipboard()\x00short\x00",
        ),
    );
    try std.testing.expectEqual(
        null,
        try findSaltAfterPassphraseSymbol(
            std.testing.allocator,
            "before\x000123456789abcdef0123456789ABCDEF\x00",
        ),
    );
    try std.testing.expectEqual(
        null,
        try findSaltAfterPassphraseSymbol(
            std.testing.allocator,
            "copyDatabaseEncryptionPassphraseToClipboard()\x00" ++
                "0123456789abcdef0123456789ABC\n",
        ),
    );
}

test "databasePasswordFromParts returns lowercase sha256 hex" {
    const password = try databasePasswordFromParts(std.testing.allocator, "key", "salt");
    defer std.testing.allocator.free(password);

    try std.testing.expectEqual(@as(usize, 64), password.len);
    try std.testing.expectEqualStrings(
        "85d87cc3b60adb89ca20449c6f30967309141595fd13b3bf68f26ffb97b7b2d2",
        password,
    );
}

test "isSqlCipherNixStoreOutput matches sqlcipher package outputs" {
    try std.testing.expect(isSqlCipherNixStoreOutput(
        "8nkcwjjha8v4sw590rasdzmxm0n86lrx-sqlcipher-4.6.1",
    ));
    try std.testing.expect(isSqlCipherNixStoreOutput(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-sqlcipher-4.6.1-bin",
    ));
    try std.testing.expect(!isSqlCipherNixStoreOutput(
        "8nkcwjjha8v4sw590rasdzmxm0n86lrx-sqlite-3.50.4",
    ));
    try std.testing.expect(!isSqlCipherNixStoreOutput("sqlcipher-4.6.1"));
    try std.testing.expect(!isSqlCipherNixStoreOutput(
        "8nkcwjjha8v4sw590rasdzmxm0n86lrx-my-sqlcipher-4.6.1",
    ));
}

test "openSqlCipherFromNixStore loads installed Nix SQLCipher library" {
    if (builtin.os.tag != .macos) return;

    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    const rt: struct {
        allocator: script.Allocator,
        io: std.Io,
        env: *std.process.Environ.Map,
    } = .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = &map,
    };

    var lib = (try openSqlCipherFromNixStore(&rt)) orelse return;
    defer lib.close();
    try std.testing.expect(
        lib.lookup(*const fn () callconv(.c) [*:0]const u8, "sqlite3_libversion") != null,
    );
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

    try std.testing.expectEqual(@as(usize, 2), missing.items.len);
    try std.testing.expectEqualStrings("builtin_command_windowManagementRightHalf", missing.items[0]);
    try std.testing.expectEqualStrings("builtin_command_windowManagementTopHalf", missing.items[1]);
}

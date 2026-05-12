const std = @import("std");
const builtin = @import("builtin");
const script = @import("script.zig");

const domain = "com.raycast.macos";
const raycast_bin = "/Applications/Raycast.app/Contents/MacOS/Raycast";
const extension_id = "builtin_package_windowManagement";
const command_prefix = "builtin_command_windowManagement";
const cf_false: u8 = 0;
const cf_true: u8 = 1;
const cf_utf8 = 0x08000100;
const cf_url_posix_path_style = 0;
const ls_launch_defaults = 0x00000001;
const ls_launch_dont_switch = 0x00000200;
const proc_all_pids = 1;
const proc_pidpathinfo_maxsize = 4096;

const sqlite_ok = 0;
const sqlite_row = 100;
const sqlite_done = 101;
const sqlite_transient: ?*const anyopaque = @ptrFromInt(std.math.maxInt(usize));

const sqlite3 = opaque {};
const sqlite3_stmt = opaque {};

extern fn proc_listpids(type: c_uint, typeinfo: c_uint, buffer: ?*anyopaque, buffersize: c_int) c_int;
extern fn proc_pidpath(pid: c_int, buffer: [*]u8, buffersize: u32) c_int;

const LSLaunchURLSpec = extern struct {
    app_url: ?*const anyopaque,
    item_urls: ?*const anyopaque,
    pass_thru_params: ?*const anyopaque,
    launch_flags: u32,
    async_ref_con: ?*anyopaque,
};

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

const CoreFoundation = struct {
    lib: std.DynLib,
    array_callbacks: *const anyopaque,
    create_string: *const fn (?*const anyopaque, [*]const u8, isize, u32, u8) callconv(.c) ?*anyopaque,
    release: *const fn (?*const anyopaque) callconv(.c) void,
    equal: *const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) u8,
    get_type_id: *const fn (?*const anyopaque) callconv(.c) usize,
    array_get_type_id: *const fn () callconv(.c) usize,
    array_create_mutable: *const fn (?*const anyopaque, isize, ?*const anyopaque) callconv(.c) ?*anyopaque,
    array_create_mutable_copy: *const fn (?*const anyopaque, isize, ?*const anyopaque) callconv(.c) ?*anyopaque,
    array_append_value: *const fn (?*anyopaque, ?*const anyopaque) callconv(.c) void,
    array_get_count: *const fn (?*const anyopaque) callconv(.c) isize,
    array_get_value_at_index: *const fn (?*const anyopaque, isize) callconv(.c) ?*const anyopaque,
    preferences_copy_app_value: *const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) ?*anyopaque,
    preferences_set_app_value: *const fn (?*const anyopaque, ?*const anyopaque, ?*const anyopaque) callconv(.c) void,
    preferences_app_synchronize: *const fn (?*const anyopaque) callconv(.c) u8,
    url_create_with_file_system_path: *const fn (?*const anyopaque, ?*const anyopaque, c_int, u8) callconv(.c) ?*anyopaque,

    fn load() !CoreFoundation {
        var lib = try std.DynLib.open("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation");
        errdefer lib.close();

        return .{
            .lib = lib,
            .array_callbacks = try dynLookup(*const anyopaque, &lib, "kCFTypeArrayCallBacks"),
            .create_string = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).create_string), &lib, "CFStringCreateWithBytes"),
            .release = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).release), &lib, "CFRelease"),
            .equal = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).equal), &lib, "CFEqual"),
            .get_type_id = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).get_type_id), &lib, "CFGetTypeID"),
            .array_get_type_id = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).array_get_type_id), &lib, "CFArrayGetTypeID"),
            .array_create_mutable = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).array_create_mutable), &lib, "CFArrayCreateMutable"),
            .array_create_mutable_copy = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).array_create_mutable_copy), &lib, "CFArrayCreateMutableCopy"),
            .array_append_value = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).array_append_value), &lib, "CFArrayAppendValue"),
            .array_get_count = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).array_get_count), &lib, "CFArrayGetCount"),
            .array_get_value_at_index = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).array_get_value_at_index), &lib, "CFArrayGetValueAtIndex"),
            .preferences_copy_app_value = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).preferences_copy_app_value), &lib, "CFPreferencesCopyAppValue"),
            .preferences_set_app_value = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).preferences_set_app_value), &lib, "CFPreferencesSetAppValue"),
            .preferences_app_synchronize = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).preferences_app_synchronize), &lib, "CFPreferencesAppSynchronize"),
            .url_create_with_file_system_path = try dynLookup(@TypeOf(@as(CoreFoundation, undefined).url_create_with_file_system_path), &lib, "CFURLCreateWithFileSystemPath"),
        };
    }

    fn deinit(self: *CoreFoundation) void {
        self.lib.close();
    }

    fn string(self: CoreFoundation, value: []const u8) !*anyopaque {
        return self.create_string(null, value.ptr, @intCast(value.len), cf_utf8, cf_false) orelse error.CoreFoundationFailed;
    }

    fn arrayAddOnce(self: CoreFoundation, key: []const u8, value: []const u8) !void {
        const app_id = try self.string(domain);
        defer self.release(app_id);
        const key_ref = try self.string(key);
        defer self.release(key_ref);
        const value_ref = try self.string(value);
        defer self.release(value_ref);

        const existing = self.preferences_copy_app_value(key_ref, app_id);
        defer if (existing) |ref| self.release(ref);

        if (existing) |ref| {
            if (self.isArray(ref) and self.arrayContains(ref, value_ref)) return;
        }

        const array = if (existing) |ref|
            if (self.isArray(ref))
                self.array_create_mutable_copy(null, 0, ref)
            else
                self.array_create_mutable(null, 0, self.array_callbacks)
        else
            self.array_create_mutable(null, 0, self.array_callbacks);
        const mutable_array = array orelse return error.CoreFoundationFailed;
        defer self.release(mutable_array);

        self.array_append_value(mutable_array, value_ref);
        self.preferences_set_app_value(key_ref, mutable_array, app_id);
        if (self.preferences_app_synchronize(app_id) == cf_false) return error.RaycastDefaultsWriteFailed;
    }

    fn isArray(self: CoreFoundation, ref: *anyopaque) bool {
        return self.get_type_id(ref) == self.array_get_type_id();
    }

    fn arrayContains(self: CoreFoundation, array: *anyopaque, value: *anyopaque) bool {
        const count = self.array_get_count(array);
        var index: isize = 0;
        while (index < count) : (index += 1) {
            const item = self.array_get_value_at_index(array, index) orelse continue;
            if (self.equal(item, value) != cf_false) return true;
        }
        return false;
    }
};

const Security = struct {
    lib: std.DynLib,
    find_generic_password: *const fn (?*anyopaque, u32, ?[*]const u8, u32, ?[*]const u8, *u32, *?*anyopaque, ?*?*anyopaque) callconv(.c) i32,
    free_content: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) i32,

    fn load() !Security {
        var lib = try std.DynLib.open("/System/Library/Frameworks/Security.framework/Security");
        errdefer lib.close();

        return .{
            .lib = lib,
            .find_generic_password = try dynLookup(@TypeOf(@as(Security, undefined).find_generic_password), &lib, "SecKeychainFindGenericPassword"),
            .free_content = try dynLookup(@TypeOf(@as(Security, undefined).free_content), &lib, "SecKeychainItemFreeContent"),
        };
    }

    fn deinit(self: *Security) void {
        self.lib.close();
    }

    fn raycastDatabaseKey(self: Security, allocator: script.Allocator) ![]u8 {
        var password_len: u32 = 0;
        var password_data: ?*anyopaque = null;
        const service = "Raycast";
        const account = "database_key";

        const status = self.find_generic_password(
            null,
            service.len,
            service.ptr,
            account.len,
            account.ptr,
            &password_len,
            &password_data,
            null,
        );
        if (status != 0) return error.RaycastDatabaseKeyNotFound;
        defer _ = self.free_content(null, password_data);

        return try copyTrimmedPassword(allocator, password_data, password_len);
    }
};

const LaunchServices = struct {
    lib: std.DynLib,
    open_from_url_spec: *const fn (*const LSLaunchURLSpec, ?*?*anyopaque) callconv(.c) i32,

    fn load() !LaunchServices {
        var lib = try std.DynLib.open("/System/Library/Frameworks/CoreServices.framework/CoreServices");
        errdefer lib.close();

        return .{
            .lib = lib,
            .open_from_url_spec = try dynLookup(@TypeOf(@as(LaunchServices, undefined).open_from_url_spec), &lib, "LSOpenFromURLSpec"),
        };
    }

    fn deinit(self: *LaunchServices) void {
        self.lib.close();
    }
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
        const rc = self.sqlcipher.close(self.handle);
        if (rc != sqlite_ok) {
            self.sqlcipher.stderr.print("warn: SQLCipher close failed: {s}\n", .{self.sqlcipher.errmsg(self.handle)}) catch {};
            self.sqlcipher.stderr.flush() catch {};
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
        errdefer self.rollbackWithWarning();
        try body(self);
        try self.exec("COMMIT");
    }

    fn rollbackWithWarning(self: Database) void {
        self.exec("ROLLBACK") catch |err| {
            self.sqlcipher.stderr.print("warn: failed to roll back Raycast database transaction: {s}\n", .{@errorName(err)}) catch {};
            self.sqlcipher.stderr.flush() catch {};
        };
    }
};

const Statement = struct {
    db: Database,
    handle: ?*sqlite3_stmt,

    fn finalize(self: Statement) void {
        const rc = self.db.sqlcipher.finalize(self.handle);
        if (rc != sqlite_ok) {
            self.db.sqlcipher.stderr.print("warn: SQLCipher statement finalize failed: {s}\n", .{self.db.sqlcipher.errmsg(self.db.handle)}) catch {};
            self.db.sqlcipher.stderr.flush() catch {};
        }
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

        const path = try std.fmt.allocPrint(rt.allocator, "/nix/store/{s}/lib/libsqlcipher.dylib", .{entry.name});
        defer rt.allocator.free(path);
        if (std.DynLib.open(path)) |lib| return lib else |_| {}
    }

    return null;
}

fn isSqlCipherNixStoreOutput(name: []const u8) bool {
    const dash = std.mem.indexOfScalar(u8, name, '-') orelse return false;
    return std.mem.startsWith(u8, name[dash + 1 ..], "sqlcipher-");
}

fn dynLookup(comptime T: type, lib: *std.DynLib, comptime name: [:0]const u8) !T {
    return lib.lookup(T, name) orelse error.DynamicSymbolMissing;
}

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
    if (!try fileExists(rt, raycast_bin)) return error.RaycastNotInstalled;

    const was_running = try quitRaycastIfRunning(rt);
    try applyConfig(rt, paths);
    if (was_running) {
        try openRaycast(rt);
    }
}

fn ensureRaycastDefaults(rt: *script.Runtime) !void {
    _ = rt;
    var cf = try CoreFoundation.load();
    defer cf.deinit();

    try cf.arrayAddOnce("onboarding_completedTaskIdentifiers", "windowManagement");
    try cf.arrayAddOnce("commandsPreferencesExpandedItemIds", "builtin_package_windowManagement");
}

fn raycastPaths(rt: *script.Runtime, context: anytype) !RaycastPaths {
    return .{
        .config = try std.fs.path.join(rt.allocator, &.{ context.source_dir, "dot_config/raycast/window-management.json" }),
        .db = try std.fs.path.join(rt.allocator, &.{ context.home_dir, "Library/Application Support/com.raycast.macos/raycast-enc.sqlite" }),
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
    var security = try Security.load();
    defer security.deinit();
    const key = try security.raycastDatabaseKey(rt.allocator);
    defer rt.allocator.free(key);

    const salt = try extractSalt(rt);
    defer rt.allocator.free(salt);
    return try databasePasswordFromParts(rt.allocator, key, salt);
}

fn copyTrimmedPassword(allocator: script.Allocator, password_data: ?*anyopaque, password_len: u32) ![]u8 {
    const data = password_data orelse return error.RaycastDatabaseKeyNotFound;
    const bytes: [*]const u8 = @ptrCast(data);
    const key = std.mem.trim(u8, bytes[0..password_len], " \t\r\n");
    if (key.len == 0) return error.RaycastDatabaseKeyNotFound;
    return try allocator.dupe(u8, key);
}

fn databasePasswordFromParts(allocator: script.Allocator, key: []const u8, salt: []const u8) ![]u8 {
    const joined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ key, salt });
    defer allocator.free(joined);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(joined, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return try allocator.dupe(u8, &hex);
}

/// Extracts Raycast's database salt from the application binary.
///
/// Caller owns returned memory.
fn extractSalt(rt: *script.Runtime) ![]u8 {
    const contents = try std.Io.Dir.cwd().readFileAlloc(rt.io, raycast_bin, rt.allocator, .limited(512 * 1024 * 1024));
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
            if (std.mem.eql(u8, previous, "copyDatabaseEncryptionPassphraseToClipboard()") and isAsciiSalt(string_run)) {
                return try allocator.dupe(u8, string_run);
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
    while (attempt < 30) : (attempt += 1) {
        const pids = try raycastPids(rt);
        defer rt.allocator.free(pids);
        if (pids.len == 0) return;
        try std.Io.sleep(rt.io, .fromMilliseconds(200), .awake);
    }
    return error.RaycastQuitTimedOut;
}

fn raycastPids(rt: *script.Runtime) ![]std.posix.pid_t {
    const initial_bytes = proc_listpids(proc_all_pids, 0, null, 0);
    if (initial_bytes < 0) return error.ProcessListFailed;

    const initial_count: usize = @intCast(@divTrunc(initial_bytes, @sizeOf(c_int)));
    const pids = try rt.allocator.alloc(c_int, initial_count + 256);
    defer rt.allocator.free(pids);

    const byte_count = proc_listpids(proc_all_pids, 0, pids.ptr, @intCast(pids.len * @sizeOf(c_int)));
    if (byte_count < 0) return error.ProcessListFailed;

    var matches: std.ArrayList(std.posix.pid_t) = .empty;
    errdefer matches.deinit(rt.allocator);

    const count: usize = @intCast(@divTrunc(byte_count, @sizeOf(c_int)));
    for (pids[0..@min(count, pids.len)]) |pid| {
        if (pid <= 0) continue;

        var path_buffer: [proc_pidpathinfo_maxsize]u8 = undefined;
        const path_len = proc_pidpath(pid, &path_buffer, path_buffer.len);
        if (path_len <= 0) continue;

        const path = path_buffer[0..@intCast(path_len)];
        try appendRaycastPidIfPathMatches(rt.allocator, &matches, pid, path);
    }

    return try matches.toOwnedSlice(rt.allocator);
}

fn appendRaycastPidIfPathMatches(allocator: script.Allocator, matches: *std.ArrayList(std.posix.pid_t), pid: c_int, path: []const u8) !void {
    if (!std.mem.eql(u8, path, raycast_bin)) return;
    try matches.append(allocator, @intCast(pid));
}

fn openRaycast(rt: *script.Runtime) !void {
    _ = rt;
    var cf = try CoreFoundation.load();
    defer cf.deinit();
    var launch_services = try LaunchServices.load();
    defer launch_services.deinit();

    const app_path = try cf.string("/Applications/Raycast.app");
    defer cf.release(app_path);
    const app_url = cf.url_create_with_file_system_path(null, app_path, cf_url_posix_path_style, cf_true) orelse return error.CoreFoundationFailed;
    defer cf.release(app_url);

    const launch_spec: LSLaunchURLSpec = .{
        .app_url = app_url,
        .item_urls = null,
        .pass_thru_params = null,
        .launch_flags = ls_launch_defaults | ls_launch_dont_switch,
        .async_ref_con = null,
    };
    const status = launch_services.open_from_url_spec(&launch_spec, null);
    if (status != 0) return error.RaycastLaunchFailed;
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

fn warnMissingConfiguredCommands(rt: *script.Runtime, known_commands: *const std.array_hash_map.String(void), config: WindowConfig) !void {
    var missing = try collectMissingConfiguredCommands(rt.allocator, known_commands, config);
    defer missing.deinit(rt.allocator);

    for (missing.items) |command| {
        try rt.stderr.print("warn: Raycast command not found in local database yet; update may be skipped: {s}\n", .{command});
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
        while (iterator.next()) |entry| try appendMissingCommand(allocator, &missing, known_commands, entry.key_ptr.*);
    }
    if (config.parsed.value.disabledCommands) |disabled_commands| {
        for (disabled_commands) |command| try appendMissingCommand(allocator, &missing, known_commands, command);
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
    const contents = "noise\x00copyDatabaseEncryptionPassphraseToClipboard()\x000123456789abcdef0123456789ABCDEF\x00";
    const salt = try findSaltAfterPassphraseSymbol(std.testing.allocator, contents) orelse return error.TestExpectedSalt;
    defer std.testing.allocator.free(salt);

    try std.testing.expectEqualStrings("0123456789abcdef0123456789ABCDEF", salt);
}

test "findSaltAfterPassphraseSymbol rejects missing and invalid salt candidates" {
    try std.testing.expectEqual(null, try findSaltAfterPassphraseSymbol(std.testing.allocator, "copyDatabaseEncryptionPassphraseToClipboard()\x00short\x00"));
    try std.testing.expectEqual(null, try findSaltAfterPassphraseSymbol(std.testing.allocator, "before\x000123456789abcdef0123456789ABCDEF\x00"));
    try std.testing.expectEqual(null, try findSaltAfterPassphraseSymbol(std.testing.allocator, "copyDatabaseEncryptionPassphraseToClipboard()\x000123456789abcdef0123456789ABC\n"));
}

test "appendRaycastPidIfPathMatches filters exact executable path" {
    var matches: std.ArrayList(std.posix.pid_t) = .empty;
    defer matches.deinit(std.testing.allocator);

    try appendRaycastPidIfPathMatches(std.testing.allocator, &matches, 42, "/Applications/Other.app/Contents/MacOS/Raycast");
    try std.testing.expectEqual(@as(usize, 0), matches.items.len);

    try appendRaycastPidIfPathMatches(std.testing.allocator, &matches, 42, raycast_bin);
    try std.testing.expectEqual(@as(usize, 1), matches.items.len);
    try std.testing.expectEqual(@as(std.posix.pid_t, 42), matches.items[0]);
}

test "copyTrimmedPassword copies keychain bytes and rejects empty secrets" {
    var key_bytes = "  secret-key\n".*;
    const key = try copyTrimmedPassword(std.testing.allocator, &key_bytes, key_bytes.len);
    defer std.testing.allocator.free(key);

    try std.testing.expectEqualStrings("secret-key", key);
    try std.testing.expectError(error.RaycastDatabaseKeyNotFound, copyTrimmedPassword(std.testing.allocator, null, 0));

    var blank = " \t\r\n".*;
    try std.testing.expectError(error.RaycastDatabaseKeyNotFound, copyTrimmedPassword(std.testing.allocator, &blank, blank.len));
}

test "databasePasswordFromParts returns lowercase sha256 hex" {
    const password = try databasePasswordFromParts(std.testing.allocator, "key", "salt");
    defer std.testing.allocator.free(password);

    try std.testing.expectEqual(@as(usize, 64), password.len);
    try std.testing.expectEqualStrings("85d87cc3b60adb89ca20449c6f30967309141595fd13b3bf68f26ffb97b7b2d2", password);
}

test "isSqlCipherNixStoreOutput matches sqlcipher package outputs" {
    try std.testing.expect(isSqlCipherNixStoreOutput("8nkcwjjha8v4sw590rasdzmxm0n86lrx-sqlcipher-4.6.1"));
    try std.testing.expect(isSqlCipherNixStoreOutput("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-sqlcipher-4.6.1-bin"));
    try std.testing.expect(!isSqlCipherNixStoreOutput("8nkcwjjha8v4sw590rasdzmxm0n86lrx-sqlite-3.50.4"));
    try std.testing.expect(!isSqlCipherNixStoreOutput("sqlcipher-4.6.1"));
    try std.testing.expect(!isSqlCipherNixStoreOutput("8nkcwjjha8v4sw590rasdzmxm0n86lrx-my-sqlcipher-4.6.1"));
}

test "openSqlCipherFromNixStore loads installed Nix SQLCipher library" {
    if (builtin.os.tag != .macos) return;

    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    const rt = struct {
        allocator: script.Allocator,
        io: std.Io,
        env: *std.process.Environ.Map,
    }{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = &map,
    };

    var lib = (try openSqlCipherFromNixStore(&rt)) orelse return;
    defer lib.close();
    try std.testing.expect(lib.lookup(*const fn () callconv(.c) [*:0]const u8, "sqlite3_libversion") != null);
}

test "macOS framework symbols load" {
    if (builtin.os.tag != .macos) return;

    var cf = try CoreFoundation.load();
    cf.deinit();
    var security = try Security.load();
    security.deinit();
    var launch_services = try LaunchServices.load();
    launch_services.deinit();
}

test "CoreFoundation strings and arrays work through dynamic bindings" {
    if (builtin.os.tag != .macos) return;

    var cf = try CoreFoundation.load();
    defer cf.deinit();

    const a = try cf.string("alpha");
    defer cf.release(a);
    const b = try cf.string("beta");
    defer cf.release(b);
    const array = cf.array_create_mutable(null, 0, cf.array_callbacks) orelse return error.CoreFoundationFailed;
    defer cf.release(array);

    try std.testing.expect(!cf.arrayContains(array, a));
    cf.array_append_value(array, a);
    try std.testing.expectEqual(@as(isize, 1), cf.array_get_count(array));
    try std.testing.expect(cf.arrayContains(array, a));
    try std.testing.expect(!cf.arrayContains(array, b));
}

test "LaunchServices creates Raycast app URL spec without launching" {
    if (builtin.os.tag != .macos) return;

    var cf = try CoreFoundation.load();
    defer cf.deinit();

    const app_path = try cf.string("/Applications/Raycast.app");
    defer cf.release(app_path);
    const app_url = cf.url_create_with_file_system_path(null, app_path, cf_url_posix_path_style, cf_true) orelse return error.CoreFoundationFailed;
    defer cf.release(app_url);

    const launch_spec: LSLaunchURLSpec = .{
        .app_url = app_url,
        .item_urls = null,
        .pass_thru_params = null,
        .launch_flags = ls_launch_defaults | ls_launch_dont_switch,
        .async_ref_con = null,
    };

    try std.testing.expectEqual(app_url, launch_spec.app_url.?);
    try std.testing.expect((launch_spec.launch_flags & ls_launch_dont_switch) != 0);
}

test "proc APIs can inspect current process on macOS" {
    if (builtin.os.tag != .macos) return;

    const byte_count = proc_listpids(proc_all_pids, 0, null, 0);
    try std.testing.expect(byte_count > 0);

    var path_buffer: [proc_pidpathinfo_maxsize]u8 = undefined;
    const path_len = proc_pidpath(std.c.getpid(), &path_buffer, path_buffer.len);
    try std.testing.expect(path_len > 0);
    try std.testing.expect(std.mem.indexOfScalar(u8, path_buffer[0..@intCast(path_len)], '/') != null);
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
    var valid: WindowConfig = .{ .parsed = try std.json.parseFromSlice(WindowConfigJson, std.testing.allocator, valid_json, .{}) };
    defer valid.deinit();
    try validateConfig(valid);

    const invalid_json =
        \\{"disabledCommands":["builtin_command_otherExtension"]}
    ;
    var invalid: WindowConfig = .{ .parsed = try std.json.parseFromSlice(WindowConfigJson, std.testing.allocator, invalid_json, .{}) };
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
    var config: WindowConfig = .{ .parsed = try std.json.parseFromSlice(WindowConfigJson, std.testing.allocator, config_json, .{}) };
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

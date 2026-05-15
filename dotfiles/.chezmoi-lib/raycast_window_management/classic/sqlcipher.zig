const std = @import("std");
const script = @import("chezmoi");
const builtin = @import("builtin");

pub const sqlite_ok = 0;
pub const sqlite_row = 100;
pub const sqlite_done = 101;
pub const sqlite_transient: ?*const anyopaque = @ptrFromInt(std.math.maxInt(usize));

pub const sqlite3 = opaque {};
pub const sqlite3_stmt = opaque {};

pub const SqlCipher = struct {
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
    pub fn load(rt: *script.Runtime) !SqlCipher {
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

    pub fn deinit(self: *SqlCipher) void {
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

pub fn openSqlCipherFromNixStore(rt: anytype) !?std.DynLib {
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
    const dash = std.mem.findScalar(u8, name, '-') orelse return false;
    return std.mem.startsWith(u8, name[dash + 1 ..], "sqlcipher-");
}

pub fn expectSql(rc: c_int, db: ?*sqlite3, sqlcipher: *SqlCipher) !void {
    if (rc == sqlite_ok or rc == sqlite_row or rc == sqlite_done) return;
    if (db) |handle| {
        try sqlcipher.stderr.print("warn: SQLCipher error: {s}\n", .{sqlcipher.errmsg(handle)});
        try sqlcipher.stderr.flush();
    }
    return error.SqlCipherFailed;
}

pub fn warnWriteFailed(err: anyerror) void {
    std.debug.print("warn: failed to write warning: {s}\n", .{@errorName(err)});
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

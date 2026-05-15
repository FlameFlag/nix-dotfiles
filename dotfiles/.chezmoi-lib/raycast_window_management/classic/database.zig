const std = @import("std");
const script = @import("chezmoi");
const sql = @import("sqlcipher.zig");

pub const Database = struct {
    sqlcipher: *sql.SqlCipher,
    handle: ?*sql.sqlite3,

    /// Opens Raycast's SQLCipher database and applies the key pragma.
    pub fn open(
        sqlcipher: *sql.SqlCipher,
        allocator: script.Allocator,
        path: []const u8,
        password: []const u8,
    ) !Database {
        const db_path = try allocator.dupeSentinel(u8, path, 0);
        defer allocator.free(db_path);

        var handle: ?*sql.sqlite3 = null;
        try sql.expectSql(sqlcipher.open(db_path, &handle), handle, sqlcipher);
        errdefer _ = sqlcipher.close(handle);

        var db: Database = .{ .sqlcipher = sqlcipher, .handle = handle };
        const pragma = try std.fmt.allocPrint(allocator, "PRAGMA key = \"{s}\"", .{password});
        defer allocator.free(pragma);
        const pragma_z = try allocator.dupeSentinel(u8, pragma, 0);
        defer allocator.free(pragma_z);
        try db.exec(pragma_z);
        return db;
    }

    pub fn close(self: Database) void {
        const rc = self.sqlcipher.close(self.handle);
        if (rc != sql.sqlite_ok) {
            self.sqlcipher.stderr.print(
                "warn: SQLCipher close failed: {s}\n",
                .{self.sqlcipher.errmsg(self.handle)},
            ) catch |err| sql.warnWriteFailed(err);
            self.sqlcipher.stderr.flush() catch |err| sql.warnWriteFailed(err);
        }
    }

    pub fn exec(self: Database, statement_sql: [:0]const u8) !void {
        var message: ?[*:0]u8 = null;
        const rc = self.sqlcipher.exec(self.handle, statement_sql, null, null, &message);
        defer if (message) |value| self.sqlcipher.free(value);
        try sql.expectSql(rc, self.handle, self.sqlcipher);
    }

    pub fn prepare(self: Database, statement_sql: [:0]const u8) !Statement {
        var handle: ?*sql.sqlite3_stmt = null;
        try sql.expectSql(
            self.sqlcipher.prepare_v2(self.handle, statement_sql, -1, &handle, null),
            self.handle,
            self.sqlcipher,
        );
        return .{ .db = self, .handle = handle };
    }

    pub fn run(self: Database, statement_sql: [:0]const u8, values: []const ?[]const u8) !void {
        var statement = try self.prepare(statement_sql);
        defer statement.finalize();
        try statement.bindAll(values);
        try statement.expectDone();
    }

    pub fn transaction(comptime body: fn (Database) anyerror!void, self: Database) !void {
        try self.exec("BEGIN");
        errdefer self.rollbackWithWarning();
        try body(self);
        try self.exec("COMMIT");
    }

    pub fn rollbackWithWarning(self: Database) void {
        self.exec("ROLLBACK") catch |err| {
            self.sqlcipher.stderr.print(
                "warn: failed to roll back Raycast database transaction: {s}\n",
                .{@errorName(err)},
            ) catch |write_err| sql.warnWriteFailed(write_err);
            self.sqlcipher.stderr.flush() catch |write_err| sql.warnWriteFailed(write_err);
        };
    }
};

pub const Statement = struct {
    db: Database,
    handle: ?*sql.sqlite3_stmt,

    pub fn finalize(self: Statement) void {
        const rc = self.db.sqlcipher.finalize(self.handle);
        if (rc != sql.sqlite_ok) {
            self.db.sqlcipher.stderr.print(
                "warn: SQLCipher statement finalize failed: {s}\n",
                .{self.db.sqlcipher.errmsg(self.db.handle)},
            ) catch |err| sql.warnWriteFailed(err);
            self.db.sqlcipher.stderr.flush() catch |err| sql.warnWriteFailed(err);
        }
    }

    pub fn bindAll(self: Statement, values: []const ?[]const u8) !void {
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
                sql.sqlite_transient,
            )
        else
            self.db.sqlcipher.bind_null(self.handle, index);
        try sql.expectSql(rc, self.db.handle, self.db.sqlcipher);
    }

    pub fn step(self: Statement) !StepResult {
        const rc = self.db.sqlcipher.step(self.handle);
        return switch (rc) {
            sql.sqlite_row => .row,
            sql.sqlite_done => .done,
            else => {
                try sql.expectSql(rc, self.db.handle, self.db.sqlcipher);
                return error.UnexpectedRaycastDatabase;
            },
        };
    }

    pub fn expectDone(self: Statement) !void {
        if (try self.step() == .done) return;
        return error.UnexpectedRaycastDatabase;
    }

    pub fn text(self: Statement, column: c_int) ![]const u8 {
        const value = self.db.sqlcipher.column_text(
            self.handle,
            column,
        ) orelse return error.UnexpectedRaycastDatabase;
        return std.mem.span(value);
    }
};

pub const StepResult = enum { row, done };

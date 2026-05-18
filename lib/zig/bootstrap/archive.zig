const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");
const Context = @import("context.zig").Context;

const Io = std.Io;
const Zip = std.zip;

pub const Kind = enum { tar_xz, tar_gz, zip };

const unix_mode_shift = 16;
const unix_permissions_mask = 0o7777;
const unix_file_type_mask = 0o170000;
const unix_regular_file_type = 0o100000;
const unix_directory_type = 0o040000;
const unix_symlink_type = 0o120000;
const dos_directory_attribute = 0x10;
const dos_epoch_year = 1980;
const zip_extra_extended_timestamp = 0x5455;
const zip_extra_info_zip_unix1 = 0x5855;

// Tiny .tar.xz fixture containing executable pkg/tool with contents "ok\n".
const tiny_tar_xz_bytes = [_]u8{
    0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00, 0x00, 0x01, 0x69, 0x22, 0xde, 0x36, 0x02, 0x00, 0x21, 0x01,
    0x16, 0x00, 0x00, 0x00, 0x74, 0x2f, 0xe5, 0xa3, 0xe0, 0x27, 0xff, 0x00, 0x5e, 0x5d, 0x00, 0x38,
    0x1a, 0xc9, 0x15, 0x9c, 0xbb, 0xcd, 0xf1, 0x02, 0x45, 0x67, 0xec, 0x4d, 0x51, 0xba, 0x8e, 0x6c,
    0x3d, 0xda, 0xfb, 0x60, 0xb2, 0xe2, 0x9c, 0x30, 0x39, 0xb2, 0xcf, 0xe0, 0xce, 0x1b, 0x55, 0x49,
    0xf6, 0x39, 0x3c, 0xa9, 0xb0, 0xce, 0x05, 0x78, 0xf4, 0x46, 0xc0, 0x39, 0xce, 0xb7, 0xeb, 0x9b,
    0xd4, 0xb5, 0x09, 0x83, 0x44, 0x3e, 0xdc, 0xa6, 0x35, 0x60, 0x45, 0xe0, 0x77, 0xf9, 0xb0, 0xf4,
    0x1f, 0xf7, 0xc0, 0x49, 0x50, 0x99, 0x1b, 0x51, 0x77, 0xd0, 0x3b, 0x1f, 0x73, 0x2d, 0x8f, 0x11,
    0xbc, 0x96, 0x34, 0x8e, 0xeb, 0x12, 0xe5, 0x4e, 0xae, 0x14, 0x28, 0x09, 0x00, 0x00, 0x00, 0x00,
    0xd4, 0xba, 0xff, 0xfc, 0x00, 0x01, 0x76, 0x80, 0x50, 0x00, 0x00, 0x00, 0x31, 0x85, 0xc5, 0x64,
    0x3e, 0x30, 0x0d, 0x8b, 0x02, 0x00, 0x00, 0x00, 0x00, 0x01, 0x59, 0x5a,
};

pub fn extract(ctx: *Context, bytes: []const u8, dest_path: []const u8, kind: Kind, strip_components: u32) !void {
    try std.Io.Dir.cwd().createDirPath(ctx.io, dest_path);
    var dest = try std.Io.Dir.openDirAbsolute(ctx.io, dest_path, .{});
    defer dest.close(ctx.io);

    switch (kind) {
        .tar_xz => try extractTarXz(ctx, bytes, dest, strip_components),
        .tar_gz => try extractTarGz(ctx, bytes, dest, strip_components),
        .zip => try extractZip(ctx, bytes, dest),
    }
}

pub fn extractFile(
    ctx: *Context,
    archive_path: []const u8,
    dest_path: []const u8,
    kind: Kind,
    strip_components: u32,
) !void {
    try std.Io.Dir.cwd().createDirPath(ctx.io, dest_path);
    var dest = try std.Io.Dir.openDirAbsolute(ctx.io, dest_path, .{});
    defer dest.close(ctx.io);

    var file = try std.Io.Dir.cwd().openFile(ctx.io, archive_path, .{});
    defer file.close(ctx.io);

    var read_buffer: [8192]u8 = undefined;
    var reader = file.reader(ctx.io, &read_buffer);
    switch (kind) {
        .tar_xz => try extractTarXzReader(ctx, &reader.interface, dest, strip_components),
        .tar_gz => try extractTarGzReader(ctx, &reader.interface, dest, strip_components),
        .zip => try extractZipReader(ctx, &reader, dest),
    }
}

fn extractTarXz(ctx: *Context, bytes: []const u8, dest: std.Io.Dir, strip_components: u32) !void {
    var input: std.Io.Reader = .fixed(bytes);
    try extractTarXzReader(ctx, &input, dest, strip_components);
}

fn extractTarXzReader(ctx: *Context, input: *std.Io.Reader, dest: std.Io.Dir, strip_components: u32) !void {
    const buffer = try ctx.allocator.alloc(u8, 8192);
    var buffer_owner = true;
    errdefer if (buffer_owner) ctx.allocator.free(buffer);
    var xz = try std.compress.xz.Decompress.init(input, ctx.allocator, buffer);
    buffer_owner = false;
    defer xz.deinit();
    try std.tar.extract(ctx.io, dest, &xz.reader, .{ .strip_components = strip_components });
}

fn extractTarGz(ctx: *Context, bytes: []const u8, dest: std.Io.Dir, strip_components: u32) !void {
    var input: std.Io.Reader = .fixed(bytes);
    return extractTarGzReader(ctx, &input, dest, strip_components);
}

fn extractTarGzReader(ctx: *Context, input: *std.Io.Reader, dest: std.Io.Dir, strip_components: u32) !void {
    const buffer = try ctx.allocator.alloc(u8, std.compress.flate.max_window_len);
    defer ctx.allocator.free(buffer);
    var gz = std.compress.flate.Decompress.init(input, .gzip, buffer);
    try std.tar.extract(ctx.io, dest, &gz.reader, .{ .strip_components = strip_components });
}

fn extractZip(ctx: *Context, bytes: []const u8, dest: std.Io.Dir) !void {
    const temp_dir = try common.fs.tempDir(ctx, "bootstrap-zip");
    defer {
        deleteTempDir(ctx, temp_dir);
        ctx.allocator.free(temp_dir);
    }

    const archive_path = try std.fs.path.join(ctx.allocator, &.{ temp_dir, "archive.zip" });
    defer ctx.allocator.free(archive_path);
    errdefer deleteTempArchive(ctx, archive_path);

    try common.fs.writeFile(ctx.io, archive_path, bytes, .{ .read = true });
    {
        var file = try std.Io.Dir.cwd().openFile(ctx.io, archive_path, .{});
        defer file.close(ctx.io);

        var read_buffer: [8192]u8 = undefined;
        var reader = file.reader(ctx.io, &read_buffer);
        try extractZipReader(ctx, &reader, dest);
    }
    try std.Io.Dir.cwd().deleteFile(ctx.io, archive_path);
}

fn extractZipReader(ctx: *Context, reader: *Io.File.Reader, dest: Io.Dir) !void {
    try extractZipPass(ctx, reader, dest, .files_and_dirs);
    try extractZipPass(ctx, reader, dest, .directory_timestamps);
    try extractZipPass(ctx, reader, dest, .symlinks);
    try extractZipPass(ctx, reader, dest, .directory_permissions);
}

const ZipExtractPass = enum { files_and_dirs, directory_timestamps, symlinks, directory_permissions };

fn extractZipPass(ctx: *Context, reader: *Io.File.Reader, dest: Io.Dir, pass: ZipExtractPass) !void {
    var iter = try Zip.Iterator.init(reader);
    var filename_buf: [std.fs.max_path_bytes]u8 = undefined;
    while (try iter.next()) |std_entry| {
        const entry = try ZipEntry.fromStd(reader, std_entry);
        const kind = entry.kind();
        switch (pass) {
            .files_and_dirs => if (kind == .symlink) continue,
            .directory_timestamps => {
                if (kind == .symlink) continue;
                try setZipEntryDirectoryTimestamp(ctx, reader, entry, filename_buf[0..], dest);
                continue;
            },
            .symlinks => if (kind != .symlink) continue,
            .directory_permissions => {
                if (kind == .symlink) continue;
                try setZipEntryDirectoryPermissions(ctx, reader, entry, filename_buf[0..], dest);
                continue;
            },
        }
        try extractZipEntry(ctx, reader, entry, filename_buf[0..], dest);
    }
}

const ZipEntryKind = enum { file, directory, symlink };

const ZipEntry = struct {
    std_entry: Zip.Iterator.Entry,
    version_made_by: u16,
    external_file_attributes: u32,
    modified_timestamp: ?Io.Timestamp,

    fn fromStd(reader: *Io.File.Reader, entry: Zip.Iterator.Entry) !ZipEntry {
        try reader.seekTo(entry.header_zip_offset);
        const header = reader.interface.takeStruct(Zip.CentralDirectoryFileHeader, .little) catch |err| switch (err) {
            error.ReadFailed => return reader.err.?,
            error.EndOfStream => |e| return e,
        };
        if (!std.mem.eql(u8, &header.signature, &Zip.central_file_header_sig))
            return error.ZipBadCdOffset;

        return .{
            .std_entry = entry,
            .version_made_by = header.version_made_by,
            .external_file_attributes = header.external_file_attributes,
            .modified_timestamp = try readZipExtraModifiedTimestamp(reader, entry.header_zip_offset, header),
        };
    }

    fn madeByHost(self: ZipEntry) u8 {
        return @intCast(self.version_made_by >> 8);
    }

    fn hasUnixMode(self: ZipEntry) bool {
        return switch (self.madeByHost()) {
            3, 19 => true, // UNIX, OS X (Darwin)
            else => false,
        };
    }

    fn unixMode(self: ZipEntry) u32 {
        if (!self.hasUnixMode()) return 0;
        return self.external_file_attributes >> unix_mode_shift;
    }

    fn kind(self: ZipEntry) ZipEntryKind {
        const mode = self.unixMode();
        const mode_type = mode & unix_file_type_mask;
        return switch (mode_type) {
            unix_symlink_type => .symlink,
            unix_directory_type => .directory,
            else => if (mode_type == 0 and (self.external_file_attributes & dos_directory_attribute) != 0)
                .directory
            else
                .file,
        };
    }
};

fn extractZipEntry(ctx: *Context, reader: *Io.File.Reader, entry: ZipEntry, filename_buf: []u8, dest: Io.Dir) !void {
    switch (entry.kind()) {
        .directory => try extractZipDirectory(ctx, reader, entry, filename_buf, dest),
        .symlink => try extractZipSymlink(ctx, reader, entry, filename_buf, dest),
        .file => try extractZipFile(ctx, reader, entry, filename_buf, dest),
    }
}

fn readZipFilename(reader: *Io.File.Reader, entry: ZipEntry, filename_buf: []u8) ![]u8 {
    const filename_len: usize = @intCast(entry.std_entry.filename_len);
    if (filename_buf.len < filename_len) return error.ZipInsufficientBuffer;
    const filename = filename_buf[0..filename_len];

    const filename_offset = entry.std_entry.header_zip_offset + @sizeOf(Zip.CentralDirectoryFileHeader);
    try reader.seekTo(filename_offset);
    try reader.interface.readSliceAll(filename);
    if (isBadZipFilename(filename)) return error.ZipBadFilename;
    return filename;
}

fn readZipExtraModifiedTimestamp(
    reader: *Io.File.Reader,
    header_zip_offset: u64,
    header: Zip.CentralDirectoryFileHeader,
) !?Io.Timestamp {
    if (header.extra_len == 0) return null;

    var extra_buf: [std.math.maxInt(u16)]u8 = undefined;
    const extra = extra_buf[0..header.extra_len];
    try reader.seekTo(header_zip_offset + @sizeOf(Zip.CentralDirectoryFileHeader) + header.filename_len);
    reader.interface.readSliceAll(extra) catch |err| switch (err) {
        error.ReadFailed => return reader.err.?,
        error.EndOfStream => |e| return e,
    };

    var modified_timestamp: ?Io.Timestamp = null;
    var extra_offset: usize = 0;
    while (extra_offset + 4 <= extra.len) {
        const header_id = std.mem.readInt(u16, extra[extra_offset..][0..2], .little);
        const data_size = std.mem.readInt(u16, extra[extra_offset..][2..4], .little);
        const end = extra_offset + 4 + data_size;
        if (end > extra.len) return error.ZipBadExtraFieldSize;

        const data = extra[extra_offset + 4 .. end];
        switch (header_id) {
            zip_extra_info_zip_unix1 => {
                if (data.len >= 8)
                    modified_timestamp = unixTimestamp(std.mem.readInt(i32, data[4..8], .little));
            },
            zip_extra_extended_timestamp => {
                if (data.len >= 5 and (data[0] & 0x01) != 0)
                    modified_timestamp = unixTimestamp(std.mem.readInt(i32, data[1..5], .little));
            },
            else => {},
        }
        extra_offset = end;
    }
    if (extra_offset != extra.len) return error.ZipBadExtraFieldSize;
    return modified_timestamp;
}

fn setZipEntryDirectoryPermissions(
    ctx: *Context,
    reader: *Io.File.Reader,
    entry: ZipEntry,
    filename_buf: []u8,
    dest: Io.Dir,
) !void {
    const filename = try readZipFilename(reader, entry, filename_buf);
    if (try zipDirectoryName(entry, filename)) |dirname| {
        try setZipDirPermissions(ctx, dest, dirname, entry.unixMode());
    }
}

fn setZipEntryDirectoryTimestamp(
    ctx: *Context,
    reader: *Io.File.Reader,
    entry: ZipEntry,
    filename_buf: []u8,
    dest: Io.Dir,
) !void {
    const filename = try readZipFilename(reader, entry, filename_buf);
    if (try zipDirectoryName(entry, filename)) |dirname| {
        try setZipModifiedTimestamp(ctx, dest, dirname, entry);
    }
}

fn zipDirectoryName(entry: ZipEntry, filename: []const u8) !?[]const u8 {
    if (filename[filename.len - 1] == '/') {
        if (entry.std_entry.uncompressed_size != 0) return error.ZipBadDirectorySize;
        return filename[0 .. filename.len - 1];
    }
    if (entry.kind() == .directory) {
        if (entry.std_entry.uncompressed_size != 0) return error.ZipBadDirectorySize;
        return filename;
    }
    return null;
}

fn extractZipDirectory(
    ctx: *Context,
    reader: *Io.File.Reader,
    entry: ZipEntry,
    filename_buf: []u8,
    dest: Io.Dir,
) !void {
    const filename = try readZipFilename(reader, entry, filename_buf);
    const dirname = try zipDirectoryName(entry, filename) orelse filename;
    try createZipDir(ctx, dest, dirname);
    try verifyZipCrc(entry, "");
}

fn extractZipFile(
    ctx: *Context,
    reader: *Io.File.Reader,
    entry: ZipEntry,
    filename_buf: []u8,
    dest: Io.Dir,
) !void {
    const permissions = zipPermissions(entry.unixMode(), .default_file);
    try entry.std_entry.extract(reader, .{}, filename_buf, dest);

    const filename = extractedZipFilename(entry, filename_buf);
    if (filename[filename.len - 1] == '/') {
        try verifyZipCrc(entry, "");
        return;
    }

    errdefer dest.deleteFile(ctx.io, filename) catch {};
    try verifyZipFileCrc(ctx, dest, filename, entry.std_entry.crc32);
    try dest.setFilePermissions(ctx.io, filename, permissions, .{});
    try setZipModifiedTimestamp(ctx, dest, filename, entry);
}

fn extractZipSymlink(
    ctx: *Context,
    reader: *Io.File.Reader,
    entry: ZipEntry,
    filename_buf: []u8,
    dest: Io.Dir,
) !void {
    if (entry.std_entry.uncompressed_size > std.fs.max_path_bytes) return error.NameTooLong;

    try entry.std_entry.extract(reader, .{}, filename_buf, dest);
    const filename = extractedZipFilename(entry, filename_buf);
    errdefer dest.deleteFile(ctx.io, filename) catch {};

    const target = try dest.readFileAlloc(ctx.io, filename, ctx.allocator, .limited(std.fs.max_path_bytes));
    defer ctx.allocator.free(target);
    try verifyZipCrc(entry, target);

    try dest.deleteFile(ctx.io, filename);
    try dest.symLink(ctx.io, target, filename, .{});
}

fn extractedZipFilename(entry: ZipEntry, filename_buf: []u8) []u8 {
    return filename_buf[0..entry.std_entry.filename_len];
}

fn createZipDir(ctx: *Context, dest: Io.Dir, dirname: []const u8) !void {
    if (dirname.len == 0) return;
    try dest.createDirPath(ctx.io, dirname);
}

fn setZipDirPermissions(ctx: *Context, dest: Io.Dir, dirname: []const u8, mode: u32) !void {
    if (dirname.len == 0) return;
    const permissions = zipPermissions(mode, .default_dir);
    try dest.setFilePermissions(ctx.io, dirname, permissions, .{});
}

fn zipPermissions(mode: u32, default: Io.File.Permissions) Io.File.Permissions {
    if (mode == 0) return default;
    if (comptime @hasDecl(Io.File.Permissions, "fromMode")) {
        return .fromMode(@intCast(mode & unix_permissions_mask));
    }
    if (!Io.File.Permissions.has_executable_bit or (mode & 0o100) == 0) return default;
    return .executable_file;
}

fn setZipModifiedTimestamp(ctx: *Context, dest: Io.Dir, path: []const u8, entry: ZipEntry) !void {
    const timestamp = zipModifiedTimestamp(entry) orelse return;
    try dest.setTimestamps(ctx.io, path, .{ .modify_timestamp = .{ .new = timestamp } });
}

fn zipModifiedTimestamp(entry: ZipEntry) ?Io.Timestamp {
    return entry.modified_timestamp orelse zipDosTimestamp(
        entry.std_entry.last_modification_date,
        entry.std_entry.last_modification_time,
    );
}

fn unixTimestamp(seconds: i32) Io.Timestamp {
    return .{ .nanoseconds = @as(i96, seconds) * std.time.ns_per_s };
}

fn zipDosTimestamp(date: u16, time: u16) ?Io.Timestamp {
    const year: std.time.epoch.Year = dos_epoch_year + @as(u16, @intCast((date >> 9) & 0x7f));
    const month_int: u4 = @intCast((date >> 5) & 0x0f);
    const day: u5 = @intCast(date & 0x1f);
    const hour: u5 = @intCast((time >> 11) & 0x1f);
    const minute: u6 = @intCast((time >> 5) & 0x3f);
    const second: u6 = @as(u6, @intCast(time & 0x1f)) * 2;

    if (month_int < 1 or day < 1 or hour > 23 or minute > 59 or second > 59) return null;

    const month: std.time.epoch.Month = @enumFromInt(month_int);
    if (day > std.time.epoch.getDaysInMonth(year, month)) return null;

    if (builtin.os.tag == .macos) {
        return localZipDosTimestamp(year, month_int, day, hour, minute, second);
    }

    return utcZipDosTimestamp(year, month, day, hour, minute, second);
}

const MacTm = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int = 0,
    tm_yday: c_int = 0,
    tm_isdst: c_int = -1,
    tm_gmtoff: c_long = 0,
    tm_zone: ?[*:0]const u8 = null,
};

extern "c" fn mktime(timeptr: *MacTm) c_long;

fn localZipDosTimestamp(year: u16, month: u4, day: u5, hour: u5, minute: u6, second: u6) ?Io.Timestamp {
    var tm: MacTm = .{
        .tm_sec = second,
        .tm_min = minute,
        .tm_hour = hour,
        .tm_mday = day,
        .tm_mon = @as(c_int, month) - 1,
        .tm_year = @as(c_int, year) - 1900,
    };
    const seconds = mktime(&tm);
    if (seconds < 0) return null;
    return .{ .nanoseconds = @as(i96, @intCast(seconds)) * std.time.ns_per_s };
}

fn utcZipDosTimestamp(
    year: std.time.epoch.Year,
    month: std.time.epoch.Month,
    day: u5,
    hour: u5,
    minute: u6,
    second: u6,
) Io.Timestamp {
    var days: u64 = 0;
    var current_year: std.time.epoch.Year = std.time.epoch.epoch_year;
    while (current_year < year) : (current_year += 1) {
        days += std.time.epoch.getDaysInYear(current_year);
    }

    var current_month: std.time.epoch.Month = .jan;
    while (@intFromEnum(current_month) < @intFromEnum(month)) {
        days += std.time.epoch.getDaysInMonth(year, current_month);
        current_month = @enumFromInt(@intFromEnum(current_month) + 1);
    }

    days += day - 1;
    const seconds = days * std.time.epoch.secs_per_day +
        @as(u64, hour) * 3600 +
        @as(u64, minute) * 60 +
        second;
    return .{ .nanoseconds = @as(i96, @intCast(seconds)) * std.time.ns_per_s };
}

fn verifyZipCrc(entry: ZipEntry, bytes: []const u8) !void {
    if (std.hash.Crc32.hash(bytes) != entry.std_entry.crc32) return error.ZipCrcMismatch;
}

fn verifyZipFileCrc(ctx: *Context, dest: Io.Dir, filename: []const u8, expected_crc32: u32) !void {
    var file = try dest.openFile(ctx.io, filename, .{});
    defer file.close(ctx.io);

    var read_buffer: [8192]u8 = undefined;
    var reader = file.reader(ctx.io, &read_buffer);
    var hash_buffer: [1024]u8 = undefined;
    var hashed_reader = reader.interface.hashed(std.hash.Crc32.init(), &hash_buffer);
    _ = try hashed_reader.reader.discardRemaining();
    if (hashed_reader.hasher.final() != expected_crc32) return error.ZipCrcMismatch;
}

fn isBadZipFilename(filename: []const u8) bool {
    if (filename.len == 0 or filename[0] == '/') return true;
    if (std.mem.findScalar(u8, filename, '\\')) |_| return true;

    var parts = std.mem.splitScalar(u8, filename, '/');
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, "..")) return true;
    }
    return false;
}

fn deleteTempArchive(ctx: *Context, archive_path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(ctx.io, archive_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => common.output.stderr(
            ctx.io,
            "warning: failed to delete temporary archive {s}: {s}\n",
            .{ archive_path, @errorName(err) },
        ) catch return,
    };
}

fn deleteTempDir(ctx: *Context, path: []const u8) void {
    common.fs.deleteTreeWarning(ctx.io, "temporary directory", path);
}

fn testingContext(env: *std.process.Environ.Map) Context {
    return .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .env = env,
        .home = "",
        .bin_dir = "",
        .opt_dir = "",
    };
}

fn tmpPath(allocator: std.mem.Allocator, tmp: std.testing.TmpDir, parts: []const []const u8) ![]u8 {
    return common.testing.tmpPath(allocator, tmp, parts);
}

fn tinyTarXzBytes() [tiny_tar_xz_bytes.len]u8 {
    return tiny_tar_xz_bytes;
}

const StoredZipEntry = struct {
    name: []const u8,
    data: []const u8,
    mode: u32,
    version_made_by: u16 = (3 << 8) | 20,
    crc32: ?u32 = null,
    last_modification_time: u16 = zipDosTime(0, 0, 0),
    last_modification_date: u16 = zipDosDate(2024, 1, 1),
    extra: []const u8 = "",
};

const zip_version_needed_store = 20;

fn writeStoredZip(ctx: *Context, path: []const u8, entries: []const StoredZipEntry) !void {
    if (std.fs.path.dirname(path)) |dir| {
        try std.Io.Dir.cwd().createDirPath(ctx.io, dir);
    }

    var file = try std.Io.Dir.cwd().createFile(ctx.io, path, .{});
    defer file.close(ctx.io);

    var buffer: [8192]u8 = undefined;
    var writer = file.writer(ctx.io, &buffer);
    var offset: u64 = 0;
    const local_offsets = try ctx.allocator.alloc(u32, entries.len);
    defer ctx.allocator.free(local_offsets);

    for (entries, local_offsets) |entry, *local_offset| {
        local_offset.* = @intCast(offset);
        try writeZipLocalHeader(&writer.interface, entry, &offset);
    }

    const central_dir_offset = offset;
    for (entries, local_offsets) |entry, local_offset| {
        try writeZipCentralHeader(&writer.interface, entry, local_offset, &offset);
    }
    const central_dir_size = offset - central_dir_offset;

    try writeZipEndRecord(&writer.interface, entries.len, central_dir_size, central_dir_offset, &offset);
    try writer.end();
}

fn writeZipLocalHeader(writer: *Io.Writer, entry: StoredZipEntry, offset: *u64) !void {
    const data_len: u32 = @intCast(entry.data.len);
    const name_len: u16 = @intCast(entry.name.len);
    const crc = storedZipCrc(entry);

    var header: Zip.LocalFileHeader = std.mem.zeroes(Zip.LocalFileHeader);
    header.signature = Zip.local_file_header_sig;
    header.version_needed_to_extract = zip_version_needed_store;
    header.compression_method = .store;
    header.last_modification_time = entry.last_modification_time;
    header.last_modification_date = entry.last_modification_date;
    header.crc32 = crc;
    header.compressed_size = data_len;
    header.uncompressed_size = data_len;
    header.filename_len = name_len;
    header.extra_len = @intCast(entry.extra.len);

    try writeZipStruct(writer, header, offset);
    try writeZipBytes(writer, entry.name, offset);
    try writeZipBytes(writer, entry.extra, offset);
    try writeZipBytes(writer, entry.data, offset);
}

fn writeZipCentralHeader(writer: *Io.Writer, entry: StoredZipEntry, local_offset: u32, offset: *u64) !void {
    const data_len: u32 = @intCast(entry.data.len);
    const name_len: u16 = @intCast(entry.name.len);
    const crc = storedZipCrc(entry);

    var header: Zip.CentralDirectoryFileHeader = std.mem.zeroes(Zip.CentralDirectoryFileHeader);
    header.signature = Zip.central_file_header_sig;
    header.version_made_by = entry.version_made_by;
    header.version_needed_to_extract = zip_version_needed_store;
    header.compression_method = .store;
    header.last_modification_time = entry.last_modification_time;
    header.last_modification_date = entry.last_modification_date;
    header.crc32 = crc;
    header.compressed_size = data_len;
    header.uncompressed_size = data_len;
    header.filename_len = name_len;
    header.extra_len = @intCast(entry.extra.len);
    header.external_file_attributes = entry.mode << unix_mode_shift;
    header.local_file_header_offset = local_offset;

    try writeZipStruct(writer, header, offset);
    try writeZipBytes(writer, entry.name, offset);
    try writeZipBytes(writer, entry.extra, offset);
}

fn writeZipEndRecord(
    writer: *Io.Writer,
    entry_count: usize,
    central_dir_size: u64,
    central_dir_offset: u64,
    offset: *u64,
) !void {
    const entry_count_16: u16 = @intCast(entry_count);

    var record: Zip.EndRecord = std.mem.zeroes(Zip.EndRecord);
    record.signature = Zip.end_record_sig;
    record.record_count_disk = entry_count_16;
    record.record_count_total = entry_count_16;
    record.central_directory_size = @intCast(central_dir_size);
    record.central_directory_offset = @intCast(central_dir_offset);

    try writeZipStruct(writer, record, offset);
}

fn writeZipStruct(writer: *Io.Writer, value: anytype, offset: *u64) !void {
    try writer.writeStruct(value, .little);
    offset.* += @sizeOf(@TypeOf(value));
}

fn writeZipBytes(writer: *Io.Writer, bytes: []const u8, offset: *u64) !void {
    try writer.writeAll(bytes);
    offset.* += bytes.len;
}

fn storedZipCrc(entry: StoredZipEntry) u32 {
    return entry.crc32 orelse std.hash.Crc32.hash(entry.data);
}

fn zipDosTime(hour: u5, minute: u6, second: u6) u16 {
    return (@as(u16, hour) << 11) |
        (@as(u16, minute) << 5) |
        @as(u16, second / 2);
}

fn zipDosDate(year: u16, month: u4, day: u5) u16 {
    return (@as(u16, year - dos_epoch_year) << 9) |
        (@as(u16, month) << 5) |
        day;
}

fn infoZipUnix1Extra(access_time: i32, modify_time: i32) [12]u8 {
    var extra: [12]u8 = undefined;
    std.mem.writeInt(u16, extra[0..2], zip_extra_info_zip_unix1, .little);
    std.mem.writeInt(u16, extra[2..4], 8, .little);
    std.mem.writeInt(i32, extra[4..8], access_time, .little);
    std.mem.writeInt(i32, extra[8..12], modify_time, .little);
    return extra;
}

test "zip extraction does not stage archives inside the destination" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest"});
    defer ctx.allocator.free(dest);
    const temp_archive = try std.fs.path.join(ctx.allocator, &.{ dest, ".download.zip" });
    defer ctx.allocator.free(temp_archive);
    try common.fs.writeFile(ctx.io, temp_archive, "keep", .{ .read = true });

    if (extract(&ctx, "not a zip archive", dest, .zip, 0)) {
        return error.TestExpectedError;
    } else |_| {}

    const retained = try std.Io.Dir.cwd().readFileAlloc(ctx.io, temp_archive, ctx.allocator, .limited(16));
    defer ctx.allocator.free(retained);
    try std.testing.expectEqualStrings("keep", retained);
}

test "zip extraction restores stored symlinks" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const archive_path = try tmpPath(ctx.allocator, tmp, &.{"links.zip"});
    defer ctx.allocator.free(archive_path);
    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest-links"});
    defer ctx.allocator.free(dest);
    const link_path = try tmpPath(ctx.allocator, tmp, &.{ "dest-links", "bundle", "link.txt" });
    defer ctx.allocator.free(link_path);

    try writeStoredZip(&ctx, archive_path, &.{
        .{ .name = "bundle/", .data = "", .mode = unix_directory_type | 0o755 },
        .{ .name = "bundle/target.txt", .data = "contents", .mode = unix_regular_file_type | 0o644 },
        .{ .name = "bundle/link.txt", .data = "target.txt", .mode = unix_symlink_type | 0o777 },
    });

    try extractFile(&ctx, archive_path, dest, .zip, 0);

    var link_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const link_len = try std.Io.Dir.cwd().readLink(ctx.io, link_path, &link_buffer);
    try std.testing.expectEqualStrings("target.txt", link_buffer[0..link_len]);
}

test "zip extraction only interprets unix modes from unix hosts" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const archive_path = try tmpPath(ctx.allocator, tmp, &.{"dos-host.zip"});
    defer ctx.allocator.free(archive_path);
    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest-dos-host"});
    defer ctx.allocator.free(dest);
    const file_path = try tmpPath(ctx.allocator, tmp, &.{ "dest-dos-host", "not-link" });
    defer ctx.allocator.free(file_path);

    try writeStoredZip(&ctx, archive_path, &.{
        .{
            .name = "not-link",
            .data = "plain file",
            .mode = unix_symlink_type | 0o777,
            .version_made_by = (0 << 8) | 20,
        },
    });

    try extractFile(&ctx, archive_path, dest, .zip, 0);

    const contents = try std.Io.Dir.cwd().readFileAlloc(ctx.io, file_path, ctx.allocator, .limited(64));
    defer ctx.allocator.free(contents);
    try std.testing.expectEqualStrings("plain file", contents);
}

test "zip extraction restores executable file modes" {
    if (!std.Io.File.Permissions.has_executable_bit) return error.SkipZigTest;

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const archive_path = try tmpPath(ctx.allocator, tmp, &.{"exec.zip"});
    defer ctx.allocator.free(archive_path);
    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest-exec"});
    defer ctx.allocator.free(dest);
    const tool_path = try tmpPath(ctx.allocator, tmp, &.{ "dest-exec", "tool" });
    defer ctx.allocator.free(tool_path);

    try writeStoredZip(&ctx, archive_path, &.{
        .{ .name = "tool", .data = "#!/bin/sh\n", .mode = unix_regular_file_type | 0o755 },
    });

    try extractFile(&ctx, archive_path, dest, .zip, 0);
    try std.Io.Dir.cwd().access(ctx.io, tool_path, .{ .execute = true });
}

test "zip extraction restores file and directory mtimes" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const archive_path = try tmpPath(ctx.allocator, tmp, &.{"mtime.zip"});
    defer ctx.allocator.free(archive_path);
    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest-mtime"});
    defer ctx.allocator.free(dest);
    const dir_path = try tmpPath(ctx.allocator, tmp, &.{ "dest-mtime", "pkg" });
    defer ctx.allocator.free(dir_path);
    const file_path = try tmpPath(ctx.allocator, tmp, &.{ "dest-mtime", "pkg", "tool" });
    defer ctx.allocator.free(file_path);

    const dir_date = zipDosDate(2024, 7, 24);
    const dir_time = zipDosTime(10, 11, 12);
    const file_date = zipDosDate(2025, 8, 25);
    const file_time = zipDosTime(13, 14, 16);
    try writeStoredZip(&ctx, archive_path, &.{
        .{
            .name = "pkg/tool",
            .data = "#!/bin/sh\n",
            .mode = unix_regular_file_type | 0o755,
            .last_modification_date = file_date,
            .last_modification_time = file_time,
        },
        .{
            .name = "pkg/",
            .data = "",
            .mode = unix_directory_type | 0o755,
            .last_modification_date = dir_date,
            .last_modification_time = dir_time,
        },
    });

    try extractFile(&ctx, archive_path, dest, .zip, 0);

    const expected_dir_mtime = zipDosTimestamp(dir_date, dir_time).?;
    const expected_file_mtime = zipDosTimestamp(file_date, file_time).?;
    const dir_stat = try std.Io.Dir.cwd().statFile(ctx.io, dir_path, .{});
    const file_stat = try std.Io.Dir.cwd().statFile(ctx.io, file_path, .{});
    try std.testing.expectEqual(expected_dir_mtime.toSeconds(), dir_stat.mtime.toSeconds());
    try std.testing.expectEqual(expected_file_mtime.toSeconds(), file_stat.mtime.toSeconds());
}

test "zip extraction prefers Info-ZIP Unix mtimes over DOS mtimes" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const archive_path = try tmpPath(ctx.allocator, tmp, &.{"extra-mtime.zip"});
    defer ctx.allocator.free(archive_path);
    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest-extra-mtime"});
    defer ctx.allocator.free(dest);
    const file_path = try tmpPath(ctx.allocator, tmp, &.{ "dest-extra-mtime", "tool" });
    defer ctx.allocator.free(file_path);

    const extra_mtime = 1_778_619_192;
    const extra = infoZipUnix1Extra(extra_mtime, extra_mtime);
    try writeStoredZip(&ctx, archive_path, &.{
        .{
            .name = "tool",
            .data = "#!/bin/sh\n",
            .mode = unix_regular_file_type | 0o755,
            .last_modification_date = zipDosDate(2026, 5, 12),
            .last_modification_time = zipDosTime(13, 53, 12),
            .extra = extra[0..],
        },
    });

    try extractFile(&ctx, archive_path, dest, .zip, 0);

    const stat = try std.Io.Dir.cwd().statFile(ctx.io, file_path, .{});
    try std.testing.expectEqual(unixTimestamp(extra_mtime).toSeconds(), stat.mtime.toSeconds());
}

test "zip extraction applies directory permissions after children" {
    if (!std.Io.File.Permissions.has_executable_bit) return error.SkipZigTest;
    if (comptime !@hasDecl(std.Io.File.Permissions, "toMode")) return error.SkipZigTest;

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const archive_path = try tmpPath(ctx.allocator, tmp, &.{"readonly-dir.zip"});
    defer ctx.allocator.free(archive_path);
    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest-readonly-dir"});
    defer ctx.allocator.free(dest);
    const locked_dir = try tmpPath(ctx.allocator, tmp, &.{ "dest-readonly-dir", "locked" });
    defer ctx.allocator.free(locked_dir);
    defer std.Io.Dir.cwd().setFilePermissions(ctx.io, locked_dir, .default_dir, .{}) catch {};
    const file_path = try tmpPath(ctx.allocator, tmp, &.{ "dest-readonly-dir", "locked", "tool" });
    defer ctx.allocator.free(file_path);
    const link_path = try tmpPath(ctx.allocator, tmp, &.{ "dest-readonly-dir", "locked", "link" });
    defer ctx.allocator.free(link_path);

    try writeStoredZip(&ctx, archive_path, &.{
        .{ .name = "locked/", .data = "", .mode = unix_directory_type | 0o555 },
        .{ .name = "locked/tool", .data = "#!/bin/sh\n", .mode = unix_regular_file_type | 0o755 },
        .{ .name = "locked/link", .data = "tool", .mode = unix_symlink_type | 0o777 },
    });

    try extractFile(&ctx, archive_path, dest, .zip, 0);

    const contents = try std.Io.Dir.cwd().readFileAlloc(ctx.io, file_path, ctx.allocator, .limited(64));
    defer ctx.allocator.free(contents);
    try std.testing.expectEqualStrings("#!/bin/sh\n", contents);

    var link_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const link_len = try std.Io.Dir.cwd().readLink(ctx.io, link_path, &link_buffer);
    try std.testing.expectEqualStrings("tool", link_buffer[0..link_len]);

    const stat = try std.Io.Dir.cwd().statFile(ctx.io, locked_dir, .{});
    try std.testing.expectEqual(@as(u32, 0o555), @as(u32, @intCast(stat.permissions.toMode() & 0o777)));
}

test "zip extraction rejects crc mismatches" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const archive_path = try tmpPath(ctx.allocator, tmp, &.{"bad-crc.zip"});
    defer ctx.allocator.free(archive_path);
    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest-bad-crc"});
    defer ctx.allocator.free(dest);

    try writeStoredZip(&ctx, archive_path, &.{
        .{ .name = "tool", .data = "#!/bin/sh\n", .mode = unix_regular_file_type | 0o755, .crc32 = 0 },
    });

    try std.testing.expectError(error.ZipCrcMismatch, extractFile(&ctx, archive_path, dest, .zip, 0));
}

test "tar xz extraction releases buffer when stream header is invalid" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest"});
    defer ctx.allocator.free(dest);

    try std.testing.expectError(error.NotXzStream, extract(&ctx, "not an xz archive", dest, .tar_xz, 0));
}

test "tar xz extraction releases decompressor-owned buffer after success" {
    const bytes = tinyTarXzBytes();

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest"});
    defer ctx.allocator.free(dest);
    const tool_path = try tmpPath(ctx.allocator, tmp, &.{ "dest", "tool" });
    defer ctx.allocator.free(tool_path);

    try extract(&ctx, bytes[0..], dest, .tar_xz, 1);
    try std.Io.Dir.cwd().access(ctx.io, tool_path, .{ .execute = true });
}

test "tar xz extraction streams from a downloaded file" {
    const bytes = tinyTarXzBytes();

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    var ctx = testingContext(&env);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const archive_path = try tmpPath(ctx.allocator, tmp, &.{"download.tar.xz"});
    defer ctx.allocator.free(archive_path);
    const dest = try tmpPath(ctx.allocator, tmp, &.{"dest-file"});
    defer ctx.allocator.free(dest);
    const tool_path = try tmpPath(ctx.allocator, tmp, &.{ "dest-file", "tool" });
    defer ctx.allocator.free(tool_path);

    try common.fs.writeFile(ctx.io, archive_path, bytes[0..], .{});
    try extractFile(&ctx, archive_path, dest, .tar_xz, 1);
    try std.Io.Dir.cwd().access(ctx.io, tool_path, .{ .execute = true });
}

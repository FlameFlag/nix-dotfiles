const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const cf_false: u8 = 0;
const cf_true: u8 = 1;
const cf_utf8 = 0x08000100;
const cf_url_posix_path_style = 0;
const ls_launch_defaults = 0x00000001;
const ls_launch_dont_switch = 0x00000200;
const proc_all_pids = 1;
const proc_pidpathinfo_maxsize = 4096;

extern fn proc_listpids(type: c_uint, typeinfo: c_uint, buffer: ?*anyopaque, buffersize: c_int) c_int;
extern fn proc_pidpath(pid: c_int, buffer: [*]u8, buffersize: u32) c_int;

const LSLaunchURLSpec = extern struct {
    app_url: ?*const anyopaque,
    item_urls: ?*const anyopaque,
    pass_thru_params: ?*const anyopaque,
    launch_flags: u32,
    async_ref_con: ?*anyopaque,
};

pub const CoreFoundation = struct {
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

    pub fn load() !CoreFoundation {
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

    pub fn deinit(self: *CoreFoundation) void {
        self.lib.close();
    }

    pub fn string(self: CoreFoundation, value: []const u8) !*anyopaque {
        return self.create_string(null, value.ptr, @intCast(value.len), cf_utf8, cf_false) orelse error.CoreFoundationFailed;
    }

    pub fn addStringToAppArrayPreference(self: CoreFoundation, app_id: []const u8, key: []const u8, value: []const u8) !void {
        const app_ref = try self.string(app_id);
        defer self.release(app_ref);
        const key_ref = try self.string(key);
        defer self.release(key_ref);
        const value_ref = try self.string(value);
        defer self.release(value_ref);

        const existing = self.preferences_copy_app_value(key_ref, app_ref);
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
        self.preferences_set_app_value(key_ref, mutable_array, app_ref);
        if (self.preferences_app_synchronize(app_ref) == cf_false) return error.PreferencesWriteFailed;
    }

    pub fn isArray(self: CoreFoundation, ref: *anyopaque) bool {
        return self.get_type_id(ref) == self.array_get_type_id();
    }

    pub fn arrayContains(self: CoreFoundation, array: *anyopaque, value: *anyopaque) bool {
        const count = self.array_get_count(array);
        var index: isize = 0;
        while (index < count) : (index += 1) {
            const item = self.array_get_value_at_index(array, index) orelse continue;
            if (self.equal(item, value) != cf_false) return true;
        }
        return false;
    }
};

pub const Security = struct {
    lib: std.DynLib,
    find_generic_password: *const fn (?*anyopaque, u32, ?[*]const u8, u32, ?[*]const u8, *u32, *?*anyopaque, ?*?*anyopaque) callconv(.c) i32,
    free_content: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) i32,

    pub fn load() !Security {
        var lib = try std.DynLib.open("/System/Library/Frameworks/Security.framework/Security");
        errdefer lib.close();

        return .{
            .lib = lib,
            .find_generic_password = try dynLookup(@TypeOf(@as(Security, undefined).find_generic_password), &lib, "SecKeychainFindGenericPassword"),
            .free_content = try dynLookup(@TypeOf(@as(Security, undefined).free_content), &lib, "SecKeychainItemFreeContent"),
        };
    }

    pub fn deinit(self: *Security) void {
        self.lib.close();
    }

    pub fn genericPassword(self: Security, allocator: Allocator, service: []const u8, account: []const u8) ![]u8 {
        var password_len: u32 = 0;
        var password_data: ?*anyopaque = null;
        const status = self.find_generic_password(
            null,
            @intCast(service.len),
            service.ptr,
            @intCast(account.len),
            account.ptr,
            &password_len,
            &password_data,
            null,
        );
        if (status != 0) return error.KeychainPasswordNotFound;
        defer _ = self.free_content(null, password_data);

        return try copyTrimmedPassword(allocator, password_data, password_len);
    }
};

pub const LaunchServices = struct {
    lib: std.DynLib,
    open_from_url_spec: *const fn (*const LSLaunchURLSpec, ?*?*anyopaque) callconv(.c) i32,

    pub fn load() !LaunchServices {
        var lib = try std.DynLib.open("/System/Library/Frameworks/CoreServices.framework/CoreServices");
        errdefer lib.close();

        return .{
            .lib = lib,
            .open_from_url_spec = try dynLookup(@TypeOf(@as(LaunchServices, undefined).open_from_url_spec), &lib, "LSOpenFromURLSpec"),
        };
    }

    pub fn deinit(self: *LaunchServices) void {
        self.lib.close();
    }

    pub fn openApplicationNoActivate(self: LaunchServices, cf: CoreFoundation, app_path: []const u8) !void {
        const app_path_ref = try cf.string(app_path);
        defer cf.release(app_path_ref);
        const app_url = cf.url_create_with_file_system_path(null, app_path_ref, cf_url_posix_path_style, cf_true) orelse return error.CoreFoundationFailed;
        defer cf.release(app_url);

        const launch_spec: LSLaunchURLSpec = .{
            .app_url = app_url,
            .item_urls = null,
            .pass_thru_params = null,
            .launch_flags = ls_launch_defaults | ls_launch_dont_switch,
            .async_ref_con = null,
        };
        const status = self.open_from_url_spec(&launch_spec, null);
        if (status != 0) return error.ApplicationLaunchFailed;
    }
};

pub fn pidsForExecutablePath(io: std.Io, allocator: Allocator, executable_path: []const u8) ![]std.posix.pid_t {
    _ = io;
    const initial_bytes = proc_listpids(proc_all_pids, 0, null, 0);
    if (initial_bytes < 0) return error.ProcessListFailed;

    const initial_count: usize = @intCast(@divTrunc(initial_bytes, @sizeOf(c_int)));
    const pids = try allocator.alloc(c_int, initial_count + 256);
    defer allocator.free(pids);

    const byte_count = proc_listpids(proc_all_pids, 0, pids.ptr, @intCast(pids.len * @sizeOf(c_int)));
    if (byte_count < 0) return error.ProcessListFailed;

    var matches: std.ArrayList(std.posix.pid_t) = .empty;
    errdefer matches.deinit(allocator);

    const count: usize = @intCast(@divTrunc(byte_count, @sizeOf(c_int)));
    for (pids[0..@min(count, pids.len)]) |pid| {
        if (pid <= 0) continue;

        var path_buffer: [proc_pidpathinfo_maxsize]u8 = undefined;
        const path_len = proc_pidpath(pid, &path_buffer, path_buffer.len);
        if (path_len <= 0) continue;

        const path = path_buffer[0..@intCast(path_len)];
        try appendPidIfPathMatches(allocator, &matches, pid, path, executable_path);
    }

    return try matches.toOwnedSlice(allocator);
}

fn appendPidIfPathMatches(
    allocator: Allocator,
    matches: *std.ArrayList(std.posix.pid_t),
    pid: c_int,
    path: []const u8,
    executable_path: []const u8,
) !void {
    if (!std.mem.eql(u8, path, executable_path)) return;
    try matches.append(allocator, @intCast(pid));
}

fn copyTrimmedPassword(allocator: Allocator, password_data: ?*anyopaque, password_len: u32) ![]u8 {
    const data = password_data orelse return error.KeychainPasswordNotFound;
    const bytes: [*]const u8 = @ptrCast(data);
    const key = std.mem.trim(u8, bytes[0..password_len], " \t\r\n");
    if (key.len == 0) return error.KeychainPasswordNotFound;
    return try allocator.dupe(u8, key);
}

fn dynLookup(comptime T: type, lib: *std.DynLib, comptime name: [:0]const u8) !T {
    return lib.lookup(T, name) orelse error.DynamicSymbolMissing;
}

test "copyTrimmedPassword copies keychain bytes and rejects empty secrets" {
    var key_bytes = "  secret-key\n".*;
    const key = try copyTrimmedPassword(std.testing.allocator, &key_bytes, key_bytes.len);
    defer std.testing.allocator.free(key);

    try std.testing.expectEqualStrings("secret-key", key);
    try std.testing.expectError(error.KeychainPasswordNotFound, copyTrimmedPassword(std.testing.allocator, null, 0));

    var blank = " \t\r\n".*;
    try std.testing.expectError(error.KeychainPasswordNotFound, copyTrimmedPassword(std.testing.allocator, &blank, blank.len));
}

test "appendPidIfPathMatches filters exact executable path" {
    var matches: std.ArrayList(std.posix.pid_t) = .empty;
    defer matches.deinit(std.testing.allocator);

    try appendPidIfPathMatches(std.testing.allocator, &matches, 42, "/Applications/Other.app/Contents/MacOS/App", "/Applications/App.app/Contents/MacOS/App");
    try std.testing.expectEqual(@as(usize, 0), matches.items.len);

    try appendPidIfPathMatches(std.testing.allocator, &matches, 42, "/Applications/App.app/Contents/MacOS/App", "/Applications/App.app/Contents/MacOS/App");
    try std.testing.expectEqual(@as(usize, 1), matches.items.len);
    try std.testing.expectEqual(@as(std.posix.pid_t, 42), matches.items[0]);
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

test "LaunchServices creates app URL spec without launching" {
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

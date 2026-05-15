const std = @import("std");
const builtin = @import("builtin");

const cli = @import("cli.zig");
const constants = @import("constants.zig");

pub fn isSupported() !bool {
    if (builtin.os.tag != .windows) return false;
    var backend = EnergyDriver.open(.read) catch |err| switch (err) {
        error.FileNotFound, error.UnsupportedWindowsBackend => return false,
        error.AccessDenied => return true,
        else => return err,
    };
    defer backend.close();

    _ = backend.readGbmd() catch |err| switch (err) {
        error.UnsupportedWindowsBackend => return false,
        error.AccessDenied, error.UnexpectedWindowsError => return true,
    };
    return true;
}

pub fn readMode(stderr: *std.Io.Writer) !bool {
    var backend = EnergyDriver.open(.read) catch |err| switch (err) {
        error.FileNotFound => return cli.fail(
            bool,
            "Lenovo ACPI Virtual Power Controller device not found: {s}",
            stderr,
            .{constants.windows_energy_drv_path},
        ),
        error.AccessDenied => return cli.fail(
            bool,
            "permission denied opening {s}; run as administrator",
            stderr,
            .{constants.windows_energy_drv_path},
        ),
        error.UnsupportedWindowsBackend => return cli.fail(
            bool,
            "Lenovo ACPI backend is unavailable on this Windows system",
            stderr,
            .{},
        ),
        else => return cli.fail(
            bool,
            "failed to open {s}: {s}",
            stderr,
            .{ constants.windows_energy_drv_path, @errorName(err) },
        ),
    };
    defer backend.close();

    const gbmd = backend.readGbmd() catch |err| switch (err) {
        error.UnsupportedWindowsBackend => return cli.fail(
            bool,
            "Lenovo ACPI driver did not accept the GBMD query",
            stderr,
            .{},
        ),
        error.AccessDenied => return cli.fail(
            bool,
            "permission denied querying Lenovo conservation mode; run as administrator",
            stderr,
            .{},
        ),
        else => return cli.fail(bool, "Lenovo ACPI GBMD query failed: {s}", stderr, .{@errorName(err)}),
    };
    return conservationState(gbmd);
}

pub fn writeMode(stderr: *std.Io.Writer, enabled: bool) !void {
    var backend = EnergyDriver.open(.write) catch |err| switch (err) {
        error.FileNotFound => return cli.fail(
            void,
            "Lenovo ACPI Virtual Power Controller device not found: {s}",
            stderr,
            .{constants.windows_energy_drv_path},
        ),
        error.AccessDenied => return cli.fail(
            void,
            "permission denied opening {s}; run as administrator",
            stderr,
            .{constants.windows_energy_drv_path},
        ),
        error.UnsupportedWindowsBackend => return cli.fail(
            void,
            "Lenovo ACPI backend is unavailable on this Windows system",
            stderr,
            .{},
        ),
        else => return cli.fail(
            void,
            "failed to open {s}: {s}",
            stderr,
            .{ constants.windows_energy_drv_path, @errorName(err) },
        ),
    };
    defer backend.close();

    backend.setConservationMode(enabled) catch |err| switch (err) {
        error.UnsupportedWindowsBackend => return cli.fail(
            void,
            "Lenovo ACPI driver did not accept the SBMC conservation command",
            stderr,
            .{},
        ),
        error.AccessDenied => return cli.fail(
            void,
            "permission denied changing Lenovo conservation mode; run as administrator",
            stderr,
            .{},
        ),
        else => return cli.fail(void, "Lenovo ACPI SBMC conservation command failed: {s}", stderr, .{@errorName(err)}),
    };
}

fn conservationState(gbmd: u32) bool {
    return (gbmd & (@as(u32, 1) << constants.windows_gbmd_conservation_state_bit)) != 0;
}

const EnergyDriver = if (builtin.os.tag == .windows) struct {
    const Self = @This();
    const windows = std.os.windows;
    const Dword = windows.DWORD;
    const Handle = windows.HANDLE;
    const Bool = windows.BOOL;
    const Hmodule = windows.HMODULE;
    const invalid_handle_value = windows.INVALID_HANDLE_VALUE;

    const Access = enum { read, write };
    const generic_read: Dword = 0x80000000;
    const generic_write: Dword = 0x40000000;
    const file_share_read: Dword = 0x00000001;
    const file_share_write: Dword = 0x00000002;
    const open_existing: Dword = 3;

    const CreateFileW = *const fn (
        lpFileName: [*:0]const u16,
        dwDesiredAccess: Dword,
        dwShareMode: Dword,
        lpSecurityAttributes: ?*anyopaque,
        dwCreationDisposition: Dword,
        dwFlagsAndAttributes: Dword,
        hTemplateFile: ?Handle,
    ) callconv(.winapi) Handle;
    const DeviceIoControl = *const fn (
        hDevice: Handle,
        dwIoControlCode: Dword,
        lpInBuffer: ?*anyopaque,
        nInBufferSize: Dword,
        lpOutBuffer: ?*anyopaque,
        nOutBufferSize: Dword,
        lpBytesReturned: *Dword,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) Bool;
    const CloseHandle = *const fn (hObject: Handle) callconv(.winapi) Bool;

    kernel32: Hmodule,
    handle: Handle,
    device_io_control: DeviceIoControl,
    close_handle: CloseHandle,

    extern "kernel32" fn LoadLibraryW(lpLibFileName: [*:0]const u16) callconv(.winapi) ?Hmodule;
    extern "kernel32" fn GetProcAddress(hModule: Hmodule, lpProcName: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(hLibModule: Hmodule) callconv(.winapi) Bool;

    fn open(access: Access) !Self {
        const kernel32_path = std.unicode.utf8ToUtf16LeStringLiteral("kernel32.dll");
        const kernel32 = LoadLibraryW(kernel32_path) orelse return error.UnsupportedWindowsBackend;
        errdefer _ = FreeLibrary(kernel32);

        const create_file: CreateFileW =
            @ptrCast(GetProcAddress(kernel32, "CreateFileW") orelse return error.UnsupportedWindowsBackend);
        const device_io_control: DeviceIoControl =
            @ptrCast(GetProcAddress(kernel32, "DeviceIoControl") orelse return error.UnsupportedWindowsBackend);
        const close_handle: CloseHandle =
            @ptrCast(GetProcAddress(kernel32, "CloseHandle") orelse return error.UnsupportedWindowsBackend);

        const desired_access = generic_read | switch (access) {
            .read => 0,
            .write => generic_write,
        };
        const path_w = std.unicode.utf8ToUtf16LeStringLiteral(constants.windows_energy_drv_path);
        const handle = create_file(
            path_w,
            desired_access,
            file_share_read | file_share_write,
            null,
            open_existing,
            0,
            null,
        );
        if (handle == invalid_handle_value) {
            return switch (windows.GetLastError()) {
                .FILE_NOT_FOUND, .PATH_NOT_FOUND => error.FileNotFound,
                .ACCESS_DENIED => error.AccessDenied,
                else => error.UnexpectedWindowsError,
            };
        }

        return .{
            .kernel32 = kernel32,
            .handle = handle,
            .device_io_control = device_io_control,
            .close_handle = close_handle,
        };
    }

    fn close(self: *Self) void {
        _ = self.close_handle(self.handle);
        _ = FreeLibrary(self.kernel32);
    }

    fn readGbmd(self: *Self) !u32 {
        var buffer = [_]u8{ constants.windows_sbmc_query_gbmd, 0, 0, 0 };
        try self.ioctl(&buffer, &buffer);
        return std.mem.readInt(u32, buffer[0..4], .little);
    }

    fn setConservationMode(self: *Self, enabled: bool) !void {
        var buffer = [_]u8{
            if (enabled) constants.windows_sbmc_conservation_on else constants.windows_sbmc_conservation_off,
            0,
            0,
            0,
        };
        try self.ioctl(&buffer, &buffer);
    }

    fn ioctl(self: *Self, input: []u8, output: []u8) !void {
        var bytes_returned: Dword = 0;
        if (self.device_io_control(
            self.handle,
            constants.windows_energy_ioctl_gbmd_sbmc,
            input.ptr,
            @intCast(input.len),
            output.ptr,
            @intCast(output.len),
            &bytes_returned,
            null,
        ).toBool()) {
            return;
        } else {
            return switch (windows.GetLastError()) {
                .ACCESS_DENIED => error.AccessDenied,
                .INVALID_FUNCTION, .INVALID_PARAMETER => error.UnsupportedWindowsBackend,
                else => error.UnexpectedWindowsError,
            };
        }
    }
} else struct {};

test "read conservation state from GBMD bitfield" {
    try std.testing.expect(!conservationState(0));
    try std.testing.expect(conservationState(@as(u32, 1) << constants.windows_gbmd_conservation_state_bit));
}

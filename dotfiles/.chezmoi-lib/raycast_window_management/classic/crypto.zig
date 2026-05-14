const std = @import("std");
const script = @import("chezmoi");
const macos = script.macos;
const constants = @import("constants.zig");

pub const SaltExtraction = union(enum) {
    after_previous_printable_string: []const u8,
    first_printable_after_anchor: []const u8,
};

/// Derives the SQLCipher key from Raycast's keychain entry and app salt.
///
/// Caller owns returned memory.
pub fn databasePassword(rt: *script.Runtime) ![]u8 {
    return databasePasswordFor(
        rt,
        "Raycast",
        "database_key",
        constants.raycast_bin,
        .{ .after_previous_printable_string = "copyDatabaseEncryptionPassphraseToClipboard()" },
    );
}

/// Derives a Raycast-family SQLCipher key from a keychain entry and app binary salt.
///
/// Caller owns returned memory.
pub fn databasePasswordFor(
    rt: *script.Runtime,
    keychain_service: []const u8,
    keychain_account: []const u8,
    app_bin: []const u8,
    salt_extraction: SaltExtraction,
) ![]u8 {
    var security = try macos.Security.load();
    defer security.deinit();
    const key = security.genericPassword(rt.allocator, keychain_service, keychain_account) catch |err| switch (err) {
        error.KeychainPasswordNotFound => return error.RaycastDatabaseKeyNotFound,
        else => return err,
    };
    defer rt.allocator.free(key);

    const salt = try extractSalt(rt, app_bin, salt_extraction);
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
fn extractSalt(rt: *script.Runtime, app_bin: []const u8, salt_extraction: SaltExtraction) ![]u8 {
    const contents = try std.Io.Dir.cwd().readFileAlloc(
        rt.io,
        app_bin,
        rt.allocator,
        .limited(constants.app_binary_read_limit),
    );
    defer rt.allocator.free(contents);
    return (try findSalt(rt.allocator, contents, salt_extraction)) orelse error.RaycastSaltNotFound;
}

fn findSalt(allocator: script.Allocator, contents: []const u8, salt_extraction: SaltExtraction) !?[]u8 {
    return switch (salt_extraction) {
        .after_previous_printable_string => |previous_string| findSaltAfterPrintableString(
            allocator,
            contents,
            previous_string,
        ),
        .first_printable_after_anchor => |anchor| findFirstSaltAfterAnchor(
            allocator,
            contents,
            anchor,
        ),
    };
}

fn findSaltAfterPrintableString(
    allocator: script.Allocator,
    contents: []const u8,
    previous_string: []const u8,
) !?[]u8 {
    var previous: []const u8 = "";
    var index: usize = 0;
    while (index < contents.len) {
        while (index < contents.len and !isPrintableAscii(contents[index])) : (index += 1) {}
        const start = index;
        while (index < contents.len and isPrintableAscii(contents[index])) : (index += 1) {}
        const string_run = contents[start..index];
        if (string_run.len >= 4) {
            if (std.mem.eql(u8, previous, previous_string) and isAsciiSalt(string_run)) {
                return @as(?[]u8, try allocator.dupe(u8, string_run));
            }
            previous = string_run;
        }
    }
    return null;
}

fn findFirstSaltAfterAnchor(
    allocator: script.Allocator,
    contents: []const u8,
    anchor: []const u8,
) !?[]u8 {
    const start = std.mem.indexOf(u8, contents, anchor) orelse return null;
    var index = start + anchor.len;
    while (index < contents.len) {
        while (index < contents.len and !isPrintableAscii(contents[index])) : (index += 1) {}
        const run_start = index;
        while (index < contents.len and isPrintableAscii(contents[index])) : (index += 1) {}
        const string_run = contents[run_start..index];
        if (isAsciiSalt(string_run)) return @as(?[]u8, try allocator.dupe(u8, string_run));
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

test "findSaltAfterPrintableString reads printable strings like strings -a" {
    const contents =
        "noise\x00" ++
        "copyDatabaseEncryptionPassphraseToClipboard()\x00" ++
        "0123456789abcdef0123456789ABCDEF\x00";
    const salt = try findSaltAfterPrintableString(
        std.testing.allocator,
        contents,
        "copyDatabaseEncryptionPassphraseToClipboard()",
    ) orelse return error.TestExpectedSalt;
    defer std.testing.allocator.free(salt);

    try std.testing.expectEqualStrings("0123456789abcdef0123456789ABCDEF", salt);
}

test "findFirstSaltAfterAnchor reads first salt after anchor" {
    const contents =
        "noise\x00" ++
        "com.raycast-x.deleted\x00" ++
        "0123456789abcdef0123456789ABCDEF\x00";
    const salt = try findFirstSaltAfterAnchor(
        std.testing.allocator,
        contents,
        "com.raycast-x.deleted",
    ) orelse return error.TestExpectedSalt;
    defer std.testing.allocator.free(salt);

    try std.testing.expectEqualStrings("0123456789abcdef0123456789ABCDEF", salt);
}

test "findSaltAfterPrintableString rejects missing and invalid salt candidates" {
    try std.testing.expectEqual(
        null,
        try findSaltAfterPrintableString(
            std.testing.allocator,
            "copyDatabaseEncryptionPassphraseToClipboard()\x00short\x00",
            "copyDatabaseEncryptionPassphraseToClipboard()",
        ),
    );
    try std.testing.expectEqual(
        null,
        try findSaltAfterPrintableString(
            std.testing.allocator,
            "before\x000123456789abcdef0123456789ABCDEF\x00",
            "copyDatabaseEncryptionPassphraseToClipboard()",
        ),
    );
    try std.testing.expectEqual(
        null,
        try findSaltAfterPrintableString(
            std.testing.allocator,
            "copyDatabaseEncryptionPassphraseToClipboard()\x00" ++
                "0123456789abcdef0123456789ABC\n",
            "copyDatabaseEncryptionPassphraseToClipboard()",
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

const std = @import("std");
const Context = @import("context.zig").Context;
const http = @import("http.zig");

const GithubReleaseJson = struct {
    tag_name: []const u8,
    assets: []const GithubAssetJson,
};

const GithubAssetJson = struct {
    name: []const u8,
    browser_download_url: []const u8,
};

pub const GithubRelease = struct {
    json: std.json.Parsed(GithubReleaseJson),

    pub fn deinit(self: *GithubRelease) void {
        self.json.deinit();
        self.* = undefined;
    }

    pub fn tag(self: GithubRelease) []const u8 {
        return self.json.value.tag_name;
    }

    pub fn assetUrl(self: GithubRelease, name: []const u8) ![]const u8 {
        for (self.json.value.assets) |asset| {
            if (std.mem.eql(u8, asset.name, name)) return asset.browser_download_url;
        }
        return error.AssetNotFound;
    }
};

pub fn latestGithub(ctx: *Context, repo: []const u8) !GithubRelease {
    const url = try std.fmt.allocPrint(ctx.allocator, "https://api.github.com/repos/{s}/releases/latest", .{repo});
    defer ctx.allocator.free(url);
    const json = try http.getBytes(ctx, url);
    defer ctx.allocator.free(json);
    return .{ .json = try std.json.parseFromSlice(GithubReleaseJson, ctx.allocator, json, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) };
}

pub fn versionFromTag(tag: []const u8, prefix: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, tag, prefix)) tag[prefix.len..] else tag;
}

test "version strings trim configured prefixes" {
    try std.testing.expectEqualStrings("2.70.3", versionFromTag("v2.70.3", "v"));
    try std.testing.expectEqualStrings("1.2.0", versionFromTag("bun-1.2.0", "bun-"));
    try std.testing.expectEqualStrings("0.16.0", versionFromTag("0.16.0", "v"));
}

test "github release lookup validates tag and assets" {
    const release_json = try std.json.parseFromSlice(GithubReleaseJson, std.testing.allocator,
        \\{
        \\  "tag_name": "v1.2.3",
        \\  "extra": "ignored",
        \\  "assets": [
        \\    {
        \\      "name": "tool-aarch64-macos.tar.xz",
        \\      "browser_download_url": "https://example.test/tool.tar.xz",
        \\      "size": 123
        \\    }
        \\  ]
        \\}
    , .{ .ignore_unknown_fields = true });
    var github_release: GithubRelease = .{ .json = release_json };
    defer github_release.deinit();

    try std.testing.expectEqualStrings("v1.2.3", github_release.tag());
    try std.testing.expectEqualStrings(
        "https://example.test/tool.tar.xz",
        try github_release.assetUrl("tool-aarch64-macos.tar.xz"),
    );
    try std.testing.expectError(error.AssetNotFound, github_release.assetUrl("missing.tar.xz"));
}

test "github release parser requires typed fields" {
    try std.testing.expectError(
        error.MissingField,
        std.json.parseFromSlice(
            GithubReleaseJson,
            std.testing.allocator,
            "{\"assets\":[]}",
            .{ .ignore_unknown_fields = true },
        ),
    );
}

const std = @import("std");

pub const Template = struct {
    value: []const u8,

    pub fn literal(value: []const u8) Template {
        return .{ .value = value };
    }

    pub fn validate(self: Template, allowed: []const []const u8) !void {
        var rest = self.value;
        while (std.mem.findScalar(u8, rest, '{')) |open| {
            const close_offset = std.mem.indexOfScalar(u8, rest[open + 1 ..], '}') orelse return error.InvalidTemplate;
            const close = open + 1 + close_offset;
            const name = rest[open + 1 .. close];
            if (!nameAllowed(name, allowed)) return error.UnknownTemplateVariable;
            rest = rest[close + 1 ..];
        }
    }

    pub fn render(self: Template, allocator: std.mem.Allocator, bindings: Bindings) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(allocator);

        var rest = self.value;
        while (std.mem.findScalar(u8, rest, '{')) |open| {
            try output.appendSlice(allocator, rest[0..open]);
            const close_offset = std.mem.indexOfScalar(u8, rest[open + 1 ..], '}') orelse return error.InvalidTemplate;
            const close = open + 1 + close_offset;
            try output.appendSlice(allocator, bindings.value(rest[open + 1 .. close]) orelse {
                return error.UnknownTemplateVariable;
            });
            rest = rest[close + 1 ..];
        }
        try output.appendSlice(allocator, rest);
        return output.toOwnedSlice(allocator);
    }

    pub fn renderSlice(
        allocator: std.mem.Allocator,
        templates: []const []const u8,
        bindings: Bindings,
    ) ![]const []const u8 {
        const rendered = try allocator.alloc([]const u8, templates.len);
        errdefer allocator.free(rendered);

        var initialized: usize = 0;
        errdefer {
            for (rendered[0..initialized]) |entry| allocator.free(entry);
        }

        for (templates, rendered) |template, *out| {
            out.* = try Template.literal(template).render(allocator, bindings);
            initialized += 1;
        }
        return rendered;
    }
};

pub const Bindings = struct {
    version: []const u8 = "",
    platform: []const u8 = "",
    file: []const u8 = "",
    bin_dir: []const u8 = "",
    opt_dir: []const u8 = "",
    home: []const u8 = "",
    toolchain: []const u8 = "",
    manager_bin: []const u8 = "",
    component: []const u8 = "",

    fn value(self: Bindings, name: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, name, "version")) return self.version;
        if (std.mem.eql(u8, name, "platform")) return self.platform;
        if (std.mem.eql(u8, name, "file")) return self.file;
        if (std.mem.eql(u8, name, "bin_dir")) return self.bin_dir;
        if (std.mem.eql(u8, name, "opt_dir")) return self.opt_dir;
        if (std.mem.eql(u8, name, "home")) return self.home;
        if (std.mem.eql(u8, name, "toolchain")) return self.toolchain;
        if (std.mem.eql(u8, name, "manager_bin")) return self.manager_bin;
        if (std.mem.eql(u8, name, "component")) return self.component;
        return null;
    }
};

pub fn freeSlice(allocator: std.mem.Allocator, rendered: []const []const u8) void {
    for (rendered) |entry| allocator.free(entry);
    allocator.free(rendered);
}

fn nameAllowed(name: []const u8, allowed: []const []const u8) bool {
    for (allowed) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

test "templates render named bindings" {
    const rendered = try Template.literal("{file} --bin={bin_dir} --home={home}").render(std.testing.allocator, .{
        .file = "/tmp/install.sh",
        .bin_dir = "/home/me/.local/bin",
        .home = "/home/me",
    });
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings("/tmp/install.sh --bin=/home/me/.local/bin --home=/home/me", rendered);
}

test "templates validate unknown placeholders" {
    try Template.literal("tool-{version}-{platform}.tar.gz").validate(&.{ "version", "platform" });
    try std.testing.expectError(
        error.UnknownTemplateVariable,
        Template.literal("tool-{unknown}.tar.gz").validate(&.{"version"}),
    );
    try std.testing.expectError(
        error.InvalidTemplate,
        Template.literal("tool-{version.tar.gz").validate(&.{"version"}),
    );
}

test "template slices render argv entries" {
    const argv = try Template.renderSlice(std.testing.allocator, &.{ "sh", "{file}", "-b", "{bin_dir}" }, .{
        .file = "/tmp/install.sh",
        .bin_dir = "/home/me/.local/bin",
    });
    defer freeSlice(std.testing.allocator, argv);

    try std.testing.expectEqualStrings("sh", argv[0]);
    try std.testing.expectEqualStrings("/tmp/install.sh", argv[1]);
    try std.testing.expectEqualStrings("/home/me/.local/bin", argv[3]);
}

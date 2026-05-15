const std = @import("std");

pub const actions = @import("tools/actions.zig");
pub const catalog = @import("tools/catalog.zig");
pub const host = @import("tools/host.zig");
pub const installer = @import("tools/install.zig");
const bootstrap = @import("bootstrap");

pub const Catalog = catalog.Catalog;
pub const Policy = bootstrap.manifest.Policy;

pub const installAll = installer.all;
pub const loadCatalog = catalog.load;

test {
    std.testing.refAllDecls(actions);
    std.testing.refAllDecls(catalog);
    std.testing.refAllDecls(host);
    std.testing.refAllDecls(installer);
}

const bootstrap = @import("bootstrap");

const Context = bootstrap.Context;
const manifest = bootstrap.manifest;

pub const HostFacts = bootstrap.host.HostFacts;
pub const currentFacts = bootstrap.host.currentFacts;
pub const currentHostOs = bootstrap.host.currentHostOs;
pub const currentHostArch = bootstrap.host.currentHostArch;
pub const isLaptopChassisType = bootstrap.host.isLaptopChassisType;
pub const isLenovoVendor = bootstrap.host.isLenovoVendor;
pub const isNixOs = bootstrap.host.isNixOs;
pub const meetsRequirement = bootstrap.host.meetsRequirement;
pub const osReleaseIsNixOs = bootstrap.host.osReleaseIsNixOs;
pub const windowsProbeOutputIsLenovoLaptop = bootstrap.host.windowsProbeOutputIsLenovoLaptop;

pub fn supportsTool(tool: manifest.Tool, ctx: *Context) !bool {
    return bootstrap.host.supportsTool(ctx, tool);
}

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}

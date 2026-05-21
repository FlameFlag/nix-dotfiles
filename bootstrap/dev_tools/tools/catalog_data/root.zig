const bootstrap = @import("bootstrap");
const bun = @import("bun.zig");
const chezmoi = @import("chezmoi.zig");
const gh_hide_comment = @import("gh-hide-comment.zig");
const git = @import("git.zig");
const lenovo_con_mode = @import("lenovo-con-mode.zig");
const node = @import("node.zig");
const ruff = @import("ruff.zig");
const rustup = @import("rustup.zig");
const ty = @import("ty.zig");
const uv = @import("uv.zig");
const vscode = @import("vscode.zig");
const yt_dlp = @import("yt-dlp.zig");
const yt_dlp_script = @import("yt-dlp-script.zig");
const zellij_theme_tools = @import("zellij-theme-tools.zig");
const zig = @import("zig.zig");
const ziglint = @import("ziglint.zig");
const zls = @import("zls.zig");

const m = bootstrap.manifest;

pub const tools = [_]m.Tool{
    chezmoi.tool,
    git.tool,
    uv.tool,
    zig.tool,
    rustup.tool,
    zls.tool,
    ziglint.tool,
    node.tool,
    bun.tool,
    vscode.tool,
    yt_dlp.tool,
    yt_dlp_script.tool,
    ruff.tool,
    ty.tool,
    gh_hide_comment.tool,
    zellij_theme_tools.tool,
    lenovo_con_mode.tool,
};

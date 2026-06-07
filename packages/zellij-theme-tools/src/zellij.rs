use std::{
    io::{IsTerminal, Write},
    sync::Mutex,
};

use crate::{Colors, run_silent};

pub fn set_pane_color(colors: Colors) {
    run_silent(
        "zellij",
        &[
            "action",
            "set-pane-color",
            "--fg",
            colors.fg,
            "--bg",
            colors.bg,
        ],
    );
}

pub fn write_pane_color_override(colors: Colors) {
    static STDOUT_LOCK: Mutex<()> = Mutex::new(());
    let Ok(_guard) = STDOUT_LOCK.lock() else {
        return;
    };

    let mut stdout = std::io::stdout().lock();
    if !stdout.is_terminal() {
        return;
    }

    let _ = write!(
        stdout,
        "\x1b]10;{}\x1b\\\x1b]11;{}\x1b\\",
        colors.fg, colors.bg
    );
    let _ = stdout.flush();
}

pub fn reset_pane_color() {
    run_silent("zellij", &["action", "set-pane-color", "--reset"]);
}

pub fn send_focus_gained(pane_id: &str) {
    run_silent(
        "zellij",
        &["action", "write", "--pane-id", pane_id, "27", "91", "73"],
    );
}

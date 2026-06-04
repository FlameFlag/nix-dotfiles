use crate::{
    detect_system_theme, detect_terminal_theme, reset_pane_color, send_focus_gained,
    write_pane_color_override,
};

pub(super) struct StartupPaneColor {
    enabled: bool,
}

impl StartupPaneColor {
    pub(super) fn start() -> Self {
        let enabled = std::env::var_os("ZELLIJ").is_some() && which::which("zellij").is_ok();
        if enabled {
            let theme = detect_terminal_theme().unwrap_or_else(detect_system_theme);
            write_pane_color_override(theme.colors);
            schedule_reset();
        }
        Self { enabled }
    }
}

impl Drop for StartupPaneColor {
    fn drop(&mut self) {
        if self.enabled {
            reset_pane_color();
        }
    }
}

fn schedule_reset() {
    let pane_id = std::env::var("ZELLIJ_PANE_ID").ok();
    let _ = std::thread::Builder::new()
        .name("zellij-pane-color-reset".to_owned())
        .spawn(move || {
            wait_for_zellij_theme_to_settle(pane_id.as_deref());
            reset_pane_color();
        });
}

fn wait_for_zellij_theme_to_settle(pane_id: Option<&str>) {
    if let Some(pane_id) = pane_id {
        for _ in 0..3 {
            std::thread::sleep(std::time::Duration::from_millis(500));
            send_focus_gained(pane_id);
        }
        std::thread::sleep(std::time::Duration::from_millis(1500));
    } else {
        std::thread::sleep(std::time::Duration::from_secs(3));
    }
}

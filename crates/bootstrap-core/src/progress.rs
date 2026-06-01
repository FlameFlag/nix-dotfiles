use std::time::Duration;

use indicatif::{ProgressBar, ProgressStyle};

pub(crate) struct Spinner {
    bar: ProgressBar,
    finished: bool,
}

impl Spinner {
    pub(crate) fn new(message: impl Into<String>) -> Self {
        let bar = ProgressBar::new_spinner();
        bar.enable_steady_tick(Duration::from_millis(120));
        if let Ok(style) = ProgressStyle::with_template("{spinner:.cyan} {wide_msg}") {
            bar.set_style(style.tick_chars("/|\\- "));
        }
        bar.set_message(message.into());
        Self {
            bar,
            finished: false,
        }
    }

    pub(crate) fn set_message(&self, message: impl Into<String>) {
        self.bar.set_message(message.into());
    }

    pub(crate) fn finish_and_clear(mut self) {
        self.bar.finish_and_clear();
        self.finished = true;
    }
}

impl Drop for Spinner {
    fn drop(&mut self) {
        if !self.finished {
            self.bar.finish_and_clear();
        }
    }
}

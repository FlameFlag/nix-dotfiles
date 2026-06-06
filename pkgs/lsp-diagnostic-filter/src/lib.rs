#![cfg_attr(test, allow(clippy::expect_used, clippy::panic, clippy::unwrap_used))]

use std::io::{self, Cursor, Write};

use lsp_server::{Message, Notification};
use lsp_types::notification::Notification as _;
use lsp_types::{PublishDiagnosticsParams, notification::PublishDiagnostics};

const TEMPLATE_DIRECTORY_PATTERN: &str = "/.chezmoitemplates/";

#[derive(Debug, Default)]
pub struct LspFilter {
    buffer: Vec<u8>,
}

impl LspFilter {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Accepts bytes from an LSP stream and writes complete, transformed frames.
    ///
    /// # Errors
    ///
    /// Returns an error if writing the transformed output fails.
    pub fn accept<W: Write>(&mut self, chunk: &[u8], writer: &mut W) -> io::Result<()> {
        self.buffer.extend_from_slice(chunk);

        loop {
            if !has_complete_header(&self.buffer) {
                return Ok(());
            }
            let mut cursor = Cursor::new(self.buffer.as_slice());
            match Message::read(&mut cursor) {
                Ok(Some(message)) => {
                    let consumed = usize::try_from(cursor.position()).map_err(io::Error::other)?;
                    self.buffer.drain(..consumed);
                    transform_message(message).write(writer)?;
                }
                Ok(None) => return Ok(()),
                Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => return Ok(()),
                Err(error) => {
                    let consumed = usize::try_from(cursor.position()).map_err(io::Error::other)?;
                    if consumed == 0 {
                        return Err(error);
                    }
                    writer.write_all(&self.buffer[..consumed])?;
                    self.buffer.drain(..consumed);
                }
            }
        }
    }
}

fn transform_message(message: Message) -> Message {
    match message {
        Message::Notification(notification)
            if notification.method == PublishDiagnostics::METHOD =>
        {
            Message::Notification(transform_publish_diagnostics(notification))
        }
        _ => message,
    }
}

fn transform_publish_diagnostics(mut notification: Notification) -> Notification {
    let Ok(mut params) =
        serde_json::from_value::<PublishDiagnosticsParams>(notification.params.clone())
    else {
        return notification;
    };

    if is_template_uri(params.uri.as_str()) {
        params.diagnostics.clear();
    }
    notification.params = serde_json::to_value(params).unwrap_or(serde_json::Value::Null);
    notification
}

fn is_template_uri(uri: &str) -> bool {
    uri.ends_with(".tmpl") || uri.contains(TEMPLATE_DIRECTORY_PATTERN)
}

fn has_complete_header(buffer: &[u8]) -> bool {
    buffer
        .windows(b"\r\n\r\n".len())
        .any(|window| window == b"\r\n\r\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clears_template_diagnostics() -> io::Result<()> {
        let body = diagnostic_body("file:///repo/config.nu.tmpl");
        let output = run_filter(frame(&body).as_bytes())?;
        let output = String::from_utf8_lossy(&output);

        assert!(output.contains(r#""diagnostics":[]"#));
        assert!(output.contains(r#""uri":"file:///repo/config.nu.tmpl""#));
        Ok(())
    }

    #[test]
    fn keeps_regular_diagnostics() -> io::Result<()> {
        let body = diagnostic_body("file:///repo/config.nu");
        let output = run_filter(frame(&body).as_bytes())?;
        let output = String::from_utf8_lossy(&output);

        assert!(output.contains(r#""message":"bad""#));
        Ok(())
    }

    #[test]
    fn handles_split_frames() -> io::Result<()> {
        let body = diagnostic_body("file:///repo/.chezmoitemplates/x.nu");
        let frame = frame(&body);
        let (first, second) = frame.as_bytes().split_at(10);

        let mut filter = LspFilter::new();
        let mut output = Vec::new();
        filter.accept(first, &mut output)?;
        assert!(output.is_empty());
        filter.accept(second, &mut output)?;

        let output = String::from_utf8_lossy(&output);
        assert!(output.contains(r#""diagnostics":[]"#));
        Ok(())
    }

    #[test]
    fn passes_invalid_json_through_as_lsp_frame() -> io::Result<()> {
        let output = run_filter(frame("not json").as_bytes())?;
        let output = String::from_utf8_lossy(&output);

        assert_eq!(output, frame("not json"));
        Ok(())
    }

    fn run_filter(input: &[u8]) -> io::Result<Vec<u8>> {
        let mut filter = LspFilter::new();
        let mut output = Vec::new();
        filter.accept(input, &mut output)?;
        Ok(output)
    }

    fn frame(body: &str) -> String {
        format!("Content-Length: {}\r\n\r\n{body}", body.len())
    }

    fn diagnostic_body(uri: &str) -> String {
        format!(
            r#"{{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{{"uri":"{uri}","diagnostics":[{{"range":{{"start":{{"line":0,"character":0}},"end":{{"line":0,"character":1}}}},"message":"bad"}}]}}}}"#
        )
    }
}

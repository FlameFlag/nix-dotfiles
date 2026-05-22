use std::io::{self, Write};

const HEADER_SEPARATOR: &[u8] = b"\r\n\r\n";
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

        while let Some(header_end) = find_subsequence(&self.buffer, HEADER_SEPARATOR) {
            let header = String::from_utf8_lossy(&self.buffer[..header_end]);
            let Some(length) = content_length(&header) else {
                writer.write_all(&self.buffer)?;
                self.buffer.clear();
                return Ok(());
            };

            let body_start = header_end + HEADER_SEPARATOR.len();
            let message_end = body_start + length;
            if self.buffer.len() < message_end {
                return Ok(());
            }

            let body = String::from_utf8_lossy(&self.buffer[body_start..message_end]).into_owned();
            self.buffer.drain(..message_end);
            write_lsp_message(transform_body(&body).as_bytes(), writer)?;
        }

        Ok(())
    }
}

fn transform_body(body: &str) -> String {
    match serde_json::from_str::<serde_json::Value>(body) {
        Ok(serde_json::Value::Object(mut message)) => {
            if should_clear_diagnostics(&message) {
                clear_diagnostics(&mut message);
            }
            serde_json::to_string(&message).unwrap_or_else(|_| body.to_owned())
        }
        _ => body.to_owned(),
    }
}

fn should_clear_diagnostics(message: &serde_json::Map<String, serde_json::Value>) -> bool {
    if message.get("method").and_then(serde_json::Value::as_str)
        != Some("textDocument/publishDiagnostics")
    {
        return false;
    }

    message
        .get("params")
        .and_then(serde_json::Value::as_object)
        .and_then(|params| params.get("uri"))
        .and_then(serde_json::Value::as_str)
        .is_some_and(is_template_uri)
}

fn clear_diagnostics(message: &mut serde_json::Map<String, serde_json::Value>) {
    let Some(serde_json::Value::Object(params)) = message.get_mut("params") else {
        return;
    };

    params.insert(
        "diagnostics".to_owned(),
        serde_json::Value::Array(Vec::new()),
    );
}

fn is_template_uri(uri: &str) -> bool {
    uri.ends_with(".tmpl") || uri.contains(TEMPLATE_DIRECTORY_PATTERN)
}

fn content_length(header: &str) -> Option<usize> {
    header.lines().find_map(|line| {
        let (name, value) = line.split_once(':')?;
        name.eq_ignore_ascii_case("content-length")
            .then(|| value.trim().parse().ok())
            .flatten()
    })
}

fn find_subsequence(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

fn write_lsp_message<W: Write>(body: &[u8], writer: &mut W) -> io::Result<()> {
    write!(writer, "Content-Length: {}\r\n\r\n", body.len())?;
    writer.write_all(body)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clears_template_diagnostics() -> io::Result<()> {
        let body = r#"{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file:///repo/config.nu.tmpl","diagnostics":[{"message":"bad"}]}}"#;
        let output = run_filter(frame(body).as_bytes())?;
        let output = String::from_utf8_lossy(&output);

        assert!(output.contains(r#""diagnostics":[]"#));
        assert!(output.contains(r#""uri":"file:///repo/config.nu.tmpl""#));
        Ok(())
    }

    #[test]
    fn keeps_regular_diagnostics() -> io::Result<()> {
        let body = r#"{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file:///repo/config.nu","diagnostics":[{"message":"bad"}]}}"#;
        let output = run_filter(frame(body).as_bytes())?;
        let output = String::from_utf8_lossy(&output);

        assert!(output.contains(r#""diagnostics":[{"message":"bad"}]"#));
        Ok(())
    }

    #[test]
    fn handles_split_frames() -> io::Result<()> {
        let body = r#"{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file:///repo/.chezmoitemplates/x.nu","diagnostics":[{"message":"bad"}]}}"#;
        let frame = frame(body);
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
}

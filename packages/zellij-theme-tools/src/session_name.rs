#[must_use]
pub fn sanitize_session_name(raw: &str) -> String {
    let mut output = String::new();
    let mut pending_dash = false;
    for ch in raw.chars() {
        if ch.is_ascii_alphanumeric() || matches!(ch, '_' | '.' | '-') {
            if pending_dash && !output.is_empty() {
                output.push('-');
            }
            pending_dash = false;
            output.push(ch);
        } else {
            pending_dash = true;
        }
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_names_are_squeezed_and_trimmed() {
        assert_eq!(sanitize_session_name("repo"), "repo");
        assert_eq!(sanitize_session_name("  hello///there!! "), "hello-there");
        assert_eq!(sanitize_session_name("a_b.c-d"), "a_b.c-d");
    }
}

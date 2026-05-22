use std::collections::HashMap;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum TemplateError {
    #[error("unknown template variable {{{0}}}")]
    UnknownVariable(String),
    #[error("unterminated template variable")]
    Unterminated,
}

pub type Bindings<'a> = HashMap<&'a str, &'a str>;

/// Renders `{name}` placeholders using `bindings`.
///
/// # Errors
///
/// Returns an error if a placeholder is unterminated or references an unknown binding.
pub fn render(input: &str, bindings: &Bindings<'_>) -> Result<String, TemplateError> {
    let mut output = String::new();
    let mut rest = input;
    while let Some(open) = rest.find('{') {
        output.push_str(&rest[..open]);
        let after_open = &rest[open + 1..];
        let close = after_open.find('}').ok_or(TemplateError::Unterminated)?;
        let key = &after_open[..close];
        let value = bindings
            .get(key)
            .ok_or_else(|| TemplateError::UnknownVariable(key.to_owned()))?;
        output.push_str(value);
        rest = &after_open[close + 1..];
    }
    output.push_str(rest);
    Ok(output)
}

/// Renders placeholders in every string in `input`.
///
/// # Errors
///
/// Returns an error if rendering any individual string fails.
pub fn render_slice(
    input: &[String],
    bindings: &Bindings<'_>,
) -> Result<Vec<String>, TemplateError> {
    input.iter().map(|item| render(item, bindings)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_known_placeholders() -> Result<(), TemplateError> {
        let mut bindings = Bindings::new();
        bindings.insert("tool", "demo");
        bindings.insert("version", "1.0.0");
        assert_eq!(render("{tool}-{version}", &bindings)?, "demo-1.0.0");
        Ok(())
    }

    #[test]
    fn rejects_unknown_placeholders() {
        let bindings = Bindings::new();
        assert!(matches!(
            render("{missing}", &bindings),
            Err(TemplateError::UnknownVariable(name)) if name == "missing"
        ));
    }
}

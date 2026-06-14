use std::collections::BTreeMap;

use minijinja::{Environment, UndefinedBehavior};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum TemplateError {
    #[error(transparent)]
    Render(#[from] minijinja::Error),
}

pub type Bindings<'a> = BTreeMap<&'a str, &'a str>;

/// Renders MiniJinja placeholders using `bindings`.
///
/// # Errors
///
/// Returns an error if rendering fails or references an unknown binding.
pub fn render(input: &str, bindings: &Bindings<'_>) -> Result<String, TemplateError> {
    let mut env = Environment::new();
    env.set_undefined_behavior(UndefinedBehavior::Strict);
    env.render_str(input, bindings).map_err(Into::into)
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
        assert_eq!(render("{{ tool }}-{{ version }}", &bindings)?, "demo-1.0.0");
        Ok(())
    }

    #[test]
    fn rejects_unknown_placeholders() {
        let bindings = Bindings::new();
        assert!(render("{{ missing }}", &bindings).is_err());
    }
}

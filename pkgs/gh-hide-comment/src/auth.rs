use secrecy::SecretString;

use crate::error::{Error, Result};

pub fn token() -> Result<SecretString> {
    token_from_env().map_or_else(token_from_gh_cli, Ok)
}

fn token_from_env() -> Option<SecretString> {
    ["GH_TOKEN", "GITHUB_TOKEN"]
        .into_iter()
        .filter_map(|name| std::env::var(name).ok())
        .find_map(secret_from_value)
}

fn token_from_gh_cli() -> Result<SecretString> {
    let output = dotfiles_common::process::capture_with_env(
        &["gh".to_owned(), "auth".to_owned(), "token".to_owned()],
        std::iter::empty::<(String, String)>(),
    )
    .map_err(|err| Error::GhAuth(err.to_string()))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        return Err(if stderr.is_empty() {
            Error::MissingToken
        } else {
            Error::GhAuth(stderr)
        });
    }
    let token = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    if token.is_empty() {
        Err(Error::MissingToken)
    } else {
        Ok(SecretString::from(token))
    }
}

fn secret_from_value(value: String) -> Option<SecretString> {
    let trimmed = value.trim();
    (!trimmed.is_empty()).then(|| SecretString::from(trimmed.to_owned()))
}

#[cfg(test)]
mod tests {
    use secrecy::ExposeSecret;

    use super::*;

    #[test]
    fn secret_from_value_trims_non_empty_tokens() {
        let token = secret_from_value("  github-token\n".to_owned()).expect("token");

        assert_eq!(token.expose_secret(), "github-token");
    }

    #[test]
    fn secret_from_value_rejects_empty_tokens() {
        assert!(secret_from_value(" \n\t".to_owned()).is_none());
    }
}

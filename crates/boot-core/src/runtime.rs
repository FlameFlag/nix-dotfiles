pub fn skip_self_install() -> bool {
    env_flag("BOOTSTRAP_SKIP_SELF_INSTALL")
}

fn env_flag(name: &str) -> bool {
    std::env::var(name).is_ok_and(|value| flag_value_is_truthy(&value))
}

fn flag_value_is_truthy(value: &str) -> bool {
    matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "1" | "true" | "yes" | "on"
    )
}

#[cfg(test)]
mod tests {
    #[test]
    fn recognizes_truthy_flag_values() {
        assert!(super::flag_value_is_truthy("1"));
        assert!(super::flag_value_is_truthy("true"));
        assert!(super::flag_value_is_truthy(" yes "));
        assert!(super::flag_value_is_truthy("ON"));
        assert!(!super::flag_value_is_truthy("0"));
        assert!(!super::flag_value_is_truthy("false"));
    }
}

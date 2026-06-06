use schemars::{JsonSchema, Schema, SchemaGenerator, json_schema};
use serde::{Deserialize, Serialize, de};

#[cfg(target_os = "windows")]
use dotfiles_common::process;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum HostOs {
    Macos,
    Linux,
    Windows,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum HostArch {
    Aarch64,
    X86_64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Default)]
pub struct Predicate {
    pub os: Option<HostOs>,
    pub arch: Option<HostArch>,
    pub musl: Option<bool>,
}

impl JsonSchema for Predicate {
    fn inline_schema() -> bool {
        true
    }

    fn schema_name() -> std::borrow::Cow<'static, str> {
        "Predicate".into()
    }

    fn json_schema(_generator: &mut SchemaGenerator) -> Schema {
        json_schema!({
            "oneOf": [
                {
                    "type": "string",
                    "examples": ["macos-aarch64", "linux-x86_64", "windows"]
                },
                {
                    "type": "object",
                    "properties": {
                        "os": { "enum": ["macos", "linux", "windows"] },
                        "arch": { "enum": ["aarch64", "x86_64"] },
                        "musl": { "type": "boolean" }
                    },
                    "additionalProperties": false
                }
            ]
        })
    }
}

impl<'de> Deserialize<'de> for Predicate {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum PredicateRepr {
            Short(String),
            Full {
                os: Option<HostOs>,
                arch: Option<HostArch>,
                musl: Option<bool>,
            },
        }

        match PredicateRepr::deserialize(deserializer)? {
            PredicateRepr::Short(value) => parse_predicate(&value).map_err(de::Error::custom),
            PredicateRepr::Full { os, arch, musl } => Ok(Self { os, arch, musl }),
        }
    }
}

fn parse_predicate(value: &str) -> Result<Predicate, String> {
    let (os, arch) = value
        .split_once('-')
        .map_or((value, None), |(os, arch)| (os, Some(arch)));
    let os = match os {
        "macos" | "darwin" => HostOs::Macos,
        "linux" => HostOs::Linux,
        "windows" | "win32" => HostOs::Windows,
        _ => return Err(format!("unknown host OS predicate {os:?}")),
    };
    let arch = match arch {
        None => None,
        Some("aarch64" | "arm64") => Some(HostArch::Aarch64),
        Some("x86_64" | "amd64" | "x64") => Some(HostArch::X86_64),
        Some(arch) => return Err(format!("unknown host architecture predicate {arch:?}")),
    };
    Ok(Predicate {
        os: Some(os),
        arch,
        musl: None,
    })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Host {
    pub os: HostOs,
    pub arch: HostArch,
}

impl Host {
    #[inline]
    #[must_use]
    pub const fn current() -> Self {
        Self {
            os: match (cfg!(target_os = "macos"), cfg!(target_os = "windows")) {
                (true, _) => HostOs::Macos,
                (_, true) => HostOs::Windows,
                _ => HostOs::Linux,
            },
            arch: if cfg!(target_arch = "aarch64") {
                HostArch::Aarch64
            } else {
                HostArch::X86_64
            },
        }
    }

    #[inline]
    #[must_use]
    pub fn matches(self, predicate: Predicate) -> bool {
        predicate.os.is_none_or(|os| os == self.os)
            && predicate.arch.is_none_or(|arch| arch == self.arch)
            && predicate.musl.is_none_or(|musl| musl == is_musl_linux())
    }

    #[inline]
    #[must_use]
    pub const fn rustup_triple(self) -> Option<&'static str> {
        match (self.os, self.arch) {
            (HostOs::Macos, HostArch::Aarch64) => Some("aarch64-apple-darwin"),
            (HostOs::Macos, HostArch::X86_64) => None,
            (HostOs::Linux, HostArch::Aarch64) if cfg!(target_env = "musl") => {
                Some("aarch64-unknown-linux-musl")
            }
            (HostOs::Linux, HostArch::Aarch64) => Some("aarch64-unknown-linux-gnu"),
            (HostOs::Linux, HostArch::X86_64) if cfg!(target_env = "musl") => {
                Some("x86_64-unknown-linux-musl")
            }
            (HostOs::Linux, HostArch::X86_64) => Some("x86_64-unknown-linux-gnu"),
            (HostOs::Windows, HostArch::Aarch64) => Some("aarch64-pc-windows-msvc"),
            (HostOs::Windows, HostArch::X86_64) => Some("x86_64-pc-windows-msvc"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum HostRequirement {
    LenovoLaptop,
    NonMusl,
}

#[inline]
#[must_use]
#[cfg_attr(
    not(any(target_os = "linux", target_os = "windows")),
    allow(clippy::missing_const_for_fn)
)]
pub fn meets_requirement(requirement: HostRequirement) -> bool {
    match requirement {
        HostRequirement::LenovoLaptop => is_lenovo_laptop(),
        HostRequirement::NonMusl => !is_musl_linux(),
    }
}

#[inline]
#[must_use]
fn is_musl_linux() -> bool {
    cfg!(target_os = "linux") && cfg!(target_env = "musl")
}

#[cfg_attr(
    not(any(target_os = "linux", target_os = "windows")),
    allow(clippy::missing_const_for_fn)
)]
fn is_lenovo_laptop() -> bool {
    #[cfg(target_os = "linux")]
    {
        let vendor = fs_err::read_to_string("/sys/class/dmi/id/sys_vendor").unwrap_or_default();
        let chassis = fs_err::read_to_string("/sys/class/dmi/id/chassis_type").unwrap_or_default();
        let is_lenovo = vendor.to_ascii_lowercase().contains("lenovo");
        let chassis = chassis.trim();
        is_lenovo && matches!(chassis, "8" | "9" | "10" | "14")
    }
    #[cfg(target_os = "windows")]
    {
        let command = [
            "wmic".to_owned(),
            "computersystem".to_owned(),
            "get".to_owned(),
            "manufacturer,model".to_owned(),
        ];
        let Ok(output) = process::capture_with_env(
            &command,
            std::iter::empty::<(std::ffi::OsString, std::ffi::OsString)>(),
        ) else {
            return false;
        };
        if !output.status.success() {
            return false;
        }
        let text = String::from_utf8_lossy(&output.stdout).to_ascii_lowercase();
        text.contains("lenovo") || text.contains("legion")
    }
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn predicates_require_all_supplied_facts() {
        let host = Host {
            os: HostOs::Linux,
            arch: HostArch::X86_64,
        };
        assert!(host.matches(Predicate {
            os: Some(HostOs::Linux),
            arch: None,
            musl: None
        }));
        assert!(host.matches(Predicate {
            os: Some(HostOs::Linux),
            arch: Some(HostArch::X86_64),
            musl: None
        }));
        assert!(!host.matches(Predicate {
            os: Some(HostOs::Macos),
            arch: None,
            musl: None
        }));
        assert!(!host.matches(Predicate {
            os: Some(HostOs::Linux),
            arch: Some(HostArch::Aarch64),
            musl: None
        }));
    }

    #[test]
    fn predicates_can_require_linux_abi() {
        let host = Host {
            os: HostOs::Linux,
            arch: HostArch::X86_64,
        };
        assert_eq!(
            host.matches(Predicate {
                os: Some(HostOs::Linux),
                arch: Some(HostArch::X86_64),
                musl: Some(true)
            }),
            cfg!(target_env = "musl")
        );
        assert_eq!(
            host.matches(Predicate {
                os: Some(HostOs::Linux),
                arch: Some(HostArch::X86_64),
                musl: Some(false)
            }),
            !cfg!(target_env = "musl")
        );
    }

    #[test]
    fn rustup_triples_follow_current_linux_abi() {
        let (x86_64, aarch64) = if cfg!(target_env = "musl") {
            ("x86_64-unknown-linux-musl", "aarch64-unknown-linux-musl")
        } else {
            ("x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu")
        };
        assert_eq!(
            Host {
                os: HostOs::Linux,
                arch: HostArch::X86_64
            }
            .rustup_triple(),
            Some(x86_64)
        );
        assert_eq!(
            Host {
                os: HostOs::Linux,
                arch: HostArch::Aarch64
            }
            .rustup_triple(),
            Some(aarch64)
        );
    }

    #[test]
    fn predicates_accept_short_platform_strings() {
        let predicate: Predicate = toml::from_str(r#"when = "macos-aarch64""#)
            .map(|value: toml::Table| value["when"].clone().try_into().expect("predicate"))
            .expect("parse toml");

        assert_eq!(
            predicate,
            Predicate {
                os: Some(HostOs::Macos),
                arch: Some(HostArch::Aarch64),
                musl: None,
            }
        );
    }
}

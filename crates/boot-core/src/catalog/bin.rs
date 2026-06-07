use schemars::{JsonSchema, Schema, SchemaGenerator, json_schema};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct Bin {
    /// Executable name as it should appear on `PATH`.
    #[garde(length(min = 1))]
    pub name: String,
    /// Command used to verify that the executable starts successfully.
    #[garde(length(min = 1))]
    pub version_argv: Vec<String>,
}

impl JsonSchema for Bin {
    fn inline_schema() -> bool {
        true
    }

    fn schema_name() -> std::borrow::Cow<'static, str> {
        "Bin".into()
    }

    fn json_schema(_generator: &mut SchemaGenerator) -> Schema {
        json_schema!({
            "oneOf": [
                { "type": "string" },
                {
                    "type": "object",
                    "required": ["name"],
                    "properties": {
                        "name": { "type": "string" },
                        "version_argv": {
                            "type": "array",
                            "items": { "type": "string" }
                        }
                    },
                    "additionalProperties": false
                }
            ]
        })
    }
}

impl Bin {
    pub(super) fn for_name(name: &str) -> Self {
        Self {
            name: name.to_owned(),
            version_argv: default_version_argv(name),
        }
    }
}

impl<'de> Deserialize<'de> for Bin {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum BinRepr {
            Name(String),
            Full {
                name: String,
                #[serde(default)]
                version_argv: Vec<String>,
            },
        }

        match BinRepr::deserialize(deserializer)? {
            BinRepr::Name(name) => Ok(Bin::for_name(&name)),
            BinRepr::Full { name, version_argv } => Ok(Bin {
                version_argv: if version_argv.is_empty() {
                    default_version_argv(&name)
                } else {
                    version_argv
                },
                name,
            }),
        }
    }
}

fn default_version_argv(name: &str) -> Vec<String> {
    vec![name.to_owned(), "--version".to_owned()]
}

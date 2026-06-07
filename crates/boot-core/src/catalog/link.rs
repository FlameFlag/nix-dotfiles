use schemars::{JsonSchema, Schema, SchemaGenerator, json_schema};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct Link {
    /// Link name to create in the destination directory.
    #[garde(length(min = 1))]
    pub name: String,
    /// Relative path under the install root.
    pub path: String,
    /// Environment variables to export from a generated wrapper before execing
    /// the linked binary.
    #[serde(default)]
    #[garde(dive)]
    pub env: Vec<EnvVar>,
}

impl JsonSchema for Link {
    fn inline_schema() -> bool {
        true
    }

    fn schema_name() -> std::borrow::Cow<'static, str> {
        "Link".into()
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
                        "path": { "type": "string" },
                        "env": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "required": ["name", "value"],
                                "properties": {
                                    "name": { "type": "string" },
                                    "value": { "type": "string" }
                                },
                                "additionalProperties": false
                            }
                        }
                    },
                    "additionalProperties": false
                }
            ]
        })
    }
}

impl<'de> Deserialize<'de> for Link {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum LinkRepr {
            Name(String),
            Full {
                name: String,
                path: Option<String>,
                #[serde(default)]
                env: Vec<EnvVar>,
            },
        }

        match LinkRepr::deserialize(deserializer)? {
            LinkRepr::Name(name) => Ok(Self {
                path: name.clone(),
                name,
                env: Vec::new(),
            }),
            LinkRepr::Full { name, path, env } => Ok(Self {
                path: path.unwrap_or_else(|| name.clone()),
                name,
                env,
            }),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct EnvVar {
    #[garde(length(min = 1))]
    pub name: String,
    pub value: String,
}

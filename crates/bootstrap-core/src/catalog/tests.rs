use super::*;

#[test]
fn validates_unique_tool_and_bin_names() -> Result<(), CatalogError> {
    let catalog = Catalog {
        tools: vec![Tool {
            name: "demo".into(),
            bins: vec![Bin {
                name: "demo".into(),
                version_argv: vec!["demo".into(), "--version".into()],
            }],
            platforms: vec![],
            requires: vec![],
            phase: None,
            action: Action::Required,
        }],
    };
    catalog.validate()
}

#[test]
fn rejects_actions_that_use_managed_bins_before_their_phase() {
    let catalog = Catalog {
        tools: vec![
            Tool {
                name: "git".into(),
                bins: vec![Bin {
                    name: "git".into(),
                    version_argv: vec!["git".into(), "--version".into()],
                }],
                platforms: vec![],
                requires: vec![],
                phase: None,
                action: Action::Archive(ArchiveAction {
                    source: None,
                    platforms: vec![ArchivePlatform {
                        when: Predicate::default(),
                        platform: "test".into(),
                        source: None,
                        kind: ArchiveKind::TarGz,
                        strip_components: 0,
                        links: vec![Link {
                            name: "git".into(),
                            path: "bin/git".into(),
                            env: Vec::new(),
                        }],
                        app_links: vec![],
                    }],
                }),
            },
            Tool {
                name: "uses-git-too-early".into(),
                bins: vec![Bin {
                    name: "uses-git-too-early".into(),
                    version_argv: vec!["uses-git-too-early".into(), "--version".into()],
                }],
                platforms: vec![],
                requires: vec![],
                phase: None,
                action: Action::Toolchain(Box::new(ToolchainAction {
                    manager_bin: "demo".into(),
                    name: "stable".into(),
                    name_env: None,
                    bin_dir: ToolchainBinDir {
                        env_var: None,
                        home_relative: ".demo/bin".into(),
                    },
                    components: vec!["demo".into()],
                    install: ToolchainInstall {
                        platforms: vec![DownloadCommand {
                            when: Predicate::default(),
                            url: "https://example.invalid/demo".into(),
                            file: "demo".into(),
                            argv: vec!["git".into(), "clone".into()],
                        }],
                    },
                    update_argv: vec!["demo".into(), "update".into()],
                    active_argv: vec!["demo".into(), "active".into()],
                    default_argv: vec!["demo".into(), "default".into()],
                    component_argv: vec!["--component".into(), "{component}".into()],
                })),
            },
        ],
    };

    let result = catalog.validate();
    assert!(matches!(result, Err(CatalogError::Invalid(_))));
    let message = match result {
        Err(CatalogError::Invalid(message)) => message,
        _ => String::new(),
    };
    assert!(message.contains("bootstrapped in Archives"));
}

#[test]
fn repository_catalog_loads() -> Result<(), CatalogError> {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("bootstrap")
        .join("tools.toml");
    let catalog = Catalog::load(path)?;
    assert!(catalog.tools.iter().any(|tool| tool.name == "uv"));
    assert!(catalog.tools.iter().any(|tool| tool.name == "rustup"));
    Ok(())
}

use std::collections::{HashMap, HashSet};

use camino::Utf8Path;

use super::{Action, Catalog, CatalogError, Phase, Source, Tool};

pub fn validate_catalog(catalog: &Catalog) -> Result<(), CatalogError> {
    garde::Validate::validate(catalog)
        .map_err(|err| CatalogError::Invalid(format!("validation failed:\n{err}")))?;
    let mut seen_tools = HashSet::new();
    let mut seen_bins = HashSet::new();
    let mut managed_bins = HashMap::new();
    for (tool_index, tool) in catalog.tools.iter().enumerate() {
        validate_tool(
            tool_index,
            tool,
            &mut seen_tools,
            &mut seen_bins,
            &mut managed_bins,
        )?;
        validate_action_paths(tool_index, &tool.action)?;
        validate_action_shape(tool_index, &tool.action)?;
    }
    validate_action_dependencies(&catalog.tools, &managed_bins)?;
    Ok(())
}

fn validate_tool<'a>(
    tool_index: usize,
    tool: &'a Tool,
    seen_tools: &mut HashSet<&'a str>,
    seen_bins: &mut HashSet<&'a str>,
    managed_bins: &mut HashMap<String, (usize, Phase, &'a str)>,
) -> Result<(), CatalogError> {
    if !seen_tools.insert(tool.name.as_str()) {
        return Err(CatalogError::Invalid(format!(
            "tools[{tool_index}].name: duplicate tool name"
        )));
    }
    for (bin_index, bin) in tool.bins.iter().enumerate() {
        if !seen_bins.insert(bin.name.as_str()) {
            return Err(CatalogError::Invalid(format!(
                "tools[{tool_index}].bins[{bin_index}].name: duplicate bin name"
            )));
        }
        for key in executable_keys(&bin.name) {
            managed_bins
                .entry(key)
                .or_insert_with(|| (tool_index, tool.phase(), bin.name.as_str()));
        }
    }
    Ok(())
}

fn validate_action_shape(tool_index: usize, action: &Action) -> Result<(), CatalogError> {
    match action {
        Action::Archive(action) if action.platforms.is_empty() => Err(CatalogError::Invalid(
            format!("tools[{tool_index}].action.platforms: must not be empty"),
        )),
        Action::Archive(action) => {
            for (platform_index, platform) in action.platforms.iter().enumerate() {
                if action.platform_kind(platform).is_none() {
                    return Err(CatalogError::Invalid(format!(
                        "tools[{tool_index}].action.platforms[{platform_index}].kind: must be set or inferable from platform"
                    )));
                }
                if action.platform_links(platform).is_empty() {
                    return Err(CatalogError::Invalid(format!(
                        "tools[{tool_index}].action.platforms[{platform_index}].links: must not be empty"
                    )));
                }
            }
            Ok(())
        }
        Action::File(action) if action.file.is_empty() => Err(CatalogError::Invalid(format!(
            "tools[{tool_index}].action.file: must not be empty"
        ))),
        Action::File(action) if action.links.is_empty() => Err(CatalogError::Invalid(format!(
            "tools[{tool_index}].action.links: must not be empty"
        ))),
        Action::Build(action) if action.path.is_empty() => Err(CatalogError::Invalid(format!(
            "tools[{tool_index}].action.path: must not be empty"
        ))),
        Action::SourceBuild(action) if action.platforms.is_empty() => Err(CatalogError::Invalid(
            format!("tools[{tool_index}].action.platforms: must not be empty"),
        )),
        Action::SourceBuild(action) => {
            for (platform_index, platform) in action.platforms.iter().enumerate() {
                if action.platform_kind(platform).is_none() {
                    return Err(CatalogError::Invalid(format!(
                        "tools[{tool_index}].action.platforms[{platform_index}].kind: must be set or inferable from archive_file/url"
                    )));
                }
                if action.platform_links(platform).is_empty() {
                    return Err(CatalogError::Invalid(format!(
                        "tools[{tool_index}].action.platforms[{platform_index}].links: must not be empty"
                    )));
                }
            }
            Ok(())
        }
        Action::Toolchain(action) if action.components.is_empty() => Err(CatalogError::Invalid(
            format!("tools[{tool_index}].action.components: must not be empty"),
        )),
        Action::Toolchain(action) if action.install.platforms.is_empty() => {
            Err(CatalogError::Invalid(format!(
                "tools[{tool_index}].action.install.platforms: must not be empty"
            )))
        }
        Action::Toolchain(action) => {
            for (platform_index, command) in action.install.platforms.iter().enumerate() {
                if action.install.platform_file(command).is_none() {
                    return Err(CatalogError::Invalid(format!(
                        "tools[{tool_index}].action.install.platforms[{platform_index}].file: must be set or inherited"
                    )));
                }
                if action.install.platform_argv(command).is_none() {
                    return Err(CatalogError::Invalid(format!(
                        "tools[{tool_index}].action.install.platforms[{platform_index}].argv: must be set or inherited"
                    )));
                }
            }
            Ok(())
        }
        _ => Ok(()),
    }
}

fn validate_action_dependencies(
    tools: &[Tool],
    managed_bins: &HashMap<String, (usize, Phase, &str)>,
) -> Result<(), CatalogError> {
    for (tool_index, tool) in tools.iter().enumerate() {
        let phase = tool.phase();
        for (program, label) in action_programs(tool_index, &tool.action) {
            let Some(key) = executable_key(&program) else {
                continue;
            };
            let Some((provider_index, provider_phase, provider_bin)) = managed_bins.get(&key)
            else {
                continue;
            };
            // Commands may depend on binaries produced by the same tool or by
            // an earlier phase. Same-phase cross-tool dependencies are rejected
            // because catalog order inside a phase is intentionally not a dependency graph.
            if *provider_index == tool_index || *provider_phase < phase {
                continue;
            }
            return Err(CatalogError::Invalid(format!(
                "{label}: invokes {program:?}, but {provider_bin:?} is bootstrapped in {provider_phase:?}; move the provider to an earlier phase or this action to a later phase"
            )));
        }
    }
    Ok(())
}

fn action_programs(tool_index: usize, action: &Action) -> Vec<(String, String)> {
    let mut programs = Vec::new();
    match action {
        Action::Archive(action) => {
            if let Some(source) = &action.source {
                collect_source_program(
                    &mut programs,
                    source,
                    format!("tools[{tool_index}].action.source.argv[0]"),
                );
            }
            for (platform_index, platform) in action.platforms.iter().enumerate() {
                if let Some(source) = &platform.source {
                    collect_source_program(
                        &mut programs,
                        source,
                        format!(
                            "tools[{tool_index}].action.platforms[{platform_index}].source.argv[0]"
                        ),
                    );
                }
            }
        }
        Action::File(action) => collect_source_program(
            &mut programs,
            &action.source,
            format!("tools[{tool_index}].action.source.argv[0]"),
        ),
        Action::Package(action) => collect_argv_program(
            &mut programs,
            &action.install_argv,
            format!("tools[{tool_index}].action.install_argv[0]"),
        ),
        Action::Build(action) => collect_argv_program(
            &mut programs,
            &action.argv,
            format!("tools[{tool_index}].action.argv[0]"),
        ),
        Action::SourceBuild(action) => {
            for (platform_index, platform) in action.platforms.iter().enumerate() {
                let (argv, label) = if let Some(argv) = platform.argv.as_deref() {
                    (
                        argv,
                        format!("tools[{tool_index}].action.platforms[{platform_index}].argv[0]"),
                    )
                } else {
                    (
                        action.argv.as_slice(),
                        format!("tools[{tool_index}].action.argv[0]"),
                    )
                };
                collect_argv_program(&mut programs, argv, label);
            }
        }
        Action::Toolchain(action) => {
            for (platform_index, command) in action.install.platforms.iter().enumerate() {
                let (argv, label) = if command.argv.is_empty() {
                    (
                        action.install.argv.as_slice(),
                        format!("tools[{tool_index}].action.install.argv[0]"),
                    )
                } else {
                    (
                        command.argv.as_slice(),
                        format!(
                            "tools[{tool_index}].action.install.platforms[{platform_index}].argv[0]"
                        ),
                    )
                };
                collect_argv_program(&mut programs, argv, label);
            }
            collect_argv_program(
                &mut programs,
                &action.update_argv,
                format!("tools[{tool_index}].action.update_argv[0]"),
            );
            collect_argv_program(
                &mut programs,
                &action.active_argv,
                format!("tools[{tool_index}].action.active_argv[0]"),
            );
            collect_argv_program(
                &mut programs,
                &action.default_argv,
                format!("tools[{tool_index}].action.default_argv[0]"),
            );
        }
        Action::Required => {}
    }
    programs
}

fn collect_source_program(programs: &mut Vec<(String, String)>, source: &Source, label: String) {
    if let Source::Command { argv, .. } = source {
        collect_argv_program(programs, argv, label);
    }
}

fn collect_argv_program(programs: &mut Vec<(String, String)>, argv: &[String], label: String) {
    if let Some(program) = argv.first() {
        programs.push((program.clone(), label));
    }
}

fn executable_keys(bin: &str) -> Vec<String> {
    let Some(key) = executable_key(bin) else {
        return Vec::new();
    };
    let mut keys = vec![key.clone()];
    // Catalogs usually name binaries without a Windows suffix, while commands
    // can invoke either `foo` or `foo.exe`/`foo.cmd`. Normalize both spellings
    // so phase validation catches cross-platform dependency mistakes.
    for extension in [".exe", ".cmd", ".bat", ".com"] {
        if let Some(stem) = key.strip_suffix(extension) {
            keys.push(stem.to_owned());
        }
    }
    keys
}

fn executable_key(program: &str) -> Option<String> {
    if program.is_empty() || program.contains('{') {
        return None;
    }
    let path = Utf8Path::new(program);
    let name = path.file_name().unwrap_or(program);
    if name.is_empty() || name.contains('{') {
        None
    } else {
        Some(name.to_ascii_lowercase())
    }
}

fn validate_action_paths(tool_index: usize, action: &Action) -> Result<(), CatalogError> {
    match action {
        Action::Archive(action) => {
            for (link_index, link) in action.links.iter().enumerate() {
                validate_relative_utf8_path(
                    &link.path,
                    &format!("tools[{tool_index}].action.links[{link_index}].path"),
                )?;
            }
            for (link_index, link) in action.app_links.iter().enumerate() {
                validate_relative_utf8_path(
                    &link.path,
                    &format!("tools[{tool_index}].action.app_links[{link_index}].path"),
                )?;
            }
            for (platform_index, platform) in action.platforms.iter().enumerate() {
                for (link_index, link) in platform.links.iter().enumerate() {
                    validate_relative_utf8_path(
                        &link.path,
                        &format!(
                            "tools[{tool_index}].action.platforms[{platform_index}].links[{link_index}].path"
                        ),
                    )?;
                }
                for (link_index, link) in platform.app_links.iter().enumerate() {
                    validate_relative_utf8_path(
                        &link.path,
                        &format!(
                            "tools[{tool_index}].action.platforms[{platform_index}].app_links[{link_index}].path"
                        ),
                    )?;
                }
            }
        }
        Action::Build(action) => {
            validate_relative_utf8_path(&action.path, &format!("tools[{tool_index}].action.path"))?;
            for (link_index, link) in action.links.iter().enumerate() {
                validate_relative_utf8_path(
                    &link.path,
                    &format!("tools[{tool_index}].action.links[{link_index}].path"),
                )?;
            }
        }
        Action::File(action) => {
            validate_relative_utf8_path(&action.file, &format!("tools[{tool_index}].action.file"))?;
            for (link_index, link) in action.links.iter().enumerate() {
                validate_relative_utf8_path(
                    &link.path,
                    &format!("tools[{tool_index}].action.links[{link_index}].path"),
                )?;
            }
        }
        Action::SourceBuild(action) => {
            for (link_index, link) in action.links.iter().enumerate() {
                validate_relative_utf8_path(
                    &link.path,
                    &format!("tools[{tool_index}].action.links[{link_index}].path"),
                )?;
            }
            for (platform_index, platform) in action.platforms.iter().enumerate() {
                for (link_index, link) in platform.links.iter().enumerate() {
                    validate_relative_utf8_path(
                        &link.path,
                        &format!(
                            "tools[{tool_index}].action.platforms[{platform_index}].links[{link_index}].path"
                        ),
                    )?;
                }
            }
        }
        Action::Toolchain(action) => validate_relative_utf8_path(
            &action.bin_dir.home_relative,
            &format!("tools[{tool_index}].action.bin_dir.home_relative"),
        )?,
        Action::Required | Action::Package(_) => {}
    }
    Ok(())
}

fn validate_relative_utf8_path(path: &str, label: &str) -> Result<(), CatalogError> {
    let path = Utf8Path::new(path);
    if path.is_absolute() {
        return Err(CatalogError::Invalid(format!("{label}: must be relative")));
    }
    // Link paths are later joined to an install root, so reject parent escapes
    // at catalog load time instead of relying on each installer path.
    if path.components().any(|component| {
        matches!(
            component,
            camino::Utf8Component::ParentDir | camino::Utf8Component::Prefix(_)
        )
    }) {
        return Err(CatalogError::Invalid(format!(
            "{label}: must stay under its install root"
        )));
    }
    Ok(())
}

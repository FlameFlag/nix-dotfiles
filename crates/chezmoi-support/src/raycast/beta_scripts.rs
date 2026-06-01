use std::path::Path;

use crate::command::{command_output, output_detail};
use crate::error::{Error, Result};
use dotfiles_common::process::argv;

const FRONTEND_OPEN_SETTINGS_BROKEN: &str =
    "openSettings:async e=>{Na({to:e.to,params:e.routeParams})}";
const FRONTEND_OPEN_SETTINGS_FIXED: &str =
    "openSettings:async e=>{Na({to:e.to,params:e.routeParams,search:e.search})}";
const FRONTEND_AUTH_STORE_USER: &str = ".authStore.peek().user";
const FRONTEND_AUTH_STORE_START: &str = "function sc(){let e=cn(`auth`);";
const FRONTEND_DEV_USER_FUNCTION: &str = "function __raycastLocalDevUser(t){let e=t??{id:`raycast-local-dev-user`,name:`Raycast Dev`,username:`raycast-local-dev`,handle:`raycast-local-dev`,email:`dev@localhost`,organizations:[]};return{...e,has_pro_features:!0,can_apply_for_free_trial:!1,subscription:{...e.subscription,id:e.subscription?.id??`raycast-local-pro`,status:e.subscription?.status??`active`}}}";
const FRONTEND_AUTH_LOGIN_RAW: &str = "let n=await m.ipc.backend.auth.getUser()";
const FRONTEND_AUTH_LOGIN_PATCHED: &str =
    "let n=__raycastLocalDevUser(await m.ipc.backend.auth.getUser())";
const FRONTEND_AUTH_UPDATE_RAW: &str =
    "update:async({set:t},n)=>{t(e=>({...e,...n})),e.send({window:window.identifier,data:n})}";
const FRONTEND_AUTH_UPDATE_PATCHED: &str = "update:async({set:t},n)=>{n.user!==void 0&&(n={...n,user:__raycastLocalDevUser(n.user)}),t(e=>({...e,...n})),e.send({window:window.identifier,data:n})}";
const FRONTEND_AUTH_APPLY_REMOTE_RAW: &str = "applyRemote:async({set:e},t)=>{e(e=>({...e,...t}))}";
const FRONTEND_AUTH_APPLY_REMOTE_PATCHED: &str = "applyRemote:async({set:e},t)=>{t.user!==void 0&&(t={...t,user:__raycastLocalDevUser(t.user)}),e(e=>({...e,...t}))}";
const BACKEND_DEV_USER_FUNCTION: &str = "function __raycastLocalDevUser(t){return t?{...t,has_pro_features:!0,can_apply_for_free_trial:!1}:t}";
const BACKEND_CLIPBOARD_HISTORY_PURGE: &str = r#"let e=(await E.settings.getInternalExtensionSettings(Hn.id))?.syncedMeta?.historyDuration??"P1W",n=icr(e);n!==null&&await E.clipboard.deleteAllBeforeDate"#;
const BACKEND_CLIPBOARD_HISTORY_UNLIMITED: &str =
    r#"let e="unlimited",n=icr(e);n!==null&&await E.clipboard.deleteAllBeforeDate"#;
const AD_HOC_ENTITLEMENTS: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
</dict>
</plist>
"#;

pub(super) fn patch(frontend_dir: &Path, backend_index: &Path, beta_app: &Path) -> Result<()> {
    if !frontend_dir.exists() {
        return Err(Error::CommandFailed(format!(
            "Raycast Beta frontend directory not found: {}",
            frontend_dir.display()
        )));
    }
    if !backend_index.exists() {
        return Err(Error::CommandFailed(format!(
            "Raycast Beta backend entrypoint not found: {}",
            backend_index.display()
        )));
    }

    let mut changed = false;
    let mut saw_open_settings_fix = false;
    let mut saw_auth_store = false;
    let mut saw_auth_store_patch = false;
    for entry in fs_err::read_dir(frontend_dir)? {
        let path = entry?.path();
        if path.extension().and_then(|extension| extension.to_str()) != Some("js") {
            continue;
        }

        let source = fs_err::read_to_string(&path)?;
        let (patched, status) = patch_frontend_javascript(&source);
        saw_open_settings_fix |= status.open_settings_fixed;
        saw_auth_store |= status.auth_store_seen;
        saw_auth_store_patch |= status.auth_store_dev_user_patch;
        if patched != source {
            write_raycast_app_file(&path, patched)?;
            changed = true;
        }
    }
    let backend_source = fs_err::read_to_string(backend_index)?;
    let (backend_patched, backend_status) = patch_backend_javascript(&backend_source);
    if backend_patched != backend_source {
        write_raycast_app_file(backend_index, backend_patched)?;
        changed = true;
    }

    if !saw_open_settings_fix {
        return Err(Error::CommandFailed(
            "Raycast Beta frontend URL settings patch point not found".into(),
        ));
    }
    if saw_auth_store && !saw_auth_store_patch {
        return Err(Error::CommandFailed(
            "Raycast Beta frontend auth store patch point not found".into(),
        ));
    }
    if !backend_status.dev_user_patch {
        return Err(Error::CommandFailed(
            "Raycast Beta backend auth user patch point not found".into(),
        ));
    }
    if !backend_status.dev_user_event_patch {
        return Err(Error::CommandFailed(
            "Raycast Beta backend auth notification patch point not found".into(),
        ));
    }
    if !backend_status.clipboard_history_unlimited {
        return Err(Error::CommandFailed(
            "Raycast Beta backend Clipboard History retention patch point not found".into(),
        ));
    }
    if changed {
        eprintln!("info: Patched Raycast Beta scripts; ensuring app bundle signature...");
    } else {
        eprintln!("info: Raycast Beta scripts already patched; ensuring app bundle signature...");
    }
    codesign_beta_app(beta_app)?;
    clear_quarantine(beta_app)?;
    Ok(())
}

fn write_raycast_app_file(path: &Path, contents: String) -> Result<()> {
    fs_err::write(path, contents).map_err(|err| {
        if err.kind() == std::io::ErrorKind::PermissionDenied {
            return Error::CommandFailed(format!(
                "macOS blocked writing to Raycast Beta app bundle: {}\n\
                 Grant App Management permission to the terminal app running this command \
                 in System Settings > Privacy & Security > App Management, then restart that \
                 terminal and rerun `chezmoi-support raycast-window-management`.\n\
                 If Raycast Beta was downloaded outside the App Store, you may also need to run \
                 `xattr -dr com.apple.quarantine \"/Applications/Raycast Beta.app\"`.",
                path.display()
            ));
        }
        err.into()
    })
}

#[derive(Debug, Default)]
struct FrontendPatchStatus {
    open_settings_fixed: bool,
    auth_store_seen: bool,
    auth_store_dev_user_patch: bool,
}

fn patch_frontend_javascript(source: &str) -> (String, FrontendPatchStatus) {
    let patched = patch_frontend_auth_store(&remove_obsolete_feature_gate_bypass(
        &patch_open_settings_search(source),
    ));

    let status = FrontendPatchStatus {
        open_settings_fixed: frontend_open_settings_is_fixed(&patched),
        auth_store_seen: patched.contains(FRONTEND_AUTH_STORE_START),
        auth_store_dev_user_patch: frontend_auth_store_is_patched(&patched),
    };
    (patched, status)
}

fn patch_open_settings_search(source: &str) -> String {
    if source.contains(FRONTEND_OPEN_SETTINGS_FIXED) {
        return source.to_owned();
    }
    if source.contains(FRONTEND_OPEN_SETTINGS_BROKEN) {
        return source.replace(FRONTEND_OPEN_SETTINGS_BROKEN, FRONTEND_OPEN_SETTINGS_FIXED);
    }

    let Some(open_settings) = source.find("openSettings:async ") else {
        return source.to_owned();
    };
    let arg_start = open_settings + "openSettings:async ".len();
    let Some(arrow_relative) = source[arg_start..].find("=>{") else {
        return source.to_owned();
    };
    let arrow = arg_start + arrow_relative;
    let arg = source[arg_start..arrow]
        .trim()
        .trim_start_matches('(')
        .trim_end_matches(')');
    if arg.is_empty() || arg.contains(',') {
        return source.to_owned();
    }
    let route_params = format!(",params:{arg}.routeParams");
    let body = arrow + "=>{".len();
    let Some(route_relative) = source[body..].find(&route_params) else {
        return source.to_owned();
    };
    let insert_search = format!(",search:{arg}.search");
    let route_end = body + route_relative + route_params.len();
    if source[route_end..].starts_with(&insert_search) {
        return source.to_owned();
    }
    let Some(close_relative) = source[route_end..].find("})") else {
        return source.to_owned();
    };
    if close_relative > 80 {
        return source.to_owned();
    }
    let insert_at = route_end + close_relative;
    let mut patched = String::with_capacity(source.len() + insert_search.len());
    patched.push_str(&source[..insert_at]);
    patched.push_str(&insert_search);
    patched.push_str(&source[insert_at..]);
    patched
}

fn frontend_open_settings_is_fixed(source: &str) -> bool {
    if source.contains(FRONTEND_OPEN_SETTINGS_FIXED) {
        return true;
    }
    let Some(open_settings) = source.find("openSettings:async ") else {
        return false;
    };
    let arg_start = open_settings + "openSettings:async ".len();
    let Some(arrow_relative) = source[arg_start..].find("=>{") else {
        return false;
    };
    let arrow = arg_start + arrow_relative;
    let arg = source[arg_start..arrow]
        .trim()
        .trim_start_matches('(')
        .trim_end_matches(')');
    !arg.is_empty() && source[arrow..].contains(&format!(",search:{arg}.search"))
}

fn remove_obsolete_feature_gate_bypass(source: &str) -> String {
    // Cleanup for earlier support builds that patched the route gate directly.
    // AuthStore normalization is now the central frontend entitlement path.
    let mut patched = source.to_owned();
    if let Some(feature_gate) = frontend_feature_gate_statement(&patched) {
        let bypass = frontend_feature_gate_bypass(&feature_gate);
        let obsolete_global_bypass = frontend_obsolete_global_feature_gate_bypass(&feature_gate);
        patched = patched.replace(&format!("{obsolete_global_bypass})"), "");
        patched = patched.replace(&obsolete_global_bypass, "");
        patched = patched.replace(&format!("{bypass})"), "");
        patched = patched.replace(&bypass, "");
    }
    patched
}

#[derive(Debug)]
struct FrontendFeatureGate {
    gate_variable: String,
    feature_expression: String,
}

fn frontend_feature_gate_statement(source: &str) -> Option<FrontendFeatureGate> {
    let mut offset = 0;
    while let Some(relative_user) = source[offset..].find(FRONTEND_AUTH_STORE_USER) {
        let user = offset + relative_user;
        let statement_start = source[..user]
            .rfind(['{', ';'])
            .map_or(0, |position| position + 1);
        let statement_end = user + source[user..].find(';')? + 1;
        let statement = &source[statement_start..statement_end];
        if let (Some(gate_variable), Some(feature_expression)) = (
            frontend_gate_variable(statement),
            frontend_feature_expression(statement),
        ) {
            return Some(FrontendFeatureGate {
                gate_variable,
                feature_expression,
            });
        }
        offset = user + FRONTEND_AUTH_STORE_USER.len();
    }
    None
}

fn frontend_gate_variable(statement: &str) -> Option<String> {
    let feature = statement.find(".feature")?;
    let equals = statement[..feature].rfind('=')?;
    let variable_end = statement[..equals].trim_end().len();
    let variable_start = statement[..variable_end]
        .rfind(|character: char| !is_javascript_identifier_part(character))
        .map_or(0, |position| position + 1);
    let variable = &statement[variable_start..variable_end];
    if variable.is_empty() {
        return None;
    }
    Some(variable.to_owned())
}

fn frontend_feature_expression(statement: &str) -> Option<String> {
    let feature = statement.find(".feature")?;
    let expression_start = statement[..feature]
        .rfind(|character: char| !is_javascript_identifier_part(character))
        .map_or(0, |position| position + 1);
    let expression = &statement[expression_start..feature + ".feature".len()];
    if expression.is_empty() {
        return None;
    }
    Some(expression.to_owned())
}

fn frontend_feature_gate_bypass(feature_gate: &FrontendFeatureGate) -> String {
    format!(
        "if([`theme-studio`,`window-management-create`,`notes`,`scheduled-export`].includes({}))return{{cancelled:!1}};",
        feature_gate.feature_expression
    )
}

fn frontend_obsolete_global_feature_gate_bypass(feature_gate: &FrontendFeatureGate) -> String {
    format!(
        "if({}!==void 0&&{}!==`none`)return{{cancelled:!1}};",
        feature_gate.gate_variable, feature_gate.gate_variable
    )
}

fn patch_frontend_auth_store(source: &str) -> String {
    let mut patched = source.to_owned();
    if patched.contains(FRONTEND_AUTH_STORE_START) && !patched.contains(FRONTEND_DEV_USER_FUNCTION)
    {
        patched = patched.replacen(
            FRONTEND_AUTH_STORE_START,
            &format!("{FRONTEND_DEV_USER_FUNCTION}{FRONTEND_AUTH_STORE_START}"),
            1,
        );
    }
    patched = patched.replace(FRONTEND_AUTH_LOGIN_RAW, FRONTEND_AUTH_LOGIN_PATCHED);
    patched = patched.replace(FRONTEND_AUTH_UPDATE_RAW, FRONTEND_AUTH_UPDATE_PATCHED);
    patched = patched.replace(
        FRONTEND_AUTH_APPLY_REMOTE_RAW,
        FRONTEND_AUTH_APPLY_REMOTE_PATCHED,
    );
    patched
}

fn frontend_auth_store_is_patched(source: &str) -> bool {
    if !source.contains(FRONTEND_AUTH_STORE_START) {
        return false;
    }
    source.contains(FRONTEND_DEV_USER_FUNCTION)
        && source.contains(FRONTEND_AUTH_LOGIN_PATCHED)
        && source.contains(FRONTEND_AUTH_UPDATE_PATCHED)
        && source.contains(FRONTEND_AUTH_APPLY_REMOTE_PATCHED)
}

fn is_javascript_identifier_part(character: char) -> bool {
    character.is_ascii_alphanumeric() || matches!(character, '_' | '$')
}

#[derive(Debug, Default)]
struct BackendPatchStatus {
    dev_user_patch: bool,
    dev_user_event_patch: bool,
    clipboard_history_unlimited: bool,
}

fn patch_backend_javascript(source: &str) -> (String, BackendPatchStatus) {
    let patched = patch_backend_clipboard_history(&patch_backend_auth_event(
        &patch_backend_auth_user(source),
    ));
    let status = BackendPatchStatus {
        dev_user_patch: patched.contains(BACKEND_DEV_USER_FUNCTION)
            && patched.contains("getUser:async()=>__raycastLocalDevUser(await "),
        dev_user_event_patch: backend_auth_event_is_patched(&patched),
        clipboard_history_unlimited: backend_clipboard_history_is_unlimited(&patched),
    };
    (patched, status)
}

fn patch_backend_clipboard_history(source: &str) -> String {
    if source.contains(BACKEND_CLIPBOARD_HISTORY_UNLIMITED) {
        return source.to_owned();
    }
    source.replace(
        BACKEND_CLIPBOARD_HISTORY_PURGE,
        BACKEND_CLIPBOARD_HISTORY_UNLIMITED,
    )
}

fn backend_clipboard_history_is_unlimited(source: &str) -> bool {
    source.contains(BACKEND_CLIPBOARD_HISTORY_UNLIMITED)
}

fn patch_backend_auth_user(source: &str) -> String {
    if source.contains(BACKEND_DEV_USER_FUNCTION) {
        return source.to_owned();
    }

    let Some(get_user) = source.find("getUser:()=>") else {
        return source.to_owned();
    };
    let service_start = get_user + "getUser:()=>".len();
    let Some(current_user_relative) = source[service_start..].find(".getCurrentUser()};function ")
    else {
        return source.to_owned();
    };
    let service = &source[service_start..service_start + current_user_relative];
    if service.is_empty() {
        return source.to_owned();
    }
    let first_function_name_start =
        service_start + current_user_relative + ".getCurrentUser()};function ".len();
    let Some(first_function_name_end_relative) = source[first_function_name_start..].find("(){")
    else {
        return source.to_owned();
    };
    let first_function_name_end = first_function_name_start + first_function_name_end_relative;
    let first_function_name = &source[first_function_name_start..first_function_name_end];
    let first_function_raw =
        format!("function {first_function_name}(){{return {service}.getCurrentUser()}}function ");
    let first_function_start = first_function_name_start.saturating_sub("function ".len());
    if !source[first_function_start..].starts_with(&first_function_raw) {
        return source.to_owned();
    }
    let second_function_name_start = first_function_start + first_function_raw.len();
    let Some(second_function_name_end_relative) = source[second_function_name_start..].find('(')
    else {
        return source.to_owned();
    };
    let second_function_name_end = second_function_name_start + second_function_name_end_relative;
    let second_function_name = &source[second_function_name_start..second_function_name_end];
    let parameter_start = second_function_name_end + 1;
    let Some(parameter_end_relative) = source[parameter_start..].find("){") else {
        return source.to_owned();
    };
    let parameter_end = parameter_start + parameter_end_relative;
    let parameter = &source[parameter_start..parameter_end];
    let raw = format!(
        "getUser:()=>{service}.getCurrentUser()}};{first_function_raw}{second_function_name}({parameter}){{return {service}.refreshCurrentUser({parameter})}}"
    );
    let patched = format!(
        "getUser:async()=>__raycastLocalDevUser(await {service}.getCurrentUser())}};{BACKEND_DEV_USER_FUNCTION}function {first_function_name}(){{return {service}.getCurrentUser().then(__raycastLocalDevUser)}}function {second_function_name}({parameter}){{return {service}.refreshCurrentUser({parameter}).then(__raycastLocalDevUser)}}"
    );
    source.replace(&raw, &patched)
}

fn patch_backend_auth_event(source: &str) -> String {
    let Some((body_start, user_variable)) = backend_auth_event_body(source) else {
        return source.to_owned();
    };
    let normalization = format!("{user_variable}=__raycastLocalDevUser({user_variable}),");
    if source[body_start..].starts_with(&normalization) {
        return source.to_owned();
    }

    let mut patched = String::with_capacity(source.len() + normalization.len());
    patched.push_str(&source[..body_start]);
    patched.push_str(&normalization);
    patched.push_str(&source[body_start..]);
    patched
}

fn backend_auth_event_is_patched(source: &str) -> bool {
    let Some((body_start, user_variable)) = backend_auth_event_body(source) else {
        return false;
    };
    source[body_start..].starts_with(&format!(
        "{user_variable}=__raycastLocalDevUser({user_variable}),"
    ))
}

fn backend_auth_event_body(source: &str) -> Option<(usize, String)> {
    let event = ".on(\"auth:userChanged\",({user:";
    let event_start = source.find(event)?;
    let user_variable_start = event_start + event.len();
    let user_variable_end = source[user_variable_start..].find("})=>{")? + user_variable_start;
    let user_variable = &source[user_variable_start..user_variable_end];
    if user_variable.is_empty() {
        return None;
    }
    Some((user_variable_end + "})=>{".len(), user_variable.to_owned()))
}

fn codesign_beta_app(beta_app: &Path) -> Result<()> {
    let entitlements = tempfile::Builder::new()
        .prefix("raycast-entitlements")
        .suffix(".plist")
        .tempfile()?;
    fs_err::write(entitlements.path(), AD_HOC_ENTITLEMENTS)?;
    let entitlements_path = entitlements.path().to_string_lossy();
    let beta_app = beta_app
        .to_str()
        .ok_or_else(|| Error::CommandFailed("invalid Raycast Beta app path".into()))?;
    let output = command_output(&argv([
        "codesign",
        "--force",
        "--deep",
        "--preserve-metadata=flags,runtime",
        "--entitlements",
        &entitlements_path,
        "--sign",
        "-",
        beta_app,
    ]))?;
    if output.status.success() {
        return Ok(());
    }

    let detail = output_detail(&output);
    Err(Error::CommandFailed(format!(
        "Raycast Beta app re-sign failed: {detail}"
    )))
}

fn clear_quarantine(beta_app: &Path) -> Result<()> {
    let beta_app = beta_app
        .to_str()
        .ok_or_else(|| Error::CommandFailed("invalid Raycast Beta app path".into()))?;
    let output = command_output(&argv(["xattr", "-dr", "com.apple.quarantine", beta_app]))?;
    if output.status.success() {
        return Ok(());
    }

    let detail = output_detail(&output);
    if detail.contains("No such xattr") {
        return Ok(());
    }
    Err(Error::CommandFailed(format!(
        "failed to clear Raycast Beta quarantine attribute: {detail}"
    )))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frontend_patch_preserves_settings_route_search() {
        let source = format!("before {FRONTEND_OPEN_SETTINGS_BROKEN} after");
        let (patched, status) = patch_frontend_javascript(&source);
        assert!(status.open_settings_fixed);
        assert!(patched.contains(FRONTEND_OPEN_SETTINGS_FIXED));
        assert!(!patched.contains(FRONTEND_OPEN_SETTINGS_BROKEN));
    }

    #[test]
    fn open_settings_patch_handles_minifier_variants() {
        let source = "openSettings:async t=>{Na({to:t.to,params:t.routeParams})}";

        assert_eq!(
            patch_open_settings_search(source),
            "openSettings:async t=>{Na({to:t.to,params:t.routeParams,search:t.search})}"
        );
    }

    #[test]
    fn open_settings_patch_ignores_unknown_shapes() {
        for source in [
            "const unrelated=true;",
            "openSettings:async (t,u)=>{Na({to:t.to,params:t.routeParams})}",
            "openSettings:async t=>{Na({to:t.to})}",
            "openSettings:async t=>{Na({to:t.to,params:t.routeParams,search:t.search})}",
            "openSettings:async t=>{Na({to:t.to,params:t.routeParams,extra:`long enough to avoid patching because the route call is not the expected compact shape`})}",
        ] {
            assert_eq!(patch_open_settings_search(source), source);
        }
    }

    #[test]
    fn frontend_patch_removes_obsolete_feature_gate_bypass() {
        let source = "async function z(a){let b=c.authStore.peek().user,d=b!==null,f=g(a.feature);if([`theme-studio`,`window-management-create`,`notes`,`scheduled-export`].includes(a.feature))return{cancelled:!1};)if([`theme-studio`,`window-management-create`,`notes`,`scheduled-export`].includes(a.feature))return{cancelled:!1};if(f===`none`)return{cancelled:!1}}";
        let (patched, _) = patch_frontend_javascript(source);
        assert!(!patched.contains(
            "if([`theme-studio`,`window-management-create`,`notes`,`scheduled-export`].includes(a.feature))return{cancelled:!1};"
        ));
        assert!(patched.contains("if(f===`none`)return{cancelled:!1}"));
    }

    #[test]
    fn frontend_patch_removes_obsolete_global_feature_gate_bypass() {
        let source = "async function z(a){let b=c.authStore.peek().user,d=b!==null,f=g(a.feature);if(f!==void 0&&f!==`none`)return{cancelled:!1};if(f===`none`)return{cancelled:!1}}";
        let (patched, _) = patch_frontend_javascript(source);
        assert!(!patched.contains("if(f!==void 0&&f!==`none`)return{cancelled:!1};"));
        assert!(patched.contains("if(f===`none`)return{cancelled:!1}"));
    }

    #[test]
    fn frontend_patch_normalizes_auth_store_user_for_dev_ui() {
        let source = format!(
            "{FRONTEND_AUTH_STORE_START}let t=p(`AuthStore`,{{context:{{user:null}},actions:{{login:async({{set:t}})=>{{{FRONTEND_AUTH_LOGIN_RAW},r=null;t({{user:n}}),e.send({{window:window.identifier,data:{{user:n}}}})}},{FRONTEND_AUTH_UPDATE_RAW},{FRONTEND_AUTH_APPLY_REMOTE_RAW}}}}})}}"
        );
        let (patched, status) = patch_frontend_javascript(&source);
        assert!(status.auth_store_seen);
        assert!(status.auth_store_dev_user_patch);
        assert!(patched.contains(FRONTEND_DEV_USER_FUNCTION));
        assert!(patched.contains(FRONTEND_AUTH_LOGIN_PATCHED));
        assert!(patched.contains(FRONTEND_AUTH_UPDATE_PATCHED));
        assert!(patched.contains(FRONTEND_AUTH_APPLY_REMOTE_PATCHED));
    }

    #[test]
    fn backend_patch_normalizes_raycast_dev_user_capabilities() {
        let source = "before getUser:()=>Zx.getCurrentUser()};function aa(){return Zx.getCurrentUser()}function bb(cc){return Zx.refreshCurrentUser(cc)} Y.on(\"auth:userChanged\",({user:dd})=>{Ee.auth.emitUserChanged({user:dd}),Ff.host.auth.userChanged({user:dd})}) after";
        let (patched, status) = patch_backend_javascript(source);
        assert!(status.dev_user_patch);
        assert!(status.dev_user_event_patch);
        assert!(patched.contains("has_pro_features:!0"));
        assert!(patched.contains("can_apply_for_free_trial:!1"));
        assert!(
            patched
                .contains("function aa(){return Zx.getCurrentUser().then(__raycastLocalDevUser)}")
        );
        assert!(patched.contains(
            "function bb(cc){return Zx.refreshCurrentUser(cc).then(__raycastLocalDevUser)}"
        ));
        assert!(patched.contains("dd=__raycastLocalDevUser(dd),Ee.auth.emitUserChanged"));
    }

    #[test]
    fn backend_patch_disables_clipboard_history_purge() {
        let source = format!(
            "function icr(t){{if(t===`unlimited`)return null}}async function bkt(){{{BACKEND_CLIPBOARD_HISTORY_PURGE}({{date:n.toISOString(),includePinned:!1}})}}"
        );
        let (patched, status) = patch_backend_javascript(&source);
        assert!(status.clipboard_history_unlimited);
        assert!(patched.contains(BACKEND_CLIPBOARD_HISTORY_UNLIMITED));
        assert!(!patched.contains(r#"historyDuration??"P1W""#));
    }
}

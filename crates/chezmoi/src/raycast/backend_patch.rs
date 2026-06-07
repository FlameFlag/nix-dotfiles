use super::local_user;

#[derive(Debug, Default)]
pub(super) struct PatchStatus {
    pub(super) dev_user_patch: bool,
    pub(super) dev_user_event_patch: bool,
}

pub(super) fn patch_javascript(source: &str) -> (String, PatchStatus) {
    let patched = patch_auth_event(&patch_auth_user(source));
    let status = PatchStatus {
        dev_user_patch: patched.contains(local_user::FUNCTION)
            && patched.contains("getUser:async()=>__raycastLocalDevUser(await "),
        dev_user_event_patch: auth_event_is_patched(&patched),
    };
    (patched, status)
}

fn patch_auth_user(source: &str) -> String {
    if source.contains(local_user::FUNCTION) {
        return source.to_owned();
    }
    if let Some((start, end)) = dev_user_function_range(source) {
        let mut patched = String::with_capacity(source.len() + local_user::FUNCTION.len());
        patched.push_str(&source[..start]);
        patched.push_str(local_user::FUNCTION);
        patched.push_str(&source[end..]);
        return patched;
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
        "getUser:async()=>__raycastLocalDevUser(await {service}.getCurrentUser())}};{}function {first_function_name}(){{return {service}.getCurrentUser().then(__raycastLocalDevUser)}}function {second_function_name}({parameter}){{return {service}.refreshCurrentUser({parameter}).then(__raycastLocalDevUser)}}",
        local_user::FUNCTION
    );
    source.replace(&raw, &patched)
}

fn dev_user_function_range(source: &str) -> Option<(usize, usize)> {
    let start = source.find("function __raycastLocalDevUser(")?;
    let body_start = source[start..].find('{')? + start;
    let mut depth = 0usize;
    for (offset, byte) in source[body_start..].bytes().enumerate() {
        match byte {
            b'{' => depth += 1,
            b'}' => {
                depth = depth.checked_sub(1)?;
                if depth == 0 {
                    return Some((start, body_start + offset + 1));
                }
            }
            _ => {}
        }
    }
    None
}

fn patch_auth_event(source: &str) -> String {
    let Some((body_start, user_variable)) = auth_event_body(source) else {
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

fn auth_event_is_patched(source: &str) -> bool {
    let Some((body_start, user_variable)) = auth_event_body(source) else {
        return false;
    };
    source[body_start..].starts_with(&format!(
        "{user_variable}=__raycastLocalDevUser({user_variable}),"
    ))
}

fn auth_event_body(source: &str) -> Option<(usize, String)> {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backend_patch_normalizes_raycast_dev_user_capabilities() {
        let source = "before getUser:()=>Zx.getCurrentUser()};function aa(){return Zx.getCurrentUser()}function bb(cc){return Zx.refreshCurrentUser(cc)} Y.on(\"auth:userChanged\",({user:dd})=>{Ee.auth.emitUserChanged({user:dd}),Ff.host.auth.userChanged({user:dd})}) after";
        let (patched, status) = patch_javascript(source);
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
    fn backend_patch_rewrites_existing_dev_user_helper() {
        let source = "getUser:async()=>__raycastLocalDevUser(await Zx.getCurrentUser())};function __raycastLocalDevUser(t){return t}function aa(){return Zx.getCurrentUser().then(__raycastLocalDevUser)} Y.on(\"auth:userChanged\",({user:dd})=>{dd=__raycastLocalDevUser(dd),Ee.auth.emitUserChanged({user:dd})})";
        let (patched, status) = patch_javascript(source);
        assert!(status.dev_user_patch);
        assert!(status.dev_user_event_patch);
        assert!(patched.contains(local_user::FUNCTION));
        assert!(patched.contains("raycast-local-dev-user"));
    }
}

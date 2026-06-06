use super::local_user;
const AUTH_LOGIN_RAW: &str = "let n=await m.ipc.backend.auth.getUser()";
const AUTH_LOGIN_PATCHED: &str = "let n=__raycastLocalDevUser(await m.ipc.backend.auth.getUser())";
const AUTH_UPDATE_RAW: &str =
    "update:async({set:t},n)=>{t(e=>({...e,...n})),e.send({window:window.identifier,data:n})}";
const AUTH_UPDATE_PATCHED: &str = "update:async({set:t},n)=>{n.user!==void 0&&(n={...n,user:__raycastLocalDevUser(n.user)}),t(e=>({...e,...n})),e.send({window:window.identifier,data:n})}";
const AUTH_APPLY_REMOTE_RAW: &str = "applyRemote:async({set:e},t)=>{e(e=>({...e,...t}))}";
const AUTH_APPLY_REMOTE_PATCHED: &str = "applyRemote:async({set:e},t)=>{t.user!==void 0&&(t={...t,user:__raycastLocalDevUser(t.user)}),e(e=>({...e,...t}))}";

#[derive(Debug, Default)]
pub(super) struct PatchStatus {
    pub(super) auth_store_seen: bool,
    pub(super) auth_store_dev_user_patch: bool,
}

pub(super) fn patch_javascript(source: &str) -> (String, PatchStatus) {
    let patched = patch_auth_store(source);

    let status = PatchStatus {
        auth_store_seen: auth_store_is_seen(&patched),
        auth_store_dev_user_patch: auth_store_is_patched(&patched),
    };
    (patched, status)
}

pub(super) fn is_auth_store_chunk(source: &str) -> bool {
    auth_store_is_seen(source)
        || source.contains("registerLazyService(`authStore`")
        || source.contains(local_user::FUNCTION)
}

fn patch_auth_store(source: &str) -> String {
    let mut patched = source.to_owned();
    if auth_store_is_seen(&patched) && !patched.contains(local_user::FUNCTION) {
        let insert_at = auth_store_function_start(&patched).unwrap_or(0);
        patched.insert_str(insert_at, local_user::FUNCTION);
    }
    patched = patch_auth_get_user_calls(&patched);
    patched = patched.replace(AUTH_LOGIN_RAW, AUTH_LOGIN_PATCHED);
    patched = patched.replace(AUTH_UPDATE_RAW, AUTH_UPDATE_PATCHED);
    patched = patched.replace(AUTH_APPLY_REMOTE_RAW, AUTH_APPLY_REMOTE_PATCHED);
    patched
}

fn auth_store_is_seen(source: &str) -> bool {
    source.contains("p(`AuthStore`")
}

fn auth_store_function_start(source: &str) -> Option<usize> {
    let auth_store = source.find("p(`AuthStore`")?;
    source[..auth_store].rfind("function ")
}

fn patch_auth_get_user_calls(source: &str) -> String {
    const NEEDLE: &str = ".ipc.backend.auth.getUser()";
    let mut patched = String::with_capacity(source.len());
    let mut cursor = 0;
    while let Some(relative_call) = source[cursor..].find(NEEDLE) {
        let call = cursor + relative_call;
        let Some(await_relative) = source[cursor..call].rfind("await ") else {
            patched.push_str(&source[cursor..call + NEEDLE.len()]);
            cursor = call + NEEDLE.len();
            continue;
        };
        let await_start = cursor + await_relative;
        if source[..await_start].ends_with("__raycastLocalDevUser(") {
            patched.push_str(&source[cursor..call + NEEDLE.len()]);
            cursor = call + NEEDLE.len();
            continue;
        }
        let receiver = &source[await_start + "await ".len()..call];
        if receiver.is_empty()
            || receiver.len() > 32
            || !receiver
                .chars()
                .all(|character| is_javascript_identifier_part(character) || character == '.')
        {
            patched.push_str(&source[cursor..call + NEEDLE.len()]);
            cursor = call + NEEDLE.len();
            continue;
        }
        patched.push_str(&source[cursor..await_start]);
        patched.push_str("__raycastLocalDevUser(await ");
        patched.push_str(receiver);
        patched.push_str(NEEDLE);
        patched.push(')');
        cursor = call + NEEDLE.len();
    }
    patched.push_str(&source[cursor..]);
    patched
}

fn auth_store_is_patched(source: &str) -> bool {
    if !auth_store_is_seen(source) {
        return false;
    }
    source.contains(local_user::FUNCTION) && source.contains("__raycastLocalDevUser(await ")
}

fn is_javascript_identifier_part(character: char) -> bool {
    character.is_ascii_alphanumeric() || matches!(character, '_' | '$')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frontend_patch_normalizes_auth_store_user_for_dev_ui() {
        let source = format!(
            "function aa(){{let e=qq(`auth`);let t=p(`AuthStore`,{{context:{{user:null}},actions:{{login:async({{set:t}})=>{{{AUTH_LOGIN_RAW},r=null;t({{user:n}}),e.send({{window:window.identifier,data:{{user:n}}}})}},{AUTH_UPDATE_RAW},{AUTH_APPLY_REMOTE_RAW}}}}})}}"
        );
        let (patched, status) = patch_javascript(&source);
        assert!(status.auth_store_seen);
        assert!(status.auth_store_dev_user_patch);
        assert!(patched.contains(local_user::FUNCTION));
        assert!(patched.contains(AUTH_LOGIN_PATCHED));
        assert!(patched.contains(AUTH_UPDATE_PATCHED));
        assert!(patched.contains(AUTH_APPLY_REMOTE_PATCHED));
    }

    #[test]
    fn frontend_patch_handles_current_auth_store_names() {
        let source = "function oc(){let e=sn(`auth`);let t=p(`AuthStore`,{context:{user:null,accessToken:null,hasAcceptedStoreToS:!1},actions:{login:async({set:t})=>{let n=await c.ipc.backend.auth.getUser(),r=(await c.ipc.backend.auth.getToken())?.access_token??null;t({user:n,accessToken:r}),e.send({window:window.identifier,data:{user:n,accessToken:r}})}}});return t}";
        let (patched, status) = patch_javascript(source);
        assert!(status.auth_store_seen);
        assert!(status.auth_store_dev_user_patch);
        assert!(patched.contains(local_user::FUNCTION));
        assert!(
            patched.contains("let n=__raycastLocalDevUser(await c.ipc.backend.auth.getUser())")
        );
    }
}

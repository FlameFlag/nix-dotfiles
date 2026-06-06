# Raycast Beta Patch

## Scope

The support command targets local Raycast Beta app behavior only:

```text
chezmoi-support raycast-beta-patch
```

It patches the installed Raycast Beta frontend/backend bundles so local auth
checks see a synthetic signed-in user with Pro capabilities.

Patched user properties:

```text
id=raycast-local-dev-user
email=dev@localhost
has_pro_features=true
can_apply_for_free_trial=false
subscription.id=raycast-local-pro
subscription.status=active
```

Out of scope:

```text
hosted Raycast services
fallback tokens
remote entitlement or billing state
```

## Patch Anchors

Frontend patching normalizes AuthStore users from:

```text
p(`AuthStore`)
registerLazyService(`authStore`)
backend.auth.getUser()
```

Backend patching normalizes users from:

```text
getCurrentUser()
refreshCurrentUser(...)
auth:userChanged
```

The patcher derives minified local variable and function names where practical,
so routine chunk renames and one-letter symbol shuffling should survive. It
still intentionally fails closed if Raycast changes the auth-store structure,
IPC method names, or auth event shape enough that the patch cannot prove it hit
the intended code.

## Module Layout

```text
raycast.rs: Darwin gate and Raycast Beta bundle path resolution
raycast/bundle.rs: app bundle scanning, writes, ad-hoc codesign, quarantine clear
raycast/frontend_patch.rs: frontend AuthStore user normalization
raycast/backend_patch.rs: backend auth facade and auth event normalization
raycast/local_user.rs: shared synthetic user helper injected into JS
```

The frontend scan intentionally patches only the shared AuthStore chunk. Other
frontend windows that call `backend.auth.getUser()` receive the normalized user
from the patched backend auth facade, so rewriting every consumer adds churn
without making the account state more reliable.

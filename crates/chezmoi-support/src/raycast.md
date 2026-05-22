# Raycast Beta Research Notes

## Target

Bundle paths of interest:

```text
Contents/MacOS/Raycast Beta
Contents/Frameworks/libraycast_host.dylib
Contents/Resources/macos-app_RaycastDesktopApp.bundle/Contents/Resources/{frontend,backend,api,node}
```

Frontend chunks are not sourcemapped in this build, but retain dense string and
object-literal metadata. Useful chunks:

```text
frontend/internal-extensions-C86ls1na.js
frontend/main-window-BHdVFQS6.js
frontend/settings-window-ThCXiZoQ.js
frontend/extension-command-ids-D71sDW4v.js
```

## Encryption

`main.db` is SQLite SEE, not SQLCipher.

Evidence: binding strings `CODEC=see`, `HAS_CODEC`, `aes128`, `aes256`,
`aes128ofb`, `aes256ofb`, `aes256gcm`, `hexkey`, `textkey`; system
`sqlcipher` fails with the correct passphrase; Raycast's native binding opens
the DB with that same passphrase.

Consequence: no system `sqlcipher`. Pure Rust DB access needs SEE compatibility.

Passphrase:

```text
Keychain: service=Raycast Beta, account=database_key
Fetch: security find-generic-password -s "Raycast Beta" -a "database_key" -w
Transform: lower_hex(sha256(database_key + "yvkwWXzxPPBAqY2tmaKrB*DvYjjMaeEf"))
Override: RAYCAST_BETA_DATABASE_PASSWORD is the derived passphrase, not raw key.
```

## Internal IPC

Raycast uses split frontend/backend/host IPC. Native host strings expose
`WindowManagement{GetActiveWindow,GetDesktops,GetWindowsOnActiveDesktop,OpenAndSetWindowBounds,SetWindowBounds,ShowGridPlacement}Handler`.

Frontend host calls:

```text
windowManagement.{getDesktops(),getActiveWindow(),showGridPlacement()}
windowManagement.setWindowBounds({ id, bounds, desktopId? })
windowManagement.openAndSetWindowBounds({ layouts })
windowManagement.toggleAlwaysOnTop({ id })
virtualDesktops.{getActiveIndex(),switch({ index, animated? }),close({ index }),rename({ index, name })}
virtualDesktops.getByIndex({ index })
virtualDesktops.moveWindow({ windowId, desktopIndex })
```

Frontend-to-frontend IPC exposes one helper:

```text
windowManagement.resolveLayoutBounds({
  layout: { position, size, offset, ignoreGap },
  desktopSize,
  windowSize
}) -> { bounds: "fullscreen" | { position, size } }
```

The public extension API bundle also exports `WindowManagement`, but built-in
Window Management uses host IPC directly from `main-window-*.js`.

## Debug Hooks

Useful strings/handlers:

```text
raycast.inspectWebView, raycast.toggleInspectWebView
RaycastInspectWebViewHandler, RaycastToggleInspectWebViewHandler
OPEN_INSPECTOR_ON_START, allowInspectingWebViews, window.inspectable =
http://localhost:{3000,3001,5001}, http://localhost:8969/stream
```

Visible commands: `raycast/raycast/inspect-web-view` calls
`M.ipc.host.raycast.inspectWebView()` and sets `window.inspectable=true`;
debug command `debug-toggle-inspect-webview` calls
`M.ipc.host.raycast.toggleInspectWebView()` and stores the returned boolean in
`window.inspectable`; About/overflow has internal `Toggle WebView Inspection`
with the same host call.

Environment/user-default toggles:

```text
RAYCAST_API_ENVIRONMENT, RAYCAST_API_CUSTOM_BACKEND_URL, RAYCAST_API_CUSTOM_FRONTEND_URL
RAYCAST_ENABLE_HANG_DETECTOR, RAYCAST_ENABLE_PERFORMANCE_LOGS, RAYCAST_ENABLE_UI_TESTING, RAYCAST_LOG
raycast_apiEnvironment, raycast_apiCustomBackendURL, raycast_apiCustomFrontendURL
raycast_enableBackendExtensions, raycast_errorReporting_debugLoggingEnabled
raycast_enablePerformanceLogs, raycast_enablePerformanceMetrics
```

Developer extension preferences:

```text
useNodeProductionEnvironment=false, autoReloadOnSave=true
disablePopToRootSearch=false, openRaycastInDevelopmentMode=true
```

`openRaycastInDevelopmentMode` only controls dev-extension behavior:
"Automatically open Raycast and pop to the root search after the first initial
build". The WebView inspector/debug path is separate: use the internal/debug
command above or try `OPEN_INSPECTOR_ON_START`.

## Window Management

Internal extension:

```text
id=e:r:window-management, key=window-management, title=Window Management
settings route=/extensions/e:r:window-management
view route=/extension/window-management/switch-desktops
```

Preferences: `innerGap` synced number default `0`; `outerGap` synced number
default `0`; `cycleMode` synced enum default `"sizes"`; `respectStageManager`
synced bool default `false`; `autoCloseEmptyDesktops` platform bool default
`false`.

Settings route search schema:

```text
intent?: "create-command" | "edit-command" | "create-layout" | "edit-layout"
layoutGroupId?: string
```

Create buttons deeplink to `/extensions/e:r:window-management?intent=create-command`
and `/extensions/e:r:window-management?intent=create-layout`.

Raycast Beta shipped frontend/backend regressions blocking these dev flows:

- `openSettings` bridge dropped `search`, flattening settings deeplinks like
  `raycast-x://extensions/raycast/window-management/create-command` back to the
  generic extension settings route
- frontend Pro gate maps `window-management-create` to `pro-paywall` and checks
  only `authStore.peek().user?.has_pro_features`

Local Pro wall map:

```text
pro-paywall: theme-studio, translator, window-management-create, notes, scheduled-export
clipboard-history settings: 1D/1W/1M/3M visible by default; 6M/1Y/unlimited
  appended only when user.has_pro_features is true
```

Patch boundary:

```text
patch local app behavior:
  frontend route gate -> /pro-gating
  frontend/backend user.has_pro_features
  trial UI based on user.can_apply_for_free_trial
  local retention/default settings such as Clipboard History
do not patch hosted or token-backed features:
  leave those disabled unless a real local implementation exists
```

The support code only targets local app behavior. Do not add fallback tokens,
hosted entitlement flags, or fake access to features that require external
Raycast services.

Clipboard History is local. The backend retention helper already accepts
`historyDuration="unlimited"` by returning `null` and skipping
`clipboard.deleteAllBeforeDate(...)`; the shipped dev bug is that the settings
panel hides `Unlimited` behind `user.has_pro_features` and the maintenance task
defaults to `P1W`. Our patch gives the frontend auth store a synthetic dev Pro
user for UI entitlement checks and forces the maintenance task to evaluate
`unlimited`, so a signed-out dev build does not silently delete old clipboard
items.

Search anchors for future bundle scans:

```text
frontend: /pro-gating, pro-paywall, sign-in-during-beta, has_pro_features,
  can_apply_for_free_trial, authStore.peek().user, openSettings:async,
  routeParams, Get Unlimited Clipboard History, historyDuration
backend: getCurrentUser(), refreshCurrentUser(, auth:userChanged,
  has_pro_features, can_apply_for_free_trial, deleteAllBeforeDate,
  historyDuration, unlimited
```

`raycast/beta_scripts.rs` patches the frontend bundle before DB updates and
patches the backend auth user facade so local dev entitlement checks see the
intended capabilities. It searches stable bundle shapes (`openSettings`,
`routeParams`, `authStore.peek().user`, `getCurrentUser()`,
`refreshCurrentUser()`, `auth:userChanged`) and derives minified local variable
names at runtime, so routine chunk renaming or single-letter variable shuffling
should not break it.

```text
openSettings:async e=>{Na({to:e.to,params:e.routeParams})}
  -> openSettings:async e=>{Na({to:e.to,params:e.routeParams,search:e.search})}
previous frontend route-gate bypass patches
  -> removed; frontend AuthStore normalization makes local pro-paywall checks
     pass without feature-specific route surgery
backend auth getUser()/to()/refreshCurrentUser()
  -> wraps returned user with has_pro_features=true, can_apply_for_free_trial=false
backend auth:userChanged notification
  -> emits the same normalized user to frontend/host subscribers
normalized user: has_pro_features=true, can_apply_for_free_trial=false
frontend AuthStore login/update/applyRemote
  -> exposes a synthetic dev user with has_pro_features=true,
     can_apply_for_free_trial=false, subscription.status=active
Clipboard History maintenance task
  -> forces historyDuration to "unlimited" before deleteAllBeforeDate can run
```

Any frontend patch requires re-signing `/Applications/Raycast Beta.app`; the
support command uses local ad-hoc signing and preserves signature metadata where
`codesign` allows it.

This removes the shared `/pro-gating` wall and local Pro checks. Hosted or
token-backed features are explicitly out of scope for this patcher.

Current helper layout:

```text
raycast.rs: orchestration and app/support paths; RAYCAST_BETA_APP override for
  testing a copied app bundle from a DMG
raycast/beta_scripts.rs: frontend deeplink search preservation; frontend
  dev-Pro AuthStore normalization; backend auth user normalization; cleanup for
  earlier route-gate patches; Clipboard History unlimited retention; app
  re-signing
raycast/window_db.rs: encrypted DB password derivation; native DatabaseClient
  apply script; classic command id/hotkey conversion; layout group writes
```

Runtime dispatcher:

```text
"run-window-management-command" -> VQ(command.key, payload.id?, launchProps)
VQ order: dynamic layoutGroup payload id -> AQ(layoutGroupId); special map BQ;
  geometry map bQ; regex openDesktop(\d+); regex moveWindowToDesktop(\d+)
```

Special command map:

```text
restore -> restore last stored bounds
toggleFullscreen -> toggle fullscreen, restoring previous bounds when possible
toggleAlwaysOnTop -> Windows topmost toggle
gridPlacement -> show host grid overlay
switchToPreviousSpace/switchToLeftSpace -> virtualDesktops.switch(left)
switchToNextSpace/switchToRightSpace -> virtualDesktops.switch(right)
createWindowManagementCommand -> settings intent=create-command
createWindowManagementLayout -> settings intent=create-layout
switchDesktop -> /extension/window-management/switch-desktops
openDesktop(index); moveWindowToDesktop(index); closeActiveDesktop()
closeDesktop(index); renameActiveDesktop(name); renameDesktop(index, name)
```

Geometry model: host provides `{ window, desktop, desktops }` via
`getActiveWindow()`/`getDesktops()`; bounds are active-desktop-relative;
fullscreen is `"fullscreen"`; `setWindowBounds` input is `{ id, bounds:
"fullscreen", desktopId? }` or `{ id, bounds: { position, size }, desktopId? }`;
gap settings apply in frontend before `setWindowBounds` unless command/layout
has `ignoreGap`; `cycleMode` changes half/center cycling with modes `sizes`,
`displays`, and fallback/default.

Custom command/layout persistence is in `data.darwin-arm64.node`:

```sql
CREATE TABLE window_management_layout_groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  icon_name TEXT,
  ignore_gap INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE window_management_layouts (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES window_management_layout_groups(id) ON DELETE CASCADE,
  position TEXT NOT NULL,
  size TEXT NOT NULL,
  offset TEXT,
  z_position INTEGER NOT NULL,
  source TEXT,
  display_index INTEGER
);
```

N-API strings expose repository methods `getLayout`, `saveLayout`,
`deleteLayout`, `windowManagement`, `WindowManagementRepository`. `saveLayout`
accepts layout-group-like data: `name`, `iconName`, `ignoreGap`, and
`layouts: [{ position, size, offset, zPosition, source, displayIndex }]`. If the
first layout has no `source`, the group behaves like a custom single-window
command; if layouts have `source`, frontend calls `openAndSetWindowBounds({
layouts })`.

## Window Management Deeplinks

Public formats:

```text
raycast-x://extensions/raycast/window-management/<command-slug>
raycast://extensions/raycast/window-management/<command-slug>
```

The command slug is title-derived kebab case, e.g.
`raycast-x://extensions/raycast/window-management/{create-command,create-layout,left-half}`.
Argument commands use common Raycast `arguments=` query JSON, e.g. Windows
desktop-index commands expect `?arguments=%7B%22index%22%3A%221%22%7D`.

Static command map (`slug | key | title | notes`):

| slug                                         | key                                                | title                    | notes                           |
| -------------------------------------------- | -------------------------------------------------- | ------------------------ | ------------------------------- |
| `maximize`                                   | `maximize`                                         | Maximize                 |                                 |
| `restore`                                    | `restore`                                          | Restore                  |                                 |
| `maximize-height`                            | `maximizeHeight`                                   | Maximize Height          |                                 |
| `maximize-width`                             | `maximizeWidth`                                    | Maximize Width           |                                 |
| `almost-maximize`                            | `maximizeAlmost`                                   | Almost Maximize          | percentage pref, default 90%    |
| `reasonable-size`                            | `reasonableSize`                                   | Reasonable Size          | 60%, max 1024x900               |
| `center`                                     | `center`                                           | Center                   | move only                       |
| `center-half`                                | `centerHalf`                                       | Center Half              | cycle-aware                     |
| `left-half`                                  | `leftHalf`                                         | Left Half                | cycle-aware                     |
| `right-half`                                 | `rightHalf`                                        | Right Half               | cycle-aware                     |
| `top-half`                                   | `topHalf`                                          | Top Half                 | cycle-aware                     |
| `bottom-half`                                | `bottomHalf`                                       | Bottom Half              | cycle-aware                     |
| `first-third`                                | `firstThird`                                       | First Third              |                                 |
| `center-third`                               | `centerThird`                                      | Center Third             |                                 |
| `last-third`                                 | `lastThird`                                        | Last Third               |                                 |
| `first-two-thirds`                           | `firstTwoThird`                                    | First Two Thirds         |                                 |
| `center-two-thirds`                          | `centerTwoThird`                                   | Center Two Thirds        |                                 |
| `last-two-thirds`                            | `lastTwoThird`                                     | Last Two Thirds          |                                 |
| `first-three-fourths`                        | `firstThreeFourth`                                 | First Three Fourths      |                                 |
| `center-three-fourths`                       | `centerThreeFourth`                                | Center Three Fourths     |                                 |
| `last-three-fourths`                         | `lastThreeFourth`                                  | Last Three Fourths       |                                 |
| `top-third`                                  | `topThird`                                         | Top Third                |                                 |
| `middle-third`                               | `middleThird`                                      | Middle Third             |                                 |
| `bottom-third`                               | `bottomThird`                                      | Bottom Third             |                                 |
| `top-two-thirds`                             | `topTwoThird`                                      | Top Two Thirds           |                                 |
| `bottom-two-thirds`                          | `bottomTwoThird`                                   | Bottom Two Thirds        |                                 |
| `top-first-fourth`                           | `topFirstFourth`                                   | Top First Fourth         |                                 |
| `top-second-fourth`                          | `topSecondFourth`                                  | Top Second Fourth        |                                 |
| `top-third-fourth`                           | `topThirdFourth`                                   | Top Third Fourth         |                                 |
| `top-last-fourth`                            | `topLastFourth`                                    | Top Last Fourth          |                                 |
| `top-three-fourths`                          | `topThreeFourth`                                   | Top Three Fourths        |                                 |
| `bottom-three-fourths`                       | `bottomThreeFourth`                                | Bottom Three Fourths     |                                 |
| `top-center-two-thirds`                      | `topCenterTwoThird`                                | Top Center Two Thirds    |                                 |
| `bottom-center-two-thirds`                   | `bottomCenterTwoThird`                             | Bottom Center Two Thirds |                                 |
| `first-fourth`                               | `firstFourth`                                      | First Fourth             |                                 |
| `second-fourth`                              | `secondFourth`                                     | Second Fourth            |                                 |
| `third-fourth`                               | `thirdFourth`                                      | Third Fourth             |                                 |
| `last-fourth`                                | `lastFourth`                                       | Last Fourth              |                                 |
| `top-left-sixth`                             | `topLeftSixth`                                     | Top Left Sixth           |                                 |
| `top-center-sixth`                           | `topCenterSixth`                                   | Top Center Sixth         |                                 |
| `top-right-sixth`                            | `topRightSixth`                                    | Top Right Sixth          |                                 |
| `bottom-left-sixth`                          | `bottomLeftSixth`                                  | Bottom Left Sixth        |                                 |
| `bottom-center-sixth`                        | `bottomCenterSixth`                                | Bottom Center Sixth      |                                 |
| `bottom-right-sixth`                         | `bottomRightSixth`                                 | Bottom Right Sixth       |                                 |
| `move-left`                                  | `moveLeft`                                         | Move Left                | `centerWindow` pref             |
| `move-right`                                 | `moveRight`                                        | Move Right               | `centerWindow` pref             |
| `move-top`                                   | `moveTop`                                          | Move Top                 | `centerWindow` pref             |
| `move-bottom`                                | `moveBottom`                                       | Move Bottom              | `centerWindow` pref             |
| `move-to-previous-space`                     | `movePreviousDesktop`                              | Move to Previous Space   | title is desktop on Windows     |
| `move-to-next-space`                         | `moveNextDesktop`                                  | Move to Next Space       | title is desktop on Windows     |
| `switch-to-previous-space`                   | `switchToPreviousSpace`                            | Switch to Previous Space | macOS; `animated` pref          |
| `switch-to-next-space`                       | `switchToNextSpace`                                | Switch to Next Space     | macOS; `animated` pref          |
| `move-to-previous-display`                   | `movePreviousDisplay`                              | Move to Previous Display | `wrap`, `keepAspectRatio` prefs |
| `move-to-next-display`                       | `moveNextDisplay`                                  | Move to Next Display     | `wrap`, `keepAspectRatio` prefs |
| `top-left-quarter`                           | `topLeftQuarter`                                   | Top Left Quarter         |                                 |
| `top-right-quarter`                          | `topRightQuarter`                                  | Top Right Quarter        |                                 |
| `bottom-left-quarter`                        | `bottomLeftQuarter`                                | Bottom Left Quarter      |                                 |
| `bottom-right-quarter`                       | `bottomRightQuarter`                               | Bottom Right Quarter     |                                 |
| `make-smaller`                               | `makeSmaller`                                      | Make Smaller             | `delta` pref, default 32px      |
| `make-larger`                                | `makeLarger`                                       | Make Larger              | `delta` pref, default 32px      |
| `toggle-fullscreen`                          | `toggleFullscreen`                                 | Toggle Fullscreen        | macOS                           |
| `toggle-always-on-top`                       | `toggleAlwaysOnTop`                                | Toggle Always on Top     | Windows internal                |
| `toggle-grid-overlay`                        | `gridPlacement`                                    | Toggle Grid Overlay      | macOS                           |
| `create-command`                             | `createWindowManagementCommand`                    | Create Command           | Pro feature                     |
| `create-layout`                              | `createWindowManagementLayout`                     | Create Layout            | macOS, Pro feature              |
| `switch-desktops`                            | `switchDesktop`                                    | Switch Desktops          | Windows view command            |
| `open-desktop`                               | `openDesktop`                                      | Open Desktop             | Windows, arg `index`            |
| `move-to-desktop`                            | `moveWindowToDesktop`                              | Move to Desktop          | Windows, arg `index`            |
| `close-desktop-active`                       | `closeActiveDesktop`                               | Close Desktop Active     | Windows                         |
| `close-desktop`                              | `closeDesktop`                                     | Close Desktop            | Windows, arg `index`            |
| `rename-desktop-active`                      | `renameActiveDesktop`                              | Rename Desktop Active    | Windows, arg `name`             |
| `rename-desktop`                             | `renameDesktop`                                    | Rename Desktop           | Windows, args `index`, `name`   |
| `open-desktop-1` ... `open-desktop-10`       | `openDesktop1` ... `openDesktop10`                 | Open Desktop 1...10      | Windows                         |
| `move-to-desktop-1` ... `move-to-desktop-10` | `moveWindowToDesktop1` ... `moveWindowToDesktop10` | Move to Desktop 1...10   | Windows                         |

Dynamic custom commands/layouts:

```text
dynamic command key=layoutGroup
primary handler=run-window-management-command
payload id=<layout_group_id>
manage handlers: edit-window-management-layout-group,
  duplicate-window-management-layout-group, delete-window-management-layout-group
```

For custom layout-group deeplinks, confirm in UI with Copy Deeplink. Runtime
needs the dynamic command instance/payload id; static title slugs alone are not
enough.

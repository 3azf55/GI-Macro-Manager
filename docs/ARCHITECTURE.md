# Architecture

## Components

### `UMM.Engine.ahk`

The AutoHotkey v1 engine owns:

- dynamic catalog loading;
- configurable global or game-window-scoped hotkey registration;
- Trigger down/up handling;
- child macro process lifecycle;
- input cleanup through `ReleaseAll()`;
- import analysis, stable package registration, and generated runners;
- export, deletion, and reordering;
- tray menu state;
- File Bridge commands and state.

It does not contain character-specific combo sequences.

### `UIHost`

A .NET 8 WinForms application hosting Microsoft Edge WebView2.

It loads the files under `UIHost/ui` and exchanges commands/state with the
engine through files under the runtime `bridge` folder.

Closing the management window hides the resident UI host instead of disposing it, so UI-owned background services remain active. The Interface shortcut (F11 by default) reuses that same process through the engine-owned window handle and a private `WM_APP` promotion message; the form is topmost only while focused and returns to normal z-order when the user switches back to the game. Engine exit and update installation still close and dispose the host normally.

`UIHost/FpsUnlockService.cs` owns the optional FPS target setting, game-process discovery, shared-memory state, and native hook lifecycle. Both the target and the user's enablement choice persist; a missing settings file defaults enablement to off. FPS commands remain inside the C# host and are not forwarded to the AutoHotkey engine.

`UIHost/FpsMonitorService.cs` owns the independent Show FPS setting at runtime. It starts the pinned PresentMon console collector only while enabled and a supported game process exists, parses displayed-frame CSV metrics into a rolling FPS value, and stops the collector when the game exits or the option is disabled. `UIHost/FpsOverlayForm.cs` draws that value in a tiny translucent, draggable, non-activating overlay that is visible only while the game is foreground, remains inside the game client area, and follows the WebView's light or dark theme immediately.

`UIHost/MacroEditorService.cs` owns visual macro generation and editing. Before invoking its event parser, it requires the exact visual-source marker emitted by the program. Imported, legacy, built-in, missing, or otherwise unknown AHK sources use a metadata-only session: the UI exposes name, description, and tags, while the service neither parses nor rewrites the AHK file. For program-created visual macros, saving validates the event model, checks that the source did not change while the editor was open, and atomically replaces the source, manifest, and registry metadata. The engine then reloads the catalog without restarting the UI.

`UIHost/KeyboardRecordingService.cs` installs low-level Windows keyboard and mouse hooks only while an editable visual-macro session is open. Its toggle key comes from the engine-owned Hotkeys configuration, so reserved keys, application duplicates, and per-macro trigger collisions are rejected centrally. It records supported key/button transitions and monotonic timestamps, ignores injected input and pointer coordinates, applies the configured rolling time window and key allowlist, and publishes snapshots directly to the trusted WebView. Its rounded, non-activating floating form stays visible while recording, auto-hides while idle, and reappears when the shortcut is used.

Optional `MacroTrigger` values are stored with macro metadata in the registry and portable manifest/export header. The engine rebuilds scoped down/up hotkey bindings after catalog changes and runs the linked macro directly while the assigned key remains held, without changing the selected character or macro.

### `FpsUnlocker`

The x64 `UnlockerStub` is built from source during Windows builds. After the user enables the feature, the C# host connects it to a supported game window and exchanges the enabled state and 10–420 FPS target through an application-specific shared-memory block. The component reports an error instead of writing when its game-version pattern cannot be resolved.

### `Macros`

`Macros/registry.ini` is the catalog. Macro source packages live under
`Macros/User`. Optional `Character.*` sections preserve character cards independently from `Combo.*` sections, allowing a character to remain visible with zero macros.

Each macro runs through a child AutoHotkey process, allowing the engine to stop
a stuck macro without exiting Macro Manager.

## Runtime flow

```text
Web UI
  ↓ command
UIHost / File Bridge
  ↓
UMM.Engine.ahk
  ↓ launch
Macro child process
```

On Trigger release, the engine terminates the active child process when needed
and runs input cleanup.

## Build output

`scripts/build-and-stage.ps1`:

1. builds the native x64 FPS component;
2. restores and publishes `UIHost`, including the pinned PresentMon binary and its notices;
3. copies `UMM.Engine.ahk`;
4. copies UI files, assets, and macros;
5. creates `bridge/commands`;
6. validates essential files, including `Native/UnlockerStub.dll` and `Native/PresentMon/PresentMon-2.5.1-x64.exe`;
7. moves the staged output to `dist`.


## GitHub update system

`UIHost/UpdateService.cs` handles the update lifecycle:

1. Query the latest stable GitHub Release.
2. Compare the release tag with the UI assembly version.
3. Select and download the complete Windows runtime ZIP.
4. Verify the optional SHA-256 digest and safely extract the archive.
5. Merge the installed macro registry with the release registry.
6. Start an external PowerShell installer after the UI and engine exit.
7. Build and validate a complete sibling installation directory.
8. Activate it through a same-volume directory rename; if Windows holds the root directory open, use a validated in-place content replacement backed by a complete rollback copy.
9. Restore the previous installation if either activation path fails.
10. Restart `UMM.Engine.ahk`; its guarded startup policy keeps the engine and UI at Administrator integrity.

The WebView2 About page communicates directly with the C# host for update actions; update commands are not forwarded to the AutoHotkey engine.

WebView commands pass through an explicit action/field allowlist. The C# line protocol normalizes control characters and enforces payload limits, while the engine independently rejects malformed or unsupported commands.

Visual-editor messages stay inside the trusted `https://app.umm/` WebView origin and are validated by `MacroEditorService`; nested event JSON is not forwarded through the line protocol. Metadata-only sessions ignore event payloads server-side. Generated AHK receives the performance header and precise-timer runtime automatically. Those implementation settings are intentionally absent from the visual interface.

## Source validation

`scripts/validate-source.ps1` validates version metadata, registry encoding and paths, exact asset filename casing, stable macro package names, duplicate AHK functions, and JavaScript syntax. GitHub runs it for pull requests and pushes to `main`.

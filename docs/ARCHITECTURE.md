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

`UIHost/FpsUnlockService.cs` owns the optional FPS limiter settings, game-process discovery, shared-memory state, and native hook lifecycle. FPS commands remain inside the C# host and are not forwarded to the AutoHotkey engine.

### `FpsUnlocker`

The x64 `UnlockerStub` is built from source during Windows builds. After the user enables the feature, the C# host connects it to a supported game window and exchanges the enabled state and 10–420 FPS target through an application-specific shared-memory block. The component reports an error instead of writing when its game-version pattern cannot be resolved.

### `Macros`

`Macros/registry.ini` is the catalog. Macro source packages live under
`Macros/User`.

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
2. restores and publishes `UIHost`;
3. copies `UMM.Engine.ahk`;
4. copies UI files, assets, and macros;
5. creates `bridge/commands`;
6. validates essential files, including `Native/UnlockerStub.dll`;
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
8. Activate it through a same-volume directory rename, restoring the previous directory if activation fails.
9. Restart `UMM.Engine.ahk`; its guarded startup policy keeps the engine and UI at Administrator integrity.

The WebView2 About page communicates directly with the C# host for update actions; update commands are not forwarded to the AutoHotkey engine.

WebView commands pass through an explicit action/field allowlist. The C# line protocol normalizes control characters and enforces payload limits, while the engine independently rejects malformed or unsupported commands.

## Source validation

`scripts/validate-source.ps1` validates version metadata, registry encoding and paths, exact asset filename casing, stable macro package names, duplicate AHK functions, and JavaScript syntax. GitHub runs it for pull requests and pushes to `main`.

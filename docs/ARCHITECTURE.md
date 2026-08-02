# Architecture

## Components

### `UMM.Engine.ahk`

The AutoHotkey v1 engine owns:

- dynamic catalog loading;
- managed hotkey registration;
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

1. restores and publishes `UIHost`;
2. copies `UMM.Engine.ahk`;
3. copies UI files, assets, and macros;
4. creates `bridge/commands`;
5. validates essential files;
6. moves the staged output to `dist`.


## GitHub update system

`UIHost/UpdateService.cs` handles the update lifecycle:

1. Query the latest stable GitHub Release.
2. Compare the release tag with the UI assembly version.
3. Select and download the complete Windows runtime ZIP.
4. Verify the optional SHA-256 digest and safely extract the archive.
5. Merge the installed macro registry with the release registry.
6. Start an external PowerShell installer after the UI and engine exit.
7. Replace runtime files and restart `UMM.Engine.ahk`.

The WebView2 About page communicates directly with the C# host for update actions; update commands are not forwarded to the AutoHotkey engine.

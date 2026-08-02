# Contributing

## Development requirements

- Windows 10/11
- AutoHotkey v1.1 Unicode
- .NET 8 SDK
- WebView2 Runtime
- Node.js

## Validate and build

Run source validation first:

```powershell
.\scripts\validate-source.ps1 -RequireNode
```

Then build the runtime package:

```bat
scripts\build-and-stage.cmd
```

The final runtime is created under `dist/`.

## Before submitting changes

1. Keep character and macro definitions out of `UMM.Engine.ahk`.
2. Store macro metadata in `Macros/registry.ini` and `manifest.ini`.
3. Use stable package names; do not add timestamped `user_*` folders.
4. Do not commit `dist`, `.publish-temp`, `bridge`, local settings, logs, or private macros.
5. Run source validation and the full build.
6. Test import, export, deletion, reordering, Trigger release, and `ReleaseAll()` when affected.
7. Test visible UI changes in dark and light themes.

## Pull requests

Keep each pull request focused on one feature or fix and describe:

- what changed;
- how it was tested;
- whether registry or settings migration is required;
- screenshots for visible UI changes.

The `Validate source` workflow must pass before a pull request is merged.

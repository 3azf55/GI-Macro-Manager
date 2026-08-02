# Contributing

## Development requirements

- Windows 10/11
- AutoHotkey v1.1 Unicode
- .NET 8 SDK
- WebView2 Runtime
- Node.js is optional and used only for JavaScript syntax checks

## Build

```bat
scripts\build-and-stage.cmd
```

The final runtime is created under `dist/`.

## Before submitting changes

1. Keep character and macro definitions out of `UMM.Engine.ahk`.
2. Store macro metadata in `Macros/registry.ini`.
3. Do not commit `dist`, `.publish-temp`, `bridge`, or local `settings.ini`.
4. Run:

```bat
scripts\build-and-stage.cmd
```

5. Check JavaScript syntax when Node.js is installed:

```bat
node --check UIHost\ui\app.js
```

6. Test import, export, deletion, reordering, Trigger release, and `ReleaseAll()` on Windows.

## Pull requests

Keep each pull request focused on one feature or fix and describe:

- what changed;
- how it was tested;
- whether registry or settings migration is required;
- screenshots for visible UI changes.

# GI Macro Manager

A Windows macro manager built with **AutoHotkey v1**, **C# WinForms**, and **WebView2**.

GI Macro Manager provides a modern interface for organizing, importing, running, exporting, deleting, and reordering macro packages. Characters and macros are loaded dynamically from the catalog rather than being hard-coded into the engine.

## Features

- Modern WebView2 interface with dark and light themes
- Dynamic character and macro catalog
- Separate AutoHotkey process for each running macro
- One-click AutoHotkey v1 import with comment metadata, filename fallback, hotkey, `RunMacro()`, and auto-execute detection
- Stable package names for imported macros
- Editable macro names, descriptions, FPS tags, and TESTING tags
- Add, export, delete, and reorder macro packages
- Configurable, conflict-checked hotkeys active only while the selected game window is focused
- Skip Dialogs mode and optional game launcher
- GitHub release checks with download and installation support
- System tray controls and Discord community access

## Requirements

### To run

- Windows 10 or Windows 11
- AutoHotkey **v1.1 Unicode**
- Microsoft Edge WebView2 Runtime

> AutoHotkey v2 scripts are not supported by the current import engine.

### To build from source

- .NET 8 SDK
- AutoHotkey **v1.1 Unicode**
- Microsoft Edge WebView2 Runtime
- Node.js for source validation

## Download

Prebuilt versions are published on the repository's [Releases page](https://github.com/3azf55/GI-Macro-Manager/releases).

After downloading a release:

1. Extract the archive.
2. Make sure AutoHotkey v1.1 is installed.
3. Run `UMM.Engine.ahk`.

## Build from Source

```bat
scripts\build-and-stage.cmd
```

The completed runtime package is created in `dist\`. Start it with:

```text
dist\UMM.Engine.ahk
```

Validate the source before submitting changes:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-source.ps1 -RequireNode
```

## Macro Packages

Macro packages are stored under:

```text
Macros\User\<Character>\<Macro>\
```

A typical package contains `manifest.ini` and `source.ahk`. Catalog information, script paths, tags, and display order are stored in `Macros\registry.ini`.

See [Macro Packages](docs/MACRO_PACKAGES.md) for the package format and import behavior.

## Project Structure

```text
.
├── UMM.Engine.ahk
├── UIHost/
├── Macros/
├── Assets/
├── scripts/
└── docs/
```

For a technical overview, see [Architecture](docs/ARCHITECTURE.md).

## Security

Imported AutoHotkey files are executable scripts. Macro Manager requests Administrator permission at startup, so imported macros inherit elevated access. Only import scripts from sources you trust and review their contents before running them.

The engine performs one guarded UAC relaunch so it can interact consistently with games running at elevated integrity. If elevation is denied or still unavailable after the guarded restart, Macro Manager exits instead of relaunching repeatedly.

Read the full [Security Policy](SECURITY.md).

## Contributing

Contributions and bug reports are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes. Pull requests are validated automatically by GitHub Actions.

## Credits

Macro timing references are listed in [Macro Timing Credits](docs/MACRO_CREDITS.md).

## Community

- GitHub: https://github.com/3azf55/GI-Macro-Manager
- Discord: https://discord.gg/H8HNhvqqm

## License

The original source code of GI Macro Manager is licensed under the [MIT License](LICENSE).

Third-party fonts, libraries, images, sounds, macro timing references, and other external assets remain subject to their respective licenses and ownership. See [Third-Party Notices](THIRD_PARTY_NOTICES.md) and [Macro Timing Credits](docs/MACRO_CREDITS.md).

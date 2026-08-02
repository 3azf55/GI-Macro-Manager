# GI Macro Manager

A Windows macro manager built with **AutoHotkey v1**, **C# WinForms**, and **WebView2**.

GI Macro Manager provides a modern interface for organizing, importing, running, exporting, deleting, and reordering macros. Character and macro definitions are loaded dynamically from the project catalog rather than being hard-coded in the engine.

## Features

- Modern WebView2 interface with dark and light themes
- Dynamic character and macro catalog
- Separate AutoHotkey process for each running macro
- Import support for AutoHotkey v1 scripts
- Automatic detection of a script's first standard hotkey
- Support for `RunMacro()` and auto-execute scripts
- Stable package names and registry IDs for imported macros
- Portable package manifests that preserve names, tooltips, and tags
- Add, export, delete, and reorder macro packages
- Configurable trigger and navigation hotkeys
- Skip Dialogs mode
- Optional game executable shortcut from the dashboard
- System tray controls
- GitHub release update checks with in-app download and installation

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

## Download

Prebuilt versions are published on the repository's [Releases page](https://github.com/3azf55/GI-Macro-Manager/releases).

After downloading a release:

1. Extract the archive.
2. Make sure AutoHotkey v1.1 is installed.
3. Run `UMM.Engine.ahk`.

The engine starts the WebView2 interface automatically.

## Build from Source

Clone the repository and run the build script from the project root:

```bat
scripts\build-and-stage.cmd
```

PowerShell can also be used directly:

```powershell
.\scripts\build-and-stage.ps1
```

The completed runtime package is created in:

```text
dist\
```

Start the built application with:

```text
dist\UMM.Engine.ahk
```

## Using Macro Manager

### Select and run a macro

1. Choose a character.
2. Select a macro.
3. Hold the configured trigger key to run it.
4. Release the trigger to stop it.

### Reorder macros

Press and hold a macro card, drag it to the desired position, and release it. The new order is saved in `Macros/registry.ini`.

### Import a macro

Use **Add Macro** from the selected character panel and choose an AutoHotkey v1 file.

The importer supports:

1. A standard hotkey detected in the script
2. A `RunMacro()` function
3. An auto-execute section

Imported packages receive a stable folder and registry ID derived from the character and macro name. Timestamps are not used. A complete `manifest.ini` is written so the package can be moved between project trees without losing its display metadata.

Scripts that depend on additional includes, DLLs, configuration files, images, or other assets must keep those dependencies available.

### Check for updates

The About page can check the latest stable GitHub Release. When a compatible runtime ZIP is available, Macro Manager can download it, preserve user settings and custom macro packages, install the update, and restart.

## Macro Packages

Macro packages are stored under:

```text
Macros\User\<Character>\<StablePackageName>\
```

A managed package contains:

```text
manifest.ini
source.ahk
run.ahk
```

Catalog information, script paths, tags, and display order are stored in:

```text
Macros\registry.ini
```

A source-only folder is not registered automatically. Package recovery requires an explicit manifest. See [Macro Packages](docs/MACRO_PACKAGES.md) for the package format and import behavior.

## Project Structure

```text
.
├── UMM.Engine.ahk
├── UIHost/
│   ├── UMM.UI.csproj
│   ├── MainForm.cs
│   ├── UpdateService.cs
│   └── ui/
├── Macros/
│   ├── registry.ini
│   ├── Runtime/
│   └── User/
├── Assets/
├── scripts/
└── docs/
```

For a technical overview, see [Architecture](docs/ARCHITECTURE.md).

## Security

Imported AutoHotkey files are executable scripts and run with the current Windows user's permissions. Only import scripts from sources you trust and review their contents before running them.

Read the full [Security Policy](SECURITY.md).

## Credits

Macro timing credits are maintained in [Macro Credits](docs/MACRO_CREDITS.md).

## Contributing

Contributions and bug reports are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes.

## Third-Party Licenses

Open Sans is licensed under the SIL Open Font License 1.1. See [Third-Party Notices](THIRD_PARTY_NOTICES.md).

## Community

- GitHub: https://github.com/3azf55/GI-Macro-Manager
- Discord: https://discord.gg/H8HNhvqqm

## License

The original source code of GI Macro Manager is licensed under the
[MIT License](LICENSE).

Third-party fonts, libraries, images, sounds, macro timing references,
and other external assets remain subject to their respective licenses
and ownership. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
and [Macro Timing Credits](docs/MACRO_CREDITS.md).

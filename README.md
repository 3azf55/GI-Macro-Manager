# GI Macro Manager

A Windows macro manager built with **AutoHotkey v1**, **C# WinForms**, and **WebView2**.

GI Macro Manager provides a modern interface for organizing, importing, running, exporting, and deleting macros.

## Features

- Modern WebView2 interface with dark and light themes
- Dynamic character and macro catalog
- Separate AutoHotkey process for each running macro
- Import support for AutoHotkey v1 scripts
- Automatic detection of a script's first standard hotkey
- Support for `RunMacro()` and auto-execute scripts
- Add, export, and delete macro packages
- Reorder macros by pressing and holding a macro card, then dragging it
- Configurable trigger and navigation hotkeys
- Skip Dialogs mode
- Optional game executable shortcut from the dashboard
- System tray controls

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

### Import a macro

Use **Add Macro** from the selected character panel and choose an AutoHotkey v1 file.

The importer supports:

1. A standard hotkey detected in the script
2. A `RunMacro()` function
3. An auto-execute section

Scripts that depend on additional includes, DLLs, configuration files, images, or other assets must keep those dependencies available.

### Start the game

The dashboard can store a game executable path. If no path is configured, pressing **Start Game** opens the executable browser and saves the selected path.

## Macro Packages

Macro packages are stored under:

```text
Macros\User\<Character>\<Macro>\
```

A typical package contains:

```text
manifest.ini
source.ahk
```

Catalog information, script paths, and display order are stored in:

```text
Macros\registry.ini
```

See [Macro Packages](docs/MACRO_PACKAGES.md) for the package format and import behavior.

## Project Structure

```text
.
├── UMM.Engine.ahk
├── UIHost/
│   ├── UMM.UI.csproj
│   ├── MainForm.cs
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

## Contributing

Contributions and bug reports are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes.

## Community

Join the Discord server:

https://discord.gg/H8HNhvqqm

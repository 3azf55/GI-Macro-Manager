# GI Macro Manager

A Windows macro manager built with **AutoHotkey v1**, **C# WinForms**, and **WebView2**.

GI Macro Manager provides a modern interface for organizing, importing, running, exporting, deleting, and reordering macro packages. Characters and macros are loaded dynamically from the catalog rather than being hard-coded into the engine.

## Features

- Modern WebView2 interface with dark and light themes
- Separate AutoHotkey process for each running macro
- Create, import, record, and visually edit advanced AutoHotkey macros without coding
- Configurable, conflict-checked gameplay hotkeys
- Startup: Additional DLLs allows adding and managing extra DLL files, which are loaded in the order shown in the list
- Optional 10–420 FPS limiter with presets and live connection status
- Optional Show FPS monitor powered by PresentMon
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
- Visual Studio 2022 with the **Desktop development with C++** workload and x64 tools

## Download

Prebuilt versions are published on the repository's [Releases page](https://github.com/3azf55/GI-Macro-Manager/releases).

After downloading a release:

1. Extract the archive.
2. Make sure AutoHotkey v1.1 is installed.
3. Run `UMM.Engine.ahk`.

On the first launch, Macro Manager verifies that AutoHotkey v1.1 is available. A valid installation produces no message; a missing installation produces one warning with the official download link.

## Build from Source

```bat
scripts\build-and-stage.cmd
```

The build script compiles the native x64 FPS component from source, packages the pinned PresentMon console binary and its notices, then publishes the WebView2 host.

The completed runtime package is created in `dist\`. Start it with:

```text
dist\UMM.Engine.ahk
```

The window close action keeps the UI host resident for Show FPS and F11. Before
rebuilding or replacing `dist`, choose **Exit** from the Macro Manager tray menu
so `UMM.UI.exe`, WebView2, PresentMon, and the AutoHotkey engine release their
runtime files.

Validate the source before submitting changes:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-source.ps1 -RequireNode
```

## Interface Hotkey

The default **Interface** shortcut is **F11**. It opens the existing manager window above the game. Change it from **Hotkeys > Interface**; **Reset defaults** restores F11 together with the other default shortcuts.

Updating preserves saved hotkeys. If your installation still uses Insert, change **Interface** to **F11** on the Hotkeys page. If F11 is already assigned to another action or custom macro, resolve that conflict first.

## Macro Packages

Macro packages are stored under:

```text
Macros\User\<Character>\<Macro>\
```

A typical package contains `manifest.ini` and `source.ahk`. Catalog information, script paths, tags, and display order are stored in `Macros\registry.ini`.

Macros for one character may share a display name when their description or tags differ. The catalog rejects only an identical name, description, and tag combination.

See [Macro Packages](docs/MACRO_PACKAGES.md) for the package format and import behavior.

## Character Catalog

Character availability is controlled by the developer rather than runtime UI controls. Add one line to `Assets/characters.txt` using:

```text
Character name|Portrait filename|Taskbar icon filename
```

The corresponding portrait and icon must already exist under `Assets/portraits` and `Assets/icons`. Every valid entry appears automatically after Macro Manager restarts; users cannot add or remove character cards from the interface.

## Project Structure

```text
.
├── UMM.Engine.ahk
├── UIHost/
├── FpsUnlocker/
├── PresentMon/
├── Macros/
├── Assets/
├── scripts/
└── docs/
```

For a technical overview, see [Architecture](docs/ARCHITECTURE.md).

## Security

Imported AutoHotkey files are executable scripts. Macro Manager requests Administrator permission at startup, so imported macros inherit elevated access. Only import scripts from sources you trust and review their contents before running them.

The optional FPS limiter loads a native component into the game process and writes the selected frame-rate target in memory. It is disabled on the first launch and remembers later user changes, may stop working after game updates, and must not be treated as risk-free or officially supported by the game publisher.

Show FPS is a separate read-only feature. It starts the bundled PresentMon collector only while enabled and the game is running, then displays measured presentation FPS over a focused windowed or borderless game. It does not require the FPS limiter to be enabled. Exclusive fullscreen can prevent a separate WinForms overlay from being visible.

The engine performs one guarded UAC relaunch so it can interact consistently with games running at elevated integrity. If elevation is denied or still unavailable after the guarded restart, Macro Manager exits instead of relaunching repeatedly.

Read the full [Security Policy](SECURITY.md).

## Contributing

Contributions and bug reports are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes. Pull requests are validated automatically by GitHub Actions.

## Credits

Macro timing references are listed in [Macro Timing Credits](docs/MACRO_CREDITS.md).

The FPS limiter is adapted from [PowerPaimon](https://github.com/catteol/PowerPaimon) at commit `09eddc6393714900cca0fb55bb83cb490acf09b8`. Its MIT license is preserved under `FpsUnlocker/LICENSE-UPSTREAM.txt`.

FPS measurement uses the official [PresentMon](https://github.com/GameTechDev/PresentMon) 2.5.1 x64 console build. Its MIT license and third-party notices are preserved under `PresentMon/` and copied beside the packaged executable.

## Community

- GitHub: https://github.com/3azf55/GI-Macro-Manager
- Discord: https://discord.gg/cm3jkdkWAp

## License

The original source code of GI Macro Manager is licensed under the [MIT License](LICENSE).

Third-party fonts, libraries, images, sounds, macro timing references, and other external assets remain subject to their respective licenses and ownership. See [Third-Party Notices](THIRD_PARTY_NOTICES.md) and [Macro Timing Credits](docs/MACRO_CREDITS.md).

# Changelog

## v1.7.5

- Added a Hotkeys activation scope with `Everywhere` and `Game only` modes; existing installations default to `Game only`.
- Removed the global macro ON/OFF control from the application, runtime settings, and tray menu.
- Added an optional FPS limiter with a 10–420 FPS range, presets, saved settings, and live connection status, using a native component adapted from PowerPaimon.
- Refined the Hotkeys and FPS layouts with balanced scope controls, a compact slider, consistent card hover behavior, and a concise risk tooltip.
- Made the taskbar icon update automatically to match the selected character, using the `.ico` files in `Assets\icons`.
- Reworked macro importing to read names, descriptions, and tags from AHK comment metadata, generate safe fallback names, and handle duplicates automatically.
- Added editing for imported macro names, descriptions, FPS tags, and TESTING tags while preserving stable macro IDs and package folders.
- Reorganized the Dashboard by integrating Quick Controls, Application Mode, and Skip Dialog Behavior into the selected Character Combos card.
- Improved character and macro card sizing for a cleaner responsive desktop layout.

## v1.7.4

- Added an in-app startup update prompt with `Update now` and `Remind me later` actions.
- Made the borderless application window resizable and preserved its position and dimensions.
- Converted the main content areas into responsive card grids and improved interface transitions and visual hierarchy.

## v1.7.2

- Fixed all interface actions being rejected by an invalid AutoHotkey v1 NUL-character check while preserving raw-byte validation for command files.

## v1.7.1

- Fixed valid UI bridge commands being rejected at startup and added UTF-8 BOM compatibility.
- Prevented repeated engine errors from creating endless notification loops.
- Restored reliable Administrator relaunch through UAC without repeated elevation attempts.

## v1.7.0

- Scoped managed hotkeys to the selected game executable and stopped active input when the game loses focus.
- Replaced in-place updates with a validated staged update process with rollback support.
- Strengthened command validation with an allowlist, payload limits, and centralized protocol normalization.
- Preserved inherited FPS and TESTING tags during macro export and import.
- Made macro reordering atomic and prevented deletion of a character's last macro.

## v1.6.6

- Reserved the `S` gameplay key from application hotkey assignment.
- Added centralized hotkey validation, duplicate detection, and automatic recovery from invalid saved settings.
- Displayed GitHub release notes safely inside the update card.

## v1.6.5

- Replaced timestamp-based imported macro IDs and folders with stable names.
- Limited automatic package recovery to complete packages containing a valid manifest.
- Hardened release packaging and added SHA-256 verification.

## v1.6.4

- Preserved FPS and TESTING tags when recovering or re-importing macro packages.
- Added versioned metadata markers to exported AHK files.

## v1.6.3

- Added automatic recovery for unregistered imported macro packages.
- Added a portable `manifest.ini` file to imported macros.

## v1.6.1

- Fixed the first macro being skipped when `Macros/registry.ini` starts with a UTF-8 BOM.
- Restored reliable loading of Mavuika's `CD 3[CDC2FD] (C)` macro.

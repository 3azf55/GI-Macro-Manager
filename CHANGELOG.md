# Changelog

## v1.6.6

- Reserved the missing `S` gameplay key from application hotkey assignment.
- Centralized hotkey-set validation and atomic startup recovery for invalid or duplicated settings.
- Added defensive duplicate checks inside every hotkey setter.
- Corrected the exact filename case for `OpenSans-Semibold.ttf`.
- Removed unused child-runtime timing and input helpers from `UMM.Engine.ahk`.
- Initialized `FState` consistently in the child runtime.
- Displayed GitHub release notes in the update card as safe plain text.
- Converted source `build-info.json` into a date-free version template.
- Added pull-request source validation and .NET build CI.
- Added the MIT license and cumulative Discord release workflow.

## v1.6.5

- Replaced timestamped imported macro IDs and folders with stable names.
- Limited automatic package recovery to complete manifest-backed packages.
- Removed the stale repository inventory document.
- Reworded historical CSS comments to describe current behavior.
- Added the Open Sans SIL Open Font License and third-party notice.
- Expanded GitHub issue and pull request templates.
- Hardened the release workflow with manual dispatch, concurrency control, exact action versions, package verification, and SHA-256 checksums.

## v1.6.4

- Preserved FPS and TESTING tags when recovering copied macro packages from `manifest.ini`.
- Preserved exported macro metadata when an exported AHK file is imported again.
- Added a versioned metadata marker to future AHK exports.
- Replaced the glow/tilt reorder effect with a press, spring-lift, and soft landing animation.

## v1.6.3

- Removed the long-press loading/progress line from macro cards.
- Added a smooth lift, glow, responsive tilt, and drag/drop animation.
- Added automatic recovery for unregistered `user_*` imported macro folders.
- Imported macros now receive a portable `manifest.ini` file.

## v1.6.2

- Added a smooth long-press progress animation before macro reordering starts.
- Added a lifted drag state and a soft drop animation for the active macro card.
- Added FLIP-based motion so neighboring macro cards slide into their new positions instead of jumping.
- Added reduced-motion support for the reorder interaction.

## v1.6.1

- Fixed the first macro entry being skipped when `Macros/registry.ini` starts with an UTF-8 BOM.
- Added automatic BOM removal before AutoHotkey v1 reads the registry.
- Normalized the staged registry to UTF-8 without BOM during every build.
- Restored reliable loading of Mavuika's `CD 3[CDC2FD] (C)` macro.

## v1.5.2

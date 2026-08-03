# Changelog

## Unreleased

- Changed Add macro to Import macro and removed the metadata form and trust confirmation from the import flow.
- Import names, descriptions, and tags from leading AHK comment metadata, with a filename-based name fallback and automatic duplicate suffixes.
- Added editing for existing macro names, descriptions, FPS tags, and TESTING tags while preserving stable macro IDs and package folders.
- Removed macro-card hover tooltips, empty Select this macro placeholders, and character macro-count labels.
- Updated character cards for square 256 x 256 portraits and removed the press-stage transform that caused macro cards to shake during normal selection.
- Reorganized the Dashboard with Application Mode inside the selected Character Combos card and a square Quick Controls card.
- Expanded the Character Combos card to embed square Quick Controls in its upper-right area and place equal-sized Application Mode and Skip Dialog Behavior controls in its bottom row.
- Moved Sound Feedback beside the compact icon-only theme control in the sidebar.
- Reduced the spacing in the Trigger release / Any key selector.
- Reduced character-card sizing to four cards per desktop row and stabilized Hotkey-card DOM and hover rendering to prevent repeated pointer jitter.

## v1.7.4

- Added animated section transitions while preserving the reduced-motion preference.
- Added an in-app startup update prompt with Update now and Remind me later actions.
- Made the borderless application window resizable and persisted its position and dimensions.
- Converted character, macro, hotkey, community, and update content into responsive card grids.
- Strengthened typography hierarchy, rounded inputs and data containers, and added subtle hover transitions and shadows.
- Made Administrator-policy source validation independent of Windows CRLF line endings.
- Added clear retry handling when a running process temporarily locks the staged build folders.

## v1.7.3

- Added a one-time staggered entrance animation for the title bar, sidebar, and main content.
- Preserved `prefers-reduced-motion` behavior for the startup animation.

## v1.7.2

- Fixed every interface action being rejected by removing an AutoHotkey v1 text-level NUL check that treated `Chr(0)` as an empty search value.
- Kept NUL-byte protection by validating command files as raw bytes before decoding them as UTF-8.
- Added source-validation guards so CI rejects the broken text-level NUL pattern if it is reintroduced.

## v1.7.1

- Fixed valid UI bridge commands being rejected on startup by replacing the AutoHotkey v1 control-character regex with a deterministic character check and tolerating UTF-8 BOM input.
- Prevented engine errors from creating an endless `error -> requestState -> error` notification loop.
- Added stable error IDs, duplicate-toast suppression, a state-request cooldown, and a cap on simultaneously visible notifications.
- Restored forced Administrator relaunch through UAC with a `/restart` guard that prevents repeated elevation attempts.

## v1.7.0

- Added a smooth, reduced-motion-aware transition between dark and light themes.
- Scoped all managed hotkeys to the selected game executable and stop active input when the game loses focus.
- Removed automatic Administrator elevation from the engine and bundled Skirk macro.
- Replaced in-place updater copying with a validated staged directory swap and rollback.
- Added a global command allowlist, payload limits, and centralized line-protocol normalization.
- Made exported FPS and TESTING tags inherit automatically unless the importer explicitly selects None.
- Made macro reordering a single atomic registry update and forced the UI to accept the engine result after rollback.
- Prevented deletion of the last macro for each character in both the UI and engine.
- Removed unused bridge, engine, and JavaScript helpers and synchronized every inlined runtime copy.
- Consolidated Discord release notification into the release workflow and expanded CI consistency checks.

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

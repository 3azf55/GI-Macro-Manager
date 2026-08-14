# Changelog

## v1.7.6

- Added subtle `scale(0.98)` press feedback to combo cards and hotkey buttons, with reduced-motion support.
- Added lightweight insertion and FLIP reordering animations to the visual macro timeline, including moves into and out of loops.

## v1.7.5

- Added the complete visual macro editor: creation and safe editing, nested/foldable loops, grouped steps, duration totals, duplication, Clear all, multi-selection, cross-loop dragging, undo/redo, and consistent event styling.
- Added `Test changes`, which temporarily arms the unsaved macro for its trigger without saving, plus optional per-macro triggers with validation and persistence.
- Added keyboard and mouse-button recording with exact delays, a themed floating control, last-N-seconds capture, an allowed-key filter, and a configurable Hotkeys shortcut.
- Protected imported and unknown AHK sources with metadata-only editing, while managed visual macros use atomic saves, conflict checks, high-resolution timing, and maximum-speed input settings.
- Improved import/export metadata, stable IDs and folders, duplicate handling, stale-header cleanup, package recovery, and reliable atomic macro ordering.
- Added the Hotkeys `Everywhere` / `Game only` scope, the global `F11` Interface shortcut, shared key-conflict rules, and temporary topmost behavior only while needed.
- Added the optional 10–420 FPS limiter with presets, persistence, connection status, a responsive layout, and a concise compatibility-risk tooltip.
- Rebuilt Characters and Combos with responsive cards, drag reordering, monospaced combo commands, consistent outlined selection, and deletion of a character's final macro without removing its card.
- Rebuilt the macro action toolbar with accessible SVG icons, distinct Import/Export actions, and an isolated destructive Delete action.
- Refined create/edit metadata with consistent `(Optional)` labels, a compact FPS/Test row, a smaller `Test` badge, and readable warnings in both themes.
- Improved the Dashboard, light/dark styling, sidebar preference controls, character-sized taskbar icons, maximized-window layouts, and window maximize/restore behavior.
- Removed the global macro ON/OFF state and simplified timeline, details, and Hotkeys microcopy.
- Added the AutoHotkey v1.1 prerequisite check and hardened automatic updates with validated in-place fallback and rollback protection.

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

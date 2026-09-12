# Changelog

## v1.7.7

- Added new charcter "Nefer" in the options.
- Added an optional Show FPS monitor powered by the official PresentMon 2.5.1 x64 console build, with persisted state and live measured-FPS feedback.
- Added PowerPaimon-based **Additional DLLs** on Startup
- Added an in-app warning before leaving a new or edited macro with unsaved changes.
- Updated the Discord community invite.

## v1.7.6

- Added the complete visual macro editor: creation and safe editing, nested/foldable loops, grouped steps, duration totals, duplication, Clear all, multi-selection, cross-loop dragging, undo/redo, and consistent event styling.
- Added Test changes, which temporarily arms the unsaved macro for its trigger without saving, plus optional per-macro triggers with validation and persistence.
- Added keyboard and mouse-button recording with exact delays, a themed floating control, last-N-seconds capture, an allowed-key filter, and a configurable Hotkeys shortcut.

## v1.7.5

- Added the complete visual macro editor with creation, safe editing, nested loops, grouped steps, duration totals, duplication, multi-selection, cross-loop dragging, and undo/redo.
- Added `Test changes`, which temporarily arms the unsaved macro for its trigger without saving, plus optional per-macro triggers with validation and persistence.
- Added keyboard and mouse-button recording with exact delays, last-N-seconds capture, key filtering, and a configurable shortcut.
- Protected imported and unknown AHK sources with metadata-only editing, while managed visual macros use atomic saves, conflict checks, high-resolution timing, and maximum-speed input settings.
- Added the Hotkeys `Everywhere` / `Game only` scope, the global `F11` Interface shortcut, shared key-conflict rules, and temporary topmost behavior only while needed.
- Added the optional 10–420 FPS limiter with presets, persistence, and live connection status.
- Added the AutoHotkey v1.1 prerequisite check and hardened automatic updates with validated in-place fallback and rollback protection.

## v1.7.4

- Added an in-app startup update prompt with `Update now` and `Remind me later` actions.
- Made the borderless application window resizable and preserved its position and dimensions.

## v1.7.0

- Scoped managed hotkeys to the selected game executable and stopped active input when the game loses focus.
- Replaced in-place updates with a validated staged update process with rollback support.
- Strengthened command validation with an allowlist, payload limits, and centralized protocol normalization.
- Preserved inherited FPS and TESTING tags during macro export and import.

## v1.6.5

- Introduced stable imported-macro package identities, validated package recovery, and SHA-256 release verification.

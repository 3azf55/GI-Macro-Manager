# Changelog

## v1.6.4

- Preserved FPS and TESTING tags when recovering copied macro packages from `manifest.ini`.
- Preserved exported macro metadata when an exported AHK file is imported again.
- Added a versioned metadata marker to future AHK exports.
- Replaced the glow/tilt reorder effect with a press, spring-lift, and soft landing animation.

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
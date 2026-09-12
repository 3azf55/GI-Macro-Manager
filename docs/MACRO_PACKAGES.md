# Macro Packages

## Directory structure

```text
Macros/
├── registry.ini
├── Runtime/
│   └── MacroRuntime.ahk
└── User/
    └── <Character>/
        └── <StablePackageName>/
            ├── manifest.ini
            ├── source.ahk
            └── run.ahk       generated for imported scripts
```

## Stable package identity

A macro imported through the application receives a stable identity derived from its character and display name. Timestamps are not used.

Example:

```text
Character: Skirk
Macro name: 9N2 2N5 N3
Folder: Macros\User\Skirk\9N2_2N5_N3
Registry ID: Skirk_9N2_2N5_N3
```

If an internal ID or folder collision remains after the user chooses a unique display name, Macro Manager appends a numeric suffix such as `_2` to the package identity. The chosen ID and folder remain unchanged afterward. Registered legacy imports that still use a timestamped `user_*` identity are normalized automatically at startup.

## Registry entry

```ini
[Combo.Example_Hero_Example_combo]
Id=Example_Hero_Example_combo
Character=Example Hero
Image=Example Hero.png
Name=Example combo
Tooltip=Optional description
Tag=120 FPS, TESTING
Script=Macros\User\Example_Hero\Example_combo\run.ahk
BuiltIn=0
Order=10
```

`Order` controls display order, combo cycling, and the Tray menu.

Character cards do not depend on macro or registry entries. The developer controls them through `Assets\characters.txt`:

```text
Character name|Portrait filename|Taskbar icon filename
```

Every valid line appears automatically, even when the character has no macros. The referenced portrait and icon must already exist under `Assets\portraits` and `Assets\icons`. Runtime users cannot add or remove character cards.

## Package manifest

Every managed package includes `manifest.ini`:

```ini
[Macro]
Id=Example_Hero_Example_combo
Character=Example Hero
Image=Example Hero.png
Name=Example combo
Tooltip=Optional description
Tag=120 FPS, TESTING
Source=source.ahk
ManagedPackage=1
PackageFormat=2
Version=2
```

The manifest makes the package portable and distinguishes an intentional macro package from an arbitrary folder containing executable code. New visual macros also receive `EditorFormat=VisualMacroV1`; imported packages do not.

## Import behavior

Selecting **Import macro** opens the AHK file picker directly. The importer does not display a separate metadata form. It copies the selected file to `source.ahk`, writes the manifest and registry entry, and creates `run.ahk` when required.

The importer reads optional metadata from the leading comment block. `Name` and `Macro`, `Description` and `Tooltip`, and `Tags` and `Tag` are accepted aliases:

```ahk
; Name: Example combo
; Description: Optional description shown below the macro name
; Tags: 120 FPS, TESTING
```

If no explicit name is present, the importer derives a readable name from the `.ahk` filename. The compact in-app conflict dialog appears only when another macro for the selected character has the same name, description, and normalized tags. A shared name alone is allowed when the description or tags differ. The dialog offers three actions: replace the existing macro, enter a different name, or cancel. It does not use native Windows message or input boxes. Replacement keeps the existing ID, display order, and package location; prepares the new package before activation; and restores the original package and registry if activation fails. A plain AHK replacement also preserves description, tags, and custom trigger values that were not explicitly supplied by the incoming file. Built-in macros cannot be replaced. Invalid or unsupported metadata is ignored safely.

It classifies the script as:

- `AutoTrigger`: a hotkey was detected and converted into a generated entry;
- `RunMacro`: the file exposes `RunMacro()`;
- `AutoExecute`: no hotkey or `RunMacro()` was detected.

AutoHotkey v2 files explicitly declaring `#Requires AutoHotkey v2` are rejected.

## Visual creation and editing

Selecting **Create macro** opens the visual timeline with starter input and delay events. A visual macro can contain:

- keyboard or mouse tap, down, and up events;
- precise millisecond delays;
- finite loops or loops that continue until the Trigger is released;
- nested loops up to four levels;
- readable notes.

Events can be dragged between the root timeline and loop bodies as well as reordered within one container. The editor rejects a drop that would place a loop inside itself or exceed four nested loop levels. Duplicate creates an independent copy with fresh event IDs, including every child of a duplicated loop.

The input recorder captures supported keyboard keys, mouse buttons, wheel direction, and the delay between transitions while ignoring pointer coordinates. It can retain only the most recent configurable number of seconds, restrict capture to selected keys, and start or stop from its rounded floating control or the conflict-checked Recorder shortcut on the Hotkeys page. The shortcut is active only while an editable visual-macro page for a character is open. Recorded transitions appear live in the timeline and are saved through the same validated event model.

Each macro can also define an optional `MacroTrigger`. The key must not collide with application Hotkeys or another macro trigger. It is stored in `registry.ini`, `manifest.ini`, and managed export headers so the engine can bind it directly to that macro after the catalog is reloaded. The binding executes only while the character that owns the macro is selected.

The timeline groups consecutive simple events into compact step blocks, displays the configured total duration from the first event through the last, and recalculates it immediately as timing or loop counts change. A release-controlled loop is labeled as indefinite.

Saving a new timeline creates a complete stable package with `manifest.ini`, `source.ahk`, a visual-source marker, and a registry entry. The edit action exposes the timeline only when that exact program-generated marker is present. This prevents the editor from attempting to interpret arbitrary AHK layouts through one rewriting model.

Imported, built-in, legacy, and otherwise unknown macros open in metadata-only mode. Only the name, description, FPS tag, TESTING tag, and optional macro trigger are editable; their AHK source is not parsed or rewritten. For visual macros, an edited source file is replaced atomically only after the service verifies that it has not changed since the editor opened. Metadata is updated in the registry and existing package manifest in the same save operation. The engine reloads the catalog and selects the saved macro afterward.

Every AHK file generated by Macro Manager receives the non-interactive maximum-speed input settings automatically. Visual macros also use `MacroRuntime.ahk` for high-resolution timing and guaranteed input release. These implementation details are not presented as user settings in the interface.

## Package recovery

At startup, Macro Manager can recover a complete package that is present under `Macros/User/<Character>` but missing from `registry.ini`.

Recovery requires both:

```text
manifest.ini
source.ahk
```

A source-only folder is ignored and is never published automatically. Recovered packages receive a stable folder and registry ID, and their runner is regenerated using that ID.

## Trigger compatibility

For AutoTrigger scripts, generated runners can redirect function-style calls such as:

```ahk
GetKeyState(HoldKey, "P")
```

When `HoldKey` refers to the detected original trigger, the generated runner reports it as held while the child process is alive. Macro Manager remains responsible for terminating the process when its configured Trigger is released.

The legacy command form and every possible custom input implementation are not universally transformable.

## Portable display metadata

Macro Manager preserves `Name`, `Tooltip`, and `Tag` when a package is copied between project trees. `Tooltip` remains the compatibility key in registry and manifest files, but the interface presents it as the macro description. Recovery reads these fields from `manifest.ini`. Import also reads equivalent metadata from the leading AHK comment block.

Supported `Tag` values are:

```text
60 FPS
120 FPS
240 FPS
TESTING
```

One FPS tag and the `TESTING` tag can be combined, for example `120 FPS, TESTING`. Existing macros can be edited from the character page. Editing updates the registry and package manifest together while keeping the macro ID and folder stable.

Export writes one fresh metadata header from the current catalog values and removes older managed export headers embedded in an imported source. Import treats the first metadata header as authoritative, so an edited name, description, or tag survives an export/import round trip.

Reordering rewrites each selected character package's `Order` value in `registry.ini`. If an otherwise valid manually edited entry has no `Order` key, the manager adds it automatically; key casing and surrounding whitespace are normalized during the save.

## External dependencies

Import centers on the selected AHK file. Scripts depending on local Includes, DLLs, INI files, images, or other assets must keep those dependencies available in their package.

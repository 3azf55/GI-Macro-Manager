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

When a normalized name already exists, Macro Manager appends a numeric suffix such as `_2`. The chosen ID and folder remain unchanged afterward. Registered legacy imports that still use a timestamped `user_*` identity are normalized automatically at startup.

## Registry entry

```ini
[Combo.Example_Hero_Example_combo]
Id=Example_Hero_Example_combo
Character=Example Hero
Image=Example Hero.png
Name=Example combo
Tooltip=Optional description
Tag=120 FPS
Script=Macros\User\Example_Hero\Example_combo\run.ahk
BuiltIn=0
Order=10
```

`Order` controls display order, combo cycling, and the Tray menu.

## Package manifest

Every managed package includes `manifest.ini`:

```ini
[Macro]
Id=Example_Hero_Example_combo
Character=Example Hero
Image=Example Hero.png
Name=Example combo
Tooltip=Optional description
Tag=120 FPS
Source=source.ahk
ManagedPackage=1
PackageFormat=2
Version=2
```

The manifest makes the package portable and distinguishes an intentional macro package from an arbitrary folder containing executable code.

## Import behavior

The importer copies the selected file to `source.ahk`, writes the manifest and registry entry, and creates `run.ahk` when required.

It classifies the script as:

- `AutoTrigger`: a hotkey was detected and converted into a generated entry;
- `RunMacro`: the file exposes `RunMacro()`;
- `AutoExecute`: no hotkey or `RunMacro()` was detected.

AutoHotkey v2 files explicitly declaring `#Requires AutoHotkey v2` are rejected.

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

Macro Manager preserves `Name`, `Tooltip`, and `Tag` when a package is copied between project trees. Recovery reads these fields from `manifest.ini`. When importing an AHK file exported by Macro Manager, metadata can also be restored from its comment header.

Supported `Tag` values are:

```text
60 FPS
120 FPS
240 FPS
TESTING
```

An explicit tag selected in the import form takes precedence.

## External dependencies

Import centers on the selected AHK file. Scripts depending on local Includes, DLLs, INI files, images, or other assets must keep those dependencies available in their package.

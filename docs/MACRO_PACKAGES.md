# Macro Packages

## Directory structure

```text
Macros/
├── registry.ini
├── Runtime/
│   └── MacroRuntime.ahk
└── User/
    └── <Character>/
        └── <MacroId>/
            ├── manifest.ini
            ├── source.ahk
            └── run.ahk       generated for some imported scripts
```

## Registry entry

```ini
[Combo.Example]
Id=Example
Character=Example Hero
Image=Example Hero.png
Name=Example combo
Tooltip=Optional description
Tag=120 FPS
Script=Macros\User\Example_Hero\Example\source.ahk
BuiltIn=0
Order=10
```

`Order` controls display order, combo cycling, and the Tray menu.

## Import behavior

The importer copies the chosen file to `source.ahk`.

It then classifies the script:

- `AutoTrigger`: a hotkey was detected and converted into a generated entry;
- `RunMacro`: the file exposes `RunMacro()`;
- `AutoExecute`: no hotkey or `RunMacro()` was detected.

AutoHotkey v2 files explicitly declaring `#Requires AutoHotkey v2` are rejected.

## Trigger compatibility

For AutoTrigger scripts, generated runners can redirect function-style calls
such as:

```ahk
GetKeyState(HoldKey, "P")
```

When `HoldKey` refers to the detected original trigger, the generated runner
reports it as held while the child process is alive. Macro Manager remains
responsible for terminating the process when its configured Trigger is
released.

The legacy command form and every possible custom input implementation are not
universally transformable.

## External dependencies

Import currently centers on the selected AHK file. Scripts depending on local
Includes, DLLs, INI files, images, or other assets must keep those dependencies
available in their package.

## Orphan imported-package recovery

At startup, Macro Manager scans `Macros/User/<Character>/user_*` folders. If a
folder contains `source.ahk` but has no matching entry in `registry.ini`, the
engine creates or reuses `run.ahk`, infers the display name from the generated
folder ID, writes a manifest, and registers the package.

This recovery is intended for folders originally created by Macro Manager.
Normal custom packages should still include `manifest.ini` and an explicit
registry entry.

## Portable display metadata

Macro Manager preserves `Name`, `Tooltip`, and `Tag` when a package is copied between project trees. Recovery reads these fields from `manifest.ini`. When the manifest is missing, it can also recover metadata from the comment header of an AHK file exported by Macro Manager.

Supported `Tag` values are:

```text
60 FPS
120 FPS
240 FPS
TESTING
```

An explicit tag selected in the import form takes precedence. When the form tag is empty, a valid tag embedded in an exported AHK file is restored automatically.

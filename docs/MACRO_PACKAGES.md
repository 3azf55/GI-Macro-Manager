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

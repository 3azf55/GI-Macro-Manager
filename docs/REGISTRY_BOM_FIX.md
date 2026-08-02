# Registry BOM Fix

## Root cause

`Macros/registry.ini` began with these three bytes:

```text
EF BB BF
```

They are the UTF-8 byte-order mark. The first visible line was:

```ini
[Combo.Overload]
```

Because the BOM was located immediately before the first opening bracket,
AutoHotkey v1's INI enumeration could fail to recognize the first section.
Every later section remained visible, which made only the first macro appear
to be missing.

## Protection

The engine now removes an UTF-8 BOM from `registry.ini` before any `IniRead`
operation.

The build script also rewrites the staged registry as UTF-8 without BOM.

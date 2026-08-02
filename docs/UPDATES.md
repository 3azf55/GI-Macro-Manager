# Update and Release Guide

GI Macro Manager checks the latest published full release through the GitHub Releases API.

## Release asset requirement

Each stable release must include one complete Windows runtime ZIP named:

```text
GI-Macro-Manager-vX.Y.Z-win-x64.zip
```

The ZIP must contain a built runtime package with at least:

```text
UMM.Engine.ahk
UMM.UI.exe
ui\index.html
ui\app.js
Macros\registry.ini
```

Source archives generated automatically by GitHub are not installable runtime packages.

## Automated release workflow

The repository includes:

```text
.github\workflows\release.yml
```

Pushing a tag such as `v1.6.5` starts a Windows build, creates the required ZIP, and publishes or updates the matching GitHub Release.

Before creating the tag, make sure these versions match:

```text
UMM.Engine.ahk                 global AppVersion := "v1.6.5"
UIHost\UMM.UI.csproj           <Version>1.6.5</Version>
UIHost\ui\build-info.json      "version": "v1.6.5"
```

Then run:

```powershell
git add .
git commit -m "Release v1.6.5"
git push

git tag v1.6.5
git push origin v1.6.5
```

The workflow validates the tag against the engine and UI versions before building.

## Update installation behavior

The updater:

1. Requests the latest stable published release.
2. Compares its tag with the installed UI assembly version.
3. Selects the matching Windows ZIP asset.
4. Downloads the file over HTTPS.
5. Verifies the GitHub SHA-256 digest when the API provides one.
6. Extracts the ZIP with path traversal and size limits.
7. Validates that the package is a complete runtime build.
8. Merges the release catalog with the installed catalog.
9. Closes Macro Manager, replaces application files, and restarts it.

The catalog merge keeps custom macro sections and preserves the existing `Order` value for macros included in both catalogs.

The update script also keeps `settings.ini`, the `bridge` directory, and extra custom macro folders that are not present in the release package.

## Manual workflow run

The release workflow can also be started from the Actions tab. Provide an existing tag in `vMAJOR.MINOR.PATCH` format. The workflow checks out that tag and refuses to publish when any project version differs.

Each release includes the runtime ZIP and a SHA-256 checksum file.

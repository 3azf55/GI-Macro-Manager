# Security Policy

## Imported AutoHotkey scripts

A `.ahk` file is executable code. An imported macro can potentially:

- read or modify files available to the current Windows user;
- start programs and child processes;
- access the network;
- send keyboard and mouse input;
- change system or application settings.

Only import scripts from sources you trust and review their source before running them.

## Current isolation boundary

Macro Manager starts a macro in a separate AutoHotkey child process and can terminate that process when the configured Trigger is released. This does **not** sandbox the script.

A script may start another process or create persistent system changes that remain after the original child process is terminated.

## Windows privilege boundary

Macro Manager intentionally requests Administrator permission at startup. The engine uses a single `/restart`-guarded UAC relaunch and exits if elevation is not granted, so a failed elevation cannot create a restart loop.

The WebView2 host and imported macro child processes inherit the engine's elevated token. Commands received from WebView2 are allowlisted, size-limited, and normalized again at the engine boundary, but the local file bridge is an IPC mechanism rather than a security sandbox. Never import an untrusted macro or allow untrusted users or processes to modify the installation directory while Macro Manager is running.

## FPS limiter and game-process modification

The FPS limiter is optional and disabled by default. When enabled, Macro Manager loads `UnlockerStub.dll` into a supported game process and changes the in-memory frame-rate value. This has a different risk profile from ordinary macro input:

- game updates can invalidate the memory pattern and make the feature fail;
- anti-cheat or publisher policy can change without notice;
- no third-party process modification can be promised to be ban-safe;
- replacing the packaged native DLL with an untrusted file would execute untrusted code inside the game.

The release workflow builds the native DLL from the included source. Do not download or substitute an unknown prebuilt DLL. If the interface reports incompatibility, disable the feature and wait for a reviewed source update.

## Reporting a vulnerability

Do not post credentials, personal paths, private macros, or sensitive logs in a public issue.

When a public GitHub repository is available, use a private security advisory when possible. Otherwise, contact the maintainer through the Discord community:

https://discord.gg/H8HNhvqqm

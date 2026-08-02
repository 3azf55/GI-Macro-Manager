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

## Reporting a vulnerability

Do not post credentials, personal paths, private macros, or sensitive logs in a public issue.

When a public GitHub repository is available, use a private security advisory when possible. Otherwise, contact the maintainer through the Discord community:

https://discord.gg/H8HNhvqqm

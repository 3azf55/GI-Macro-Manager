# Third-Party Notices

## Open Sans

The optional Open Sans UI font files are provided by the Open Sans Project Authors and are licensed under the SIL Open Font License, Version 1.1.

The complete license is available at [`Assets/fonts/OFL.txt`](Assets/fonts/OFL.txt).

## PowerPaimon FPS unlocker and game DLL loading

The managed hook/IPC lifecycle, native frame-rate unlocking implementation, and
CreateProcess/LoadLibraryW game DLL loading flow are adapted from
[PowerPaimon](https://github.com/catteol/PowerPaimon), commit
`09eddc6393714900cca0fb55bb83cb490acf09b8`, which is derived from the
Genshin FPS Unlocker work by 34736384.

Copyright (c) 2021-Present 34736384.

This component is used under the MIT License. The complete upstream license is
available at [`FpsUnlocker/LICENSE-UPSTREAM.txt`](FpsUnlocker/LICENSE-UPSTREAM.txt).

## PresentMon

The optional Show FPS monitor bundles the official x64 console build of
[PresentMon](https://github.com/GameTechDev/PresentMon), version 2.5.1. PresentMon
collects frame-presentation events through Windows ETW; Macro Manager parses its
CSV output and draws its own small draggable overlay.

PresentMon is Copyright (C) 2017-2024 Intel Corporation and is used under the
MIT License. Its license and bundled third-party notices are available at
[`PresentMon/LICENSE.txt`](PresentMon/LICENSE.txt) and
[`PresentMon/THIRD_PARTY.txt`](PresentMon/THIRD_PARTY.txt).

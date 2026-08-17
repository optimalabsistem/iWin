# Architecture

## The stack, top to bottom

| Layer | What it is |
|-------|-----------|
| SwiftUI / Metal host app | `app/` — owns the window, CAMetalLayer compositor, input, audio. |
| Wine 11.4 fork (**ARM64EC**) | Windows API. `wineserver` runs as a *thread*, not a process. |
| FEX-Emu fork | x86-64 → ARM64 JIT, entered via `xtajit64.dll` (ARM64EC "Path B"). |
| DXMT | D3D11 → Metal (direct, no Vulkan intermediary). |

The host app is a single Mach task. Every Windows "process" (steam.exe,
steamwebhelper.exe, services.exe, rpcss…) is a pseudo-process: a thread inside
that one task. There is no process isolation — an unhandled fault in any
"process" kills the whole app, which is why so much engineering goes into
fault containment and signal handling.

## Guest execution model

- Wine's system DLLs run natively as ARM64 / ARM64EC PE binaries.
- Only guest x86-64 code runs through FEX (via `xtajit64.dll`).
- Two PE bundle architectures ship in the app: `aarch64-windows/` (native
  ARM64 system DLLs) and `arm64ec-windows/` (ARM64EC hybrid DLLs that interop
  with FEX-translated x86-64 code). Selection is heuristic in
  `WineProcessBridge.m`: `explorer` → aarch64; a `*x64*` name or a full
  `C:\...` path → arm64ec; `MYTHIC_USE_ARM64EC=1` forces it.
- Per-arch "farms" (`drive_c/windows/sysx64`, `sysaa64`) hold the
  cross-architecture DLL copies so cross-arch child processes resolve.

## Hard constraints (non-negotiable)

- **Free Apple ID sideloading only.** No paid entitlements, no jailbreak,
  7-day provisioning, max 3 apps.
- **JIT via StikDebug.** A debugger attaches, the app `BRK`s, the debugger
  grants `CS_DEBUGGED`. After the debugger detaches, **no new executable
  mappings can be created**, so all JIT memory is reserved up front as one
  dual-mapped RX/RW pool.
- **Usable CPU virtual address space is ~64 GB, not 512 GB.** iOS reserves a
  GPU carveout at `[64G, 448G)` that is xnu-proven undefeatable. This is why
  Steam + CEF must be single-process.
- **Jetsam ceiling is exactly 4096 MB.** Runs currently peak ~3.0–3.4 GB.

## Virtual-address map (never to be violated)

```
guest code/data            ≤ 0x73ffff0000
CEF's four 16 GB PartitionAlloc pools   [0x74, 0x7c)
FEX host + arena                        [0x7c, 0x80)
```

## Data flow

1. User taps a launcher entry → Swift starts the wineserver thread
   (`WineServerBridge.m`), which seeds the prefix BEFORE loading the registry.
2. `WineProcessBridge.m` sets up the environment, symlinks PE DLLs into
   `system32`, then calls `__wine_main()` on a background thread.
3. FEX (`FEXBridge.mm`) initializes the JIT pool first — its RX→RW write offset
   is published via `MYTHIC_JIT_WRITE_OFFSET` to `xtajit64.dll`.
4. Guest DX11 calls → DXMT → Metal, presented to the window-level CAMetalLayer
   owned by `MetalHostView` (in `ContentView.swift`).

## Current status (as of the last handoff)

- **Thumper (x86-64) is PLAYABLE** with audio (~142 FPS typical, 2286 peak).
- **Steam's CEF login window renders and is interactive** (hover, QR-refresh
  click work). CEF = Chromium 126.0.6478.183. Reached via the ladder
  `BrowserReady → transport → GetDesiredSteamUIWindows → PopupHTMLWindow →
  BrowserReady 131073`.
- CrossOver on macOS runs this same Steam client correctly — the open bugs are
  in *this* stack, not Steam/CEF.

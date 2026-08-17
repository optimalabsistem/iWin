# JIT, memory, and environment

## JIT acquisition (StikDebug)

1. `StikJITHelper.enableJIT` opens `stikjit://enable-jit?bundle-id=…&script-data=<base64>`.
2. StikDebug attaches (`vAttach;<pid>`), the app `BRK #0xf00d`s, StikDebug
   grants `CS_DEBUGGED` (polled via `jit_check_debugged()` → `csops`).
3. The JIT pool is reserved up front as one dual-mapped region; **after the
   debugger detaches no new executable mappings can be created**.
4. Detach early — the debugger burns its CPU budget fast; late departure
   caused a ~54 s whole-app stall (#67).

The debugger script (`mythic-jit.js`) implements the BRK protocol: skip genuine
BRK (PC += 4), forward real faults/signals back to the process as Unix signals,
and kill-not-detach on undeliverable faults.

## Dual-mapped memory (W^X compliance)

One physical backing, two virtual views:

- **RX view** — executable (code runs here).
- **RW view** — writable (code is written here).

`JITAllocator.c` creates it with `mach_make_memory_entry_64`
(`MAP_MEM_NAMED_CREATE`) + two `vm_map`s, optionally marked
`VM_LEDGER_FLAG_NO_FOOTPRINT` via the private `mach_memory_entry_ownership`
so the pool does not count against the Jetsam limit.

`FEXBridge.mm` (production path) instead asks StikDebug to allocate RX
(`jit26_prepare_region`) and creates the RW alias with `vm_remap`. The RX→RW
delta becomes `FEXCore::DualMap::WriteOffset` and is published as
`MYTHIC_JIT_WRITE_OFFSET` to `xtajit64.dll` (see the env list below).

## Pool placement constraints (violating either bricks the session)

- **Low bound:** FEX has a position-dependent emit bug below `0x119000000`
  (mode A: dispatcher branches to zero memory before block 0 runs).
- **Guest window:** the pool must NOT land in `[0x70, 0x80)G` — that is where
  Wine packs PE images, and executing pool code there hangs silently.

Bad placements are rejected and re-rolled; a bad region is freed if possible,
otherwise kept alive as a pin. (`StikJITHelper.swift` pins low address space to
push the ANYWHERE allocation above the threshold.)

## Memory ceilings

- Jetsam ceiling: **4096 MB** (runs peak ~3.0–3.4 GB).
- Usable VA: ~64 GB (GPU carveout `[64G, 448G)` is xnu-proven undefeatable).
- Entitlements: `com.apple.developer.kernel.increased-memory-limit` and
  `com.apple.developer.kernel.extended-virtual-addressing` are declared, but a
  free Apple ID cannot provision them at runtime — see gotchas.

## Environment variables (set in `WineProcessBridge.m`)

| Variable | Meaning |
|----------|---------|
| `WINEPREFIX` / `HOME` | Prefix path (app Documents/wine). |
| `WINEDLLPATH` | App bundle (holds `aarch64-windows/`, `arm64ec-windows/` PE DLLs). |
| `WINESERVERSOCKET` | Socketpair fd for ntdll → wineserver (bypasses broken iOS UDS accept). |
| `WINELOADERNOEXEC=1` | Skip Wine's check_command_line / reexec_loader. |
| `WINEDEBUG` | `err+all,err-virtual` (perf default); `MYTHIC_DEBUG_VERBOSE=1` restores full trace. |
| `MYTHIC_EXE` | Guest exe to launch (`cube.exe` default; full `C:\...` paths allowed). |
| `MYTHIC_ARGS` | Space-separated extra argv tokens. |
| `MYTHIC_USE_ARM64EC=1` | Force the ARM64EC bundle. |
| `MYTHIC_JIT_WRITE_OFFSET` | RX→RW pool offset, published to `xtajit64.dll`. |
| `MYTHIC_DOCS_DIR` | App Documents dir (e.g. for `fex-jit-dump.bin`). |
| `MYTHIC_CA_BUNDLE` | Path to bundled `cacert.pem` for crypt32 rootstore. |
| `MYTHIC_INITIAL_CWD` | Wine cwd override for full-path launches. |
| `MYTHIC_QUIET=1` | Disables heavy diagnostics (PROF sampler, per-present logs). |
| `MYTHIC_WIN32U=1` | Enables win32u path. |
| `MYTHIC_DESKTOP`, `MYTHIC_SCREEN_W/H` | Desktop mode + logical surface size (read from the app). |
| `SteamAppPath`, `SteamGameId`, `SteamAppId` | Steam game vars (setenv → but see gotcha #11). |

## Guest thread-exit containment

`wine_ios_exit.h` shim (in `build/ntdll-unix/shims/`) intercepts `_exit`,
`_Exit`, and `abort` so a guest "process" thread can longjmp out
(`wine_ios_exit_jmpbuf`, thread-local in `WineProcessBridge.m`) instead of
terminating the whole app.

# Gotchas, methodology, and open problems

## Methodology rules (learned the hard way — assume load-bearing)

1. No per-app/per-game fixes. Fix the accuracy gap, not the symptom.
2. A probe must not break what it measures, and its bound must be reachable —
   spend the budget counter before the risky op, never after.
3. Confirm-only probes prove nothing. Print the negative case too.
4. A constant delta means stale data, not a real signal.
5. Offline disassembly is free — exhaust it before spending a 40–60 s device run.
6. Verify deploys by content (`grep -ac '<marker>' <shipped binary>`).
7. Read Steam's own logs first (`drive_c/Program Files (x86)/Steam/logs/`).
8. Pull binaries from the phone prefix, not local copies (a local `libcef.dll`
   was a different build and invalidated a control).
9. `/usr/bin/log collect --device-udid …` (needs root) is the only way to
   observe a whole-task stop. `log` is shadowed in zsh; use `/usr/bin/log`.
   `--start/--end` silently match nothing given fractional seconds.
10. Submodule `unix/*.c` fixes are dead code — the `*_ios.c` forks build.
11. `setenv()` in `WineProcessBridge.m` does **not** reach
    `GetEnvironmentVariableW` for arbitrary names (allowlist is `WINE*`,
    `DXVK_*`). Publish FEX/wine values through Wine's own env snapshot point.
12. BSD `grep` silently suppresses output on NUL-containing logs without `-a`.

## Solved walls (context; the methods are reusable)

| # | Wall | Root cause & fix |
|---|------|------------------|
| #61 | Steam draws no text | `dwrite.dll` had no unixlib on iOS → every `__wine_unix_call` failed → empty glyph bboxes. Built a dwrite unixlib; it silently wasn't archived until added to the explicit `ar rcs` list. "Compiled OK" ≠ "shipped". |
| #67 | ~54 s whole-app stall | StikDebug debugger departing (clean or jetsam) burns its CPU budget in ~52 s. Fix: detach early, right after the JIT pool is granted. Also sped Steam webhelper 89 s → 9 s. |
| #70 | C00000FD infinite recursion | Chromium font-init recursed on stale macOS font paths; dwrite is registry-only, GDI dir-scans. Registry-only font push. |
| #71 | Misaligned compare-exchange in Valve shm | Mach-side misaligned-atomic emulation (no code patching). |
| #72 | V8 cage VA exhaustion | Aligned reservations, 8 GB sandbox holdback, 4 GB cppgc cap. |
| #74 | Steam watchdog cross-terminates threads holding FEX JIT locks | Fixed. `Failed to mprotect last page` is benign. |
| #79 | Steam pid-auth rejected 11/11 | Linux-vs-BSD TCP state numbering mismatch in `sock.c`. |
| #83 | Misaligned 8-byte MOVs into PA-band SM_COW | `memcpy`-based unaligned emulation in the bus handler. |

Also self-inflicted and fixed: a `[rsp-trunc]` diagnostic read TSD slot 275 as
a Wine TEB (slot 275 is not ours — Apple framework value sits there); and
`pthread_exit_wrapper` dereferenced a NULL TEB in the fault breaker.

## Open problems (ranked — from the last handoff)

1. **`KERN_MEMORY_ERROR` (kr=10) crash** — `libcef.dll+0x41258FB`. A mapped,
   RW, page-aligned address faults exactly once with `KERN_MEMORY_ERROR`, and
   `[bus-reheal]` misdiagnoses it as a protection strip (its `entryprot=3
   nowprot=3` says protection was never stripped). Most concrete lead. Candidates:
   a purged volatile region, compressor decompression failure, destroyed backing
   entry. The fix is ownership/lifetime, not protection.
2. **Render corruption — tile-granular displacement** (Steam login). Duplicated
   logos, seams at x=185 and tile boundaries; 254px interior pitch ⇒ tile-granular,
   per-draw-op destination error, not a whole-surface offset. Every layer we own
   is exonerated. Best hypothesis: deterministic misexecution of Chromium under
   FEX. Untried: lift Chromium 126's compositing path into a standalone test PE
   for offline bisection.
3. **CM login / network** — above TCP (handshakes complete, some TLS completes).
   Fails at the TLS/WebSocket layer. `GetAdaptersAddresses failed: 2` is real but
   not the blocker.

Separate small items: login-window black pixels are alpha=0 (needs a per-window
alpha gate on the BGRX surface); `#42`-family `x17` (REG_CALLRET_SP on ARM64EC)
is IP1 and gets zeroed across EC thunks.

## FEX conformance tooling

`build/x64-tests/gen_asmconf.py` re-hosts FEX's own 1,283 golden-value
instruction tests in a Windows PE (through our fork + ARM64EC + jitless). It
assembles/links but is parked because test 17 kills the process; needs a
statically filtered safe subset. `fpconf-x64.c` passes 28/28 — basic FP/SSE is
not the render-corruption cause.

## Refuted / do-not-re-propose (highlights)

- `--disable-threaded-compositing` (breaks frame production entirely).
- Memory-ordering / TSO / SIMD-dropped-stores / missing-invalidate hypotheses.
- JIT-pool use-after-free (guard found 0 refusals across 52 frees).
- Page reclamation (#53).
- Stale-memory / zero-fill contract (unbounded censuses found 0 violations).
- The `srcwatch` probe family has a hard ceiling — stop iterating on it.

Keep `STEAM_CEF_HANDOFF.md` in sync with any new CONFIRMED/REFUTED/OPEN result;
it is the canonical handoff document.

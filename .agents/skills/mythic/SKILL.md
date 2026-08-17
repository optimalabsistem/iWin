---
name: mythic
description: >-
  Knowledge base for the Mythic project — an iOS app that runs x86-64 Windows
  games (Wine 11.4 ARM64EC + FEX-Emu x86->ARM64 JIT + DXMT D3D11->Metal) on a
  stock, non-jailbroken iPhone. Use this skill whenever working in this
  repository: understanding the stack, tracing launch / wineserver / JIT code,
  debugging Wine, FEX or DXMT, building/deploying, or adding new knowledge.
  Read the relevant file under references/ for the details; do not guess from
  the top of this file alone.
---

# Mythic — Project Knowledge Base

Run real x86-64 Windows games (and the Steam client) on a stock, non-jailbroken
iPhone, sideloaded with a free Apple ID. All "Windows processes" are
pseudo-processes — threads inside ONE Mach task — so fault containment is a
first-class concern.

## When to use this skill

Activate when the task touches any of:

- The iOS app (`app/Mythic/`), Wine/FEX/DXMT bridging, or the build system.
- JIT / dual-mapped memory / StikDebug / entitlements.
- The `wine` and `FEX` submodules or any `build/*` static library.
- Debugging a guest crash, rendering, input, audio, or network issue.

## Reference index (read the one you need — do not load all)

| File | Contents |
|------|----------|
| [references/architecture.md](references/architecture.md) | The stack, hard constraints, and the virtual-address map. |
| [references/codebase-map.md](references/codebase-map.md) | Where each component lives and the build chains. |
| [references/jit-and-memory.md](references/jit-and-memory.md) | JIT pool, W^X, StikDebug protocol, Jetsam, environment variables. |
| [references/build-and-deploy.md](references/build-and-deploy.md) | CI (Codemagic), local build scripts, and device deployment. |
| [references/gotchas.md](references/gotchas.md) | Methodology rules, solved walls, and the current open bugs. |

The automatically generated tree at
[references/_autogen-tree.md](references/_autogen-tree.md) is refreshed by the
script below; treat it as an index, not canonical knowledge.

## How this knowledge base grows

The `references/` files are the retrieval corpus. They are meant to evolve with
the code — when you fix a bug, find a new constraint, or add a component:

1. Append the finding to the most relevant `references/*.md` file (a new
   "Solved wall" row, a new env var, a new gotcha). Prefer editing an existing
   file over creating a new one.
2. If the file tree changed (new `build/*` dir, new `*_ios.c` fork), run
   [scripts/refresh.sh](scripts/refresh.sh) to regenerate the tree index:
   ```sh
   .agents/skills/mythic/scripts/refresh.sh
   ```
3. Do not delete entries when they become "done" — solved walls are retained as
   reusable method knowledge (the project itself keeps them for this reason).

## Non-negotiable project rules (load-bearing)

- No per-app/per-game fixes. Fix the accuracy gap, not the symptom.
- Every probe must print the negative case, or "nothing happened" is not an
  observation.
- Offline disassembly/analysis is free; a device run costs 40–60 s. Exhaust the
  cheap path first.
- Submodule `unix/*.c` fixes are dead code — the `*_ios.c` forks are what build.
- Verify deploys by content (`grep -ac '<marker>'` on the shipped binary), not
  by assuming a `.a` compiled into the bundle.

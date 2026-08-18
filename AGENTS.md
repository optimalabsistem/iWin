# iWin / Mythic Project Knowledge & Persistent Memory (AGENTS.md)

## 📌 Project Overview
- **Goal**: Run x86-64 / ARM64 Windows applications and DirectX 11 Metal games on non-jailbroken iOS / iPadOS using Wine + FEX JIT + DXMT.
- **Repository**: `https://github.com/optimalabsistem/iWin.git` (branch `main`).
- **CI / CD**: Codemagic API (App ID: `6a8023cf319d803a9daeb3ef`, Workflow: `ios-iwin-workflow`).
- **Live Telemetry Server**: `https://comes-wealth-sink-vast.trycloudflare.com/log` (Cloudflare Tunnel HTTPS) & direct `http://3.1.51.240:8080/log` (monitored locally via `server_logger.py` and `live_logs.txt`).

---

## 🔒 Crucial Architecture Rules & Lessons Learned (DO NOT FORGET)

### 1. Wine Desktop & Start Menu Integrity
- **Start Menu Simplicity**: The Start Menu in Wine Explorer MUST remain clean with only `Run...` and `Exit Desktop`.
- **NO Files in `Start Menu/Programs`**: Placing `.bat` or shortcut files in `drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs` causes `fill_menu()` in Wine to invoke COM `IShellFolder` object enumeration, which deadlocks/freezes the taskbar and Start button on iOS.
- **NO DLL Cross-Linking**: When linking files from bundle directories into `system32`, only `.exe` files should be cross-linked. Never cross-link incompatible `.dll` files (e.g. ARM64EC `uxtheme.dll` into an AArch64 native session), as it causes `status=0xc000007b` and freezes the UI.

### 2. Forked Source Files (Source of Truth)
- **Do NOT edit submodules directly**: In `wine/` or `FEX/`, changes can be overwritten by `git submodule update --init`.
- **Source of Truth for Static Libs**:
  - `libntdll.a` -> Edit `/home/admin/mythic/build/ntdll-unix/` (`virtual_ios.c`, `signal_arm64_ios.c`, etc.).
  - `libwin32u.a` -> Edit `/home/admin/mythic/build/win32u-unix/`.
  - `libwineserver.a` -> Edit `/home/admin/mythic/build/wineserver/`.
  - `Mythic iOS App` -> Edit `/home/admin/mythic/app/Mythic/` (`WineProcessBridge.m`, `ContentView.swift`, `Mythic.entitlements`).

### 3. iOS Memory & Mach Exception Handling
- **Extended Virtual Addressing (64-bit VA)**: Requires `com.apple.developer.kernel.extended-virtual-addressing` in `Mythic.entitlements`.
- **Universal Page Healing (`mach-heal-page`)**: If a guest read/write fault occurs on a page with `prot=0` (`VM_PROT_NONE`), `signal_arm64_ios.c` restores `VM_PROT_READ | VM_PROT_WRITE` via `mach_vm_protect` and resumes execution.

### 4. Build & Verification Protocol
- After making code changes:
  1. Commit and push to `origin main`.
  2. Trigger Codemagic build via `https://api.codemagic.io/builds`.
  3. Monitor build with `monitor_build.py` until `FINISHED`.
  4. Provide direct artifact download links to the user.

---


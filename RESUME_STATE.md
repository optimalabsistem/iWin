# RESUME STATE — iWin/Mythic

> File handoff antar sesi Freebuff. **Baca di awal sesi baru**, **update di akhir sesi**.
> Diperbarui: 2026-08-20 (sesi: Fix ROUND_SIZE PE Section Mapping & Trigger Codemagic Build)

## Status terakhir
- **Fix Terkini**:
  1. `build/ntdll-unix/virtual_ios.c`: Fix bug kalkulasi `ROUND_SIZE` pada `.data` & `.bss` mapping (`map_image_into_view` & `virtual_create_builtin_view`). Mengganti `(uintptr_t)sec_addr` dan `(uintptr_t)((char *)base + sec[i].VirtualAddress)` dengan `sec[si].VirtualAddress` (relatif terhadap image base), sehingga section `.data` biner PE mendapatkan proteksi memori `PROT_READ | PROT_WRITE` yang valid di iOS kernel.
- **Web Live Logs**: `https://relations-ing-diversity-formerly.trycloudflare.com/logs`
- **Telemetry Endpoint Aktif**: `https://relations-ing-diversity-formerly.trycloudflare.com/log` (HTTP port 8080)

## Fitur Build Sebelumnya:
1. `build/d3d11-triangle/triangle.c`: Entry point ganda `WinMain` + `main` standar Win32 GUI murni.
2. `build/d3d11-triangle/triangle.c`: Format swapchain `DXGI_FORMAT_B8G8R8A8_UNORM_SRGB` (standar resmi DXMT) & `Present(0, 0)` immediate commit.
3. `app/Mythic/ContentView.swift` & `WineProcessBridge.m`: `WINEDLLOVERRIDES="d3d11=n,b;dxgi=n,b;winemetal=n,b;libc++=n,b;libunwind=n,b"`.
4. `app/Mythic/RemoteLogger.swift`: Real-time POSIX STDERR redirection langsung ke Web Live Logs.
5. `app/Mythic/ContentView.swift`: Eksekusi Direct in-process tunggal untuk biner 3D.
6. `app/Mythic/ContentView.swift`: Background `CAMetalLayer` transparan (`UIColor.clear.cgColor`).

## Langkah berikutnya
1. Tunggu build Codemagic selesai dan unduh `iWin.ipa`
2. Pasang di iPad dan jalankan pengujian 3D Cube / Triangle
3. Verifikasi log: `[STEP-1-D3D11] cube.exe: CreateWindowEx OK` dan `Present` frame count bertambah

## Rule penting (jangan dilanggar)
- **Jangan edit submodule `wine/` atau `FEX/` langsung** — edit source of truth: `build/ntdll-unix/`, `build/win32u-unix/`, `build/wineserver/`, `app/Mythic/`
- Start Menu harus bersih (hanya `Run...` + `Exit Desktop`) — jangan taruh file di `Start Menu/Programs`
- Jangan cross-link DLL arm64ec (mis. `uxtheme.dll`) ke sesi aarch64 native — `status=0xc000007b`
- Setelah patch: commit + push `origin main` → trigger Codemagic (App ID `6a8589ee4049aa8ea251422c`, workflow `ios-iwin-workflow`) → monitor `monitor_build.py` → beri link artifact ke user

## Telemetry
- Server: `https://relations-ing-diversity-formerly.trycloudflare.com/log` & `http://3.1.51.240:8080/log`
- Log lokal: `live_logs.txt` (monitor via `server_logger.py`)

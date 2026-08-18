# RESUME STATE — iWin/Mythic

> File handoff antar sesi Freebuff. **Baca di awal sesi baru**, **update di akhir sesi**.
> Diperbarui: 2026-08-17 (sesi: setup Telegram autonomous loop)

## Status terakhir
- **Selesai di-patch**: Fix crash `cube.exe` (PE .data store fault & protection)
  1. `build/ntdll-unix/signal_arm64_ios.c`: Menambahkan mapping lookup PE via `ios_jit_translate_addr` pada path store emulation (`rw_addr` & `rw_end`), sehingga store ke original PE VA (seperti `.data` 0x14003a9d8) diarahkan ke JIT pool RW alias (0x11cc409d8) dan PC di-advance + 4.
  2. `build/ntdll-unix/virtual_ios.c`: Memperbaiki bug kalkulasi `ROUND_SIZE` pada `map_image_into_view` dan `virtual_create_builtin_view` yang sebelumnya menyebabkan underflow `data_map_sz` / `bss_map_size` dan membuat `.data` section tertinggal dalam status prot=0 max=0.

## Langkah berikutnya
1. Commit & push ke `origin main`
2. Trigger Codemagic build (workflow `ios-iwin-workflow`) & monitor via `monitor_build.py`
3. Ambil log runtime terbaru / verifikasi rendering `cube.exe` & DXMT


## Rule penting (jangan dilanggar)
- **Jangan edit submodule `wine/` atau `FEX/` langsung** — edit source of truth: `build/ntdll-unix/`, `build/win32u-unix/`, `build/wineserver/`, `app/Mythic/`
- Start Menu harus bersih (hanya `Run...` + `Exit Desktop`) — jangan taruh file di `Start Menu/Programs`
- Jangan cross-link DLL arm64ec (mis. `uxtheme.dll`) ke sesi aarch64 native — `status=0xc000007b`
- Setelah patch: commit + push `origin main` → trigger Codemagic (App ID `6a8023cf319d803a9daeb3ef`, workflow `ios-iwin-workflow`) → monitor `monitor_build.py` → beri link artifact ke user

## Telemetry
- Server: `https://comes-wealth-sink-vast.trycloudflare.com/log` & `http://3.1.51.240:8080/log`
- Log lokal: `live_logs.txt` (monitor via `server_logger.py`)

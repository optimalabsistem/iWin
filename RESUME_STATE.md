# RESUME STATE — iWin/Mythic

> File handoff antar sesi Freebuff. **Baca di awal sesi baru**, **update di akhir sesi**.
> Diperbarui: 2026-08-20 (sesi: Robust WinMain & D3D11 Initialization for Cube & Triangle)

## Status terakhir
- **Fix Terkini**:
  1. `research/dxmt/tests/dx11/dx11_cube.cpp` & `build/dxmt-tests/dx11_cube.cpp`:
     - Fix `hInstance` fallback via `GetModuleHandleW(NULL)` jika dipanggil dengan `NULL`.
     - Hapus semua blocking `MessageBoxA(...)` yang menyebabkan thread Windows hang/beku di iOS.
     - Tambah `[STEP-1-D3D11] cube.exe: WinMain entered!` di awal fungsi.
     - Tambah `extern "C" int main(...)` wrapper.
  2. `build/d3d11-triangle/triangle.c` & `build/d3d11-triangle/build.sh`:
     - Tambah `#include <initguid.h>` agar `IID_ID3D11Texture2D` terdefinisi dan `GetBuffer` tidak crash.
     - Tambah guard & HRESULT checks lengkap di semua tahap D3D11 (`GetBuffer`, `CreateRenderTargetView`, `CreateVertexShader`, `CreatePixelShader`, `CreateInputLayout`, `CreateBuffer`).
     - Tambah flag `-mwindows` dan `-Wl,--section-alignment=0x4000`.
     - Generate `vs_dxbc.h` dan `ps_dxbc.h` pre-compiled shaders.
  3. `build/build_cube_aarch64.sh` & `codemagic.yaml`:
     - Tambah `-mwindows` flag.
     - Tambah step kompilasi otomatis `build/d3d11-triangle/build.sh`.
  4. `patch_repo/`:
     - Bersihkan file stale agar aplikasi iOS tidak meng-overwrite bundle binary dengan file lama via OTA.
- **Web Live Logs**: `https://relations-ing-diversity-formerly.trycloudflare.com/logs`
- **Telemetry Endpoint Aktif**: `https://relations-ing-diversity-formerly.trycloudflare.com/log` (HTTP port 8080)

## Langkah berikutnya
1. Monitor build Codemagic sampai selesai
2. Berikan file `iWin.ipa` baru ke user
3. Uji kembali 3D Cube & 3D Triangle dan verifikasi render loop logs `[STEP-3-RENDER-LOOP] presented frame=...`

## Rule penting (jangan dilanggar)
- **Jangan edit submodule `wine/` atau `FEX/` langsung** — edit source of truth: `build/ntdll-unix/`, `build/win32u-unix/`, `build/wineserver/`, `app/Mythic/`
- Start Menu harus bersih (hanya `Run...` + `Exit Desktop`) — jangan taruh file di `Start Menu/Programs`
- Jangan cross-link DLL arm64ec (mis. `uxtheme.dll`) ke sesi aarch64 native — `status=0xc000007b`
- Setelah patch: commit + push `origin main` → trigger Codemagic (App ID `6a8589ee4049aa8ea251422c`, workflow `ios-iwin-workflow`) → monitor `monitor_build.py` → beri link artifact ke user

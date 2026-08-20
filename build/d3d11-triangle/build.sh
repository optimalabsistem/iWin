#!/bin/bash
# Cross-compile triangle.c as aarch64-windows PE with pre-compiled DXBC
# shaders embedded.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
MINGW="$REPO_ROOT/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin"
if [ ! -d "$MINGW" ]; then
    MINGW="$(brew --prefix mingw-w64 2>/dev/null || echo /usr)/bin"
fi
CC_AARCH64="$MINGW/aarch64-w64-mingw32-clang"
if [ ! -x "$CC_AARCH64" ]; then
    CC_AARCH64=$(command -v aarch64-w64-mingw32-clang || true)
fi

if [ -z "$CC_AARCH64" ] || [ ! -x "$CC_AARCH64" ]; then
    LLVM_DIR=$(find "$REPO_ROOT/toolchains" -maxdepth 1 -type d -name "llvm-mingw*" 2>/dev/null | head -n 1)
    if [ -n "$LLVM_DIR" ] && [ -d "$LLVM_DIR/bin" ]; then
        CC_AARCH64="$LLVM_DIR/bin/aarch64-w64-mingw32-clang"
    fi
fi

DXMT_DIRECTX="$REPO_ROOT/research/dxmt/include/native/directx"

# --- Triangle PE ---
if [ -n "$CC_AARCH64" ] && [ -x "$CC_AARCH64" ]; then
    echo "==> building triangle.exe"
    "$CC_AARCH64" -o "$DIR/triangle.exe" \
        -Wl,--section-alignment=0x4000 \
        -mwindows \
        -I "$DXMT_DIRECTX" \
        -I "$DIR" \
        "$DIR/triangle.c" \
        -ld3d11 -ldxgi -luuid \
        -O2

    WINEBUILD="$REPO_ROOT/wine/build-macos/tools/winebuild/winebuild"
    if [ -x "$WINEBUILD" ]; then
        # Tag as a Wine builtin so our ntdll's JIT copy path is taken on iOS.
        "$WINEBUILD" --builtin "$DIR/triangle.exe" || true
    fi

    mkdir -p "$REPO_ROOT/app/Mythic/aarch64-windows"
    cp "$DIR/triangle.exe" "$REPO_ROOT/app/Mythic/aarch64-windows/triangle.exe"
    echo "==> Copied fresh triangle.exe to app/Mythic/aarch64-windows/triangle.exe"
else
    echo "Warning: aarch64-w64-mingw32-clang could not be found to build triangle.exe"
fi

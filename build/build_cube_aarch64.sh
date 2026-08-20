#!/bin/bash
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$DIR/.." && pwd)"
MINGW="$REPO_ROOT/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin"
if [ ! -d "$MINGW" ]; then
    MINGW="$(brew --prefix mingw-w64 2>/dev/null || echo /usr)/bin"
fi
CXX="$MINGW/aarch64-w64-mingw32-clang++"
if [ ! -x "$CXX" ]; then
    CXX=$(command -v aarch64-w64-mingw32-clang++ || true)
fi

if [ -z "$CXX" ] || [ ! -x "$CXX" ]; then
    echo "==> Fetching llvm-mingw toolchain for aarch64 cross-compilation..."
    mkdir -p "$REPO_ROOT/toolchains"
    curl -sL https://github.com/mstorsjo/llvm-mingw/releases/download/20240619/llvm-mingw-20240619-ucrt-macos-universal.tar.xz | tar -xJ -C "$REPO_ROOT/toolchains" || true
    LLVM_DIR=$(find "$REPO_ROOT/toolchains" -maxdepth 1 -type d -name "llvm-mingw*" | head -n 1)
    if [ -n "$LLVM_DIR" ] && [ -d "$LLVM_DIR/bin" ]; then
        CXX="$LLVM_DIR/bin/aarch64-w64-mingw32-clang++"
    fi
fi

DXMT_DIRECTX="$REPO_ROOT/research/dxmt/include/native/directx"
DXMT_TESTS="$REPO_ROOT/research/dxmt/tests/dx11"
OUT="$REPO_ROOT/build/dxmt-tests/out/cube"
mkdir -p "$OUT"

# Copy pre-compiled blobs if available
if [ -f "$REPO_ROOT/build/dxmt-tests/out-x64/cube/cube_blobs.c" ]; then
    cp "$REPO_ROOT/build/dxmt-tests/out-x64/cube/cube_blobs.c" "$OUT/cube_blobs.c"
fi

if [ -n "$CXX" ] && [ -x "$CXX" ]; then
    CUBE_SRC="$DXMT_TESTS/dx11_cube.cpp"
    if [ -f "$REPO_ROOT/build/dxmt-tests/dx11_cube.cpp" ]; then
        CUBE_SRC="$REPO_ROOT/build/dxmt-tests/dx11_cube.cpp"
    fi

    echo "==> Compiling aarch64 cube.exe with 16K section alignment and STEP logging from $CUBE_SRC"
    "$CXX" -o "$OUT/cube.exe" \
        -Wl,--section-alignment=0x4000 \
        -mwindows \
        -I "$DXMT_DIRECTX" \
        -I "$REPO_ROOT/build/dxmt-tests" \
        -I "$DXMT_TESTS" \
        -include "$REPO_ROOT/build/dxmt-tests/test_shim.h" \
        -std=c++17 -O2 \
        -Wno-int-conversion -Wno-null-conversion -Wno-c++11-narrowing \
        -static -static-libgcc -static-libstdc++ \
        "$CUBE_SRC" \
        "$OUT/cube_blobs.c" \
        -ld3d11 -ldxgi -luuid -lwinmm

    WINEBUILD="$REPO_ROOT/wine/build-macos/tools/winebuild/winebuild"
    if [ -x "$WINEBUILD" ]; then
        echo "==> Tagging cube.exe as Wine builtin"
        "$WINEBUILD" --builtin "$OUT/cube.exe" || true
    fi

    # Copy to app bundle
    mkdir -p "$REPO_ROOT/app/Mythic/aarch64-windows"
    cp "$OUT/cube.exe" "$REPO_ROOT/app/Mythic/aarch64-windows/cube.exe"
    echo "==> Copied fresh cube.exe to app/Mythic/aarch64-windows/cube.exe"
else
    echo "Warning: aarch64-w64-mingw32-clang++ could not be acquired"
fi

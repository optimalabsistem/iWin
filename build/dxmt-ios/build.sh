#!/bin/bash
# Build DXMT winemetal unix side + airconv + dxbc_parser as iOS-aarch64
# static library, for linking into Mythic.app.
#
# Produces: libdxmt_unix.a
set -eu

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$BUILD_DIR/../.." && pwd)"
DXMT_SRC="$REPO_ROOT/research/dxmt/src"
DXMT_ROOT="$REPO_ROOT/research/dxmt"
LLVM_SRC="$REPO_ROOT/toolchains/llvm-project/llvm"
LLVM_BUILD="$REPO_ROOT/toolchains/llvm-ios-build"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
OBJ_DIR="$BUILD_DIR/obj"
OUT_LIB="$BUILD_DIR/libdxmt_unix.a"

mkdir -p "$OBJ_DIR"

COMMON_FLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=17.0 -fblocks -O2"
INCLUDES="-I$DXMT_ROOT/include -I$DXMT_ROOT/libs -I$DXMT_ROOT/libs/DXBCParser -I$DXMT_SRC/winemetal -I$DXMT_SRC/airconv"
INCLUDES_DIRECTX="-I$DXMT_ROOT/include/native/directx -I$DXMT_ROOT/include/native/windows -I$REPO_ROOT/wine/include"
INCLUDES_SHADERS="-I$BUILD_DIR/shader-headers"
LLVM_INCLUDES="-I$LLVM_BUILD/include -I$LLVM_SRC/include"
if [ ! -d "$LLVM_BUILD/include" ]; then
    LLVM_PREFIX="$(brew --prefix llvm@15 2>/dev/null || brew --prefix llvm@16 2>/dev/null || brew --prefix llvm 2>/dev/null || echo /opt/homebrew/opt/llvm@15)"
    LLVM_INCLUDES="-I$LLVM_PREFIX/include"
fi
AIRCONV_DEFS="-D_FILE_OFFSET_BITS=64 -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS"
CXX_FLAGS="-std=c++20 -fno-exceptions -fno-rtti"

SUCCEEDED=0
FAILED=0
FAILED_FILES=""

echo "=== Generating Metal shader headers ==="
mkdir -p "$BUILD_DIR/shader-headers"
for shader in msad samplepos tessellation; do
    metal_src="$DXMT_SRC/airconv/shaders/air_${shader}.metal"
    if [ -f "$metal_src" ]; then
        if xcrun -sdk iphoneos metal -c -std=metal3.1 "$metal_src" -o "$OBJ_DIR/air_${shader}.air" 2>/dev/null; then
            xxd -i "$OBJ_DIR/air_${shader}.air" | sed "s/unsigned char.*=/const unsigned char air_${shader}[] =/" > "$BUILD_DIR/shader-headers/air_${shader}.h"
        else
            echo "const unsigned char air_${shader}[] = {0};" > "$BUILD_DIR/shader-headers/air_${shader}.h"
        fi
    fi
done

compile_objc() {
    local src=$1 name=$2
    printf "  %-40s " "$name"
    if xcrun -sdk iphoneos clang $COMMON_FLAGS -x objective-c $INCLUDES \
        -c "$src" -o "$OBJ_DIR/$name.o" 2>"$OBJ_DIR/$name.err"; then
        echo "OK"; SUCCEEDED=$((SUCCEEDED+1))
    else
        echo "FAILED:"
        cat "$OBJ_DIR/$name.err" 2>/dev/null || true
        FAILED=$((FAILED+1)); FAILED_FILES="$FAILED_FILES $name"
    fi
}

compile_cxx() {
    local src=$1 name=$2 extra="${3:-}"
    printf "  %-40s " "$name"
    if xcrun -sdk iphoneos clang++ $COMMON_FLAGS $CXX_FLAGS $INCLUDES $INCLUDES_DIRECTX $INCLUDES_SHADERS $LLVM_INCLUDES $AIRCONV_DEFS $extra \
        -c "$src" -o "$OBJ_DIR/$name.o" 2>"$OBJ_DIR/$name.err"; then
        echo "OK"; SUCCEEDED=$((SUCCEEDED+1))
    else
        echo "FAILED:"
        cat "$OBJ_DIR/$name.err" 2>/dev/null || true
        FAILED=$((FAILED+1)); FAILED_FILES="$FAILED_FILES $name"
    fi
}

echo "=== winemetal unix (Objective-C) ==="
compile_objc "$DXMT_SRC/winemetal/unix/winemetal_unix.c" winemetal_unix
compile_objc "$DXMT_SRC/winemetal/unix/cache.c"          cache

echo "=== airconv (C++ 20, needs LLVM headers) ==="
for cpp in airconv_context.cpp air_type.cpp air_signature.cpp air_operations.cpp \
           dxbc_converter.cpp dxbc_converter_gs.cpp dxbc_converter_ts.cpp \
           dxbc_converter_basicblock.cpp dxbc_converter_cfg.cpp \
           dxbc_instructions.cpp dxbc_signature.cpp metallib_writer.cpp; do
    name=$(basename "$cpp" .cpp)
    compile_cxx "$DXMT_SRC/airconv/$cpp" "$name"
done
compile_cxx "$DXMT_SRC/airconv/nt/air_builder.cpp" air_builder
compile_cxx "$DXMT_SRC/airconv/nt/dxbc_converter_base.cpp" dxbc_converter_base
compile_cxx "$DXMT_SRC/airconv/transforms/lower_16bit_texread.cpp" lower_16bit_texread

echo "=== DXBCParser (uses exceptions — override) ==="
for cpp in BlobContainer.cpp DXBCUtils.cpp ShaderBinary.cpp; do
    name=dxbc_$(basename "$cpp" .cpp)
    # ShaderBinary uses `throw`, so we can't use -fno-exceptions from CXX_FLAGS.
    printf "  %-40s " "$name"
    if xcrun -sdk iphoneos clang++ $COMMON_FLAGS -std=c++20 -fno-rtti \
            $INCLUDES $INCLUDES_DIRECTX $AIRCONV_DEFS \
            -c "$DXMT_ROOT/libs/DXBCParser/$cpp" -o "$OBJ_DIR/$name.o" 2>"$OBJ_DIR/$name.err"; then
        echo "OK"; SUCCEEDED=$((SUCCEEDED+1))
    else
        echo "FAILED:"
        cat "$OBJ_DIR/$name.err" 2>/dev/null || true
        FAILED=$((FAILED+1)); FAILED_FILES="$FAILED_FILES $name"
    fi
done

echo ""
echo "Results: $SUCCEEDED succeeded, $FAILED failed"
if [ -n "$FAILED_FILES" ]; then
    echo "Failed:$FAILED_FILES"
    echo "See .err files in $OBJ_DIR/"
    exit 1
fi

echo "=== Compiling curses stub for iOS ==="
cat << 'EOF' > "$OBJ_DIR/curses_stub.c"
int setupterm(char *term, int fildes, int *errret) { if (errret) *errret = -1; return -1; }
int set_curterm(void *nterm) { return 0; }
int del_curterm(void *oterm) { return 0; }
int tigetnum(char *capname) { return -1; }
EOF
xcrun -sdk iphoneos clang $COMMON_FLAGS -c "$OBJ_DIR/curses_stub.c" -o "$OBJ_DIR/curses_stub.o"

echo ""
echo "=== Extracting LLVM static objects and converting to iOS platform ==="
LLVM_OBJ_DIR="$BUILD_DIR/llvm_obj"
mkdir -p "$LLVM_OBJ_DIR"
LLVM_CONFIG="$(brew --prefix llvm@15 2>/dev/null || brew --prefix llvm 2>/dev/null)/bin/llvm-config"
if [ -x "$LLVM_CONFIG" ]; then
    LLVM_LIB_DIR="$($LLVM_CONFIG --libdir)"
    for lib in "$LLVM_LIB_DIR"/libLLVM*.a; do
        if [ -f "$lib" ]; then
            libname=$(basename "$lib" .a)
            mkdir -p "$LLVM_OBJ_DIR/$libname"
            (cd "$LLVM_OBJ_DIR/$libname" && ar -x "$lib")
        fi
    done
    python3 "$BUILD_DIR/patch_macho_ios.py" "$LLVM_OBJ_DIR"
fi

echo "=== Archiving libdxmt_combined.a ==="
rm -f "$OUT_LIB"
find "$OBJ_DIR" "$LLVM_OBJ_DIR" -name "*.o" | xargs xcrun -sdk iphoneos ar -rcs "$OUT_LIB"
xcrun -sdk iphoneos ranlib "$OUT_LIB"
cp "$OUT_LIB" "$REPO_ROOT/app/Mythic/libdxmt_combined.a"
echo "Ready: $REPO_ROOT/app/Mythic/libdxmt_combined.a ($(wc -c < "$REPO_ROOT/app/Mythic/libdxmt_combined.a" | tr -d ' ') bytes)"

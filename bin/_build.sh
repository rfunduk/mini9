#!/usr/bin/env bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"

TARGET="${TARGET:-release}"

# MRUBY MACROS LIBRARY
MRUBY_INCLUDE="$SCRIPT_DIR/vendor/mruby/include"
MACROS_SRC="$SCRIPT_DIR/lib/mruby/macros.c"

#
# WEB BUILD
# first do a web build because the resulting
# assets will be bundled into the native executable
#
WEB_OUT_DIR="$SCRIPT_DIR/build/web"
mkdir -p $WEB_OUT_DIR

TARGET="${TARGET:-release}"
DEBUG_FLAG=""
ENGINE_DEBUG="false"
if [ $TARGET == "debug" ]; then
  DEBUG_FLAG="-g"
  ENGINE_DEBUG="true"
fi

# note *_WASM_LIB=env.o -- env.o is an internal WASM object file. you can
# see how *_WASM_LIB is used inside <odin>/vendor/raylib/raylib.odin or source/mruby_bindings.odin
#
# the emcc call will be fed the actual raylib & mruby library files
# and they will be included in env.o

echo "  Building for web..."
if ! odin build source/main_web \
      -define:RAYLIB_WASM_LIB=env.o \
      -define:BOX2D_LIB=env.o \
      -define:MRUBY_LIB=env.o \
      -define:MRUBY_MACROS_LIB=env.o \
      -collection:lib=lib \
      -target:js_wasm32 \
      -build-mode:obj \
      -vet -strict-style \
      -define:ENGINE_DEBUG=$ENGINE_DEBUG \
      -out:$WEB_OUT_DIR/engine; then
  echo "  Web build failed!"
  exit 1
fi

ODIN_PATH=$(odin root)
cp $ODIN_PATH/core/sys/wasm/js/odin.js $WEB_OUT_DIR
files="
  $WEB_OUT_DIR/engine.wasm
  ${ODIN_PATH}/vendor/raylib/wasm/libraylib.a
  vendor/mruby/build/emscripten/lib/libmruby.a
  vendor/box2d/build-wasm/src/libbox2d.a
  $WEB_OUT_DIR/macros.o
"
flags="
  -sUSE_GLFW=3
  -sWASM_BIGINT
  -sWARN_ON_UNDEFINED_SYMBOLS=0
  -sASSERTIONS
  -sASYNCIFY
  -sASYNCIFY_ONLY=[\"mrb_load_irep_cxt\",\"mrb_load_string_cxt\"]
  -sALLOW_TABLE_GROWTH=1
  -sALLOW_MEMORY_GROWTH=1
  -sINITIAL_MEMORY=67108864
  -sMAXIMUM_MEMORY=268435456
  -sFORCE_FILESYSTEM=1
  -sEXPORTED_RUNTIME_METHODS=[\"HEAPF32\"]
  --shell-file source/main_web/index_template.html
"


export EMSDK_QUIET=1
[[ -f "vendor/emsdk/emsdk_env.sh" ]] && . "vendor/emsdk/emsdk_env.sh"

emcc -c -I"$MRUBY_INCLUDE" "$MACROS_SRC" -o "$WEB_OUT_DIR/macros.o"
emcc $DEBUG_FLAG -o $WEB_OUT_DIR/index.html $files $flags
rm $WEB_OUT_DIR/engine.wasm
rm "$WEB_OUT_DIR/macros.o"

echo "  Web assets: ${WEB_OUT_DIR}"


#
# NATIVE BUILD
#

OUT_DIR="$SCRIPT_DIR/build/$TARGET"
mkdir -p "$OUT_DIR"

echo "  Building mruby macros..."
cc -c -I"$MRUBY_INCLUDE" "$MACROS_SRC" -o "$OUT_DIR/macros.o"

FLAGS="
  -out:$OUT_DIR/mini9 \
  -define:MRUBY_LIB=../../vendor/mruby/build/host/lib/libmruby.a \
  -define:MRUBY_MACROS_LIB=../../build/$TARGET/macros.o \
  -define:BOX2D_LIB=../../vendor/box2d/build/src/libbox2d.a \
  -define:BYTECODE_PACKAGING=true \
  -collection:lib=lib \
  -vet-packages:engine,mrb \
  -vet-style -vet-semicolon -vet-cast -vet \
"

if [ $TARGET == "debug" ]; then
  FLAGS+="
    -debug \
    -define:SAFE_DISPATCH=true \
    -define:CHECK_MRUBY_DATA_TYPES=true \
    -define:ENGINE_DEBUG=true \
    -define:USE_TRACKING_ALLOCATOR=true
  "
else
  FLAGS+="
    -no-bounds-check \
    -o:speed \
    -define:ENGINE_DEBUG=false
  "
fi

echo "  Building native binary..."
odin build source/main_native $FLAGS
rm "$OUT_DIR/macros.o"

echo "  Build created in $OUT_DIR"

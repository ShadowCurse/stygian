#!/bin/bash

cp -r assets wasm
cd wasm

emcc \
  -sUSE_SDL=2 \
  -sASSERTIONS=1 \
  -sMALLOC='dlmalloc' \
  -sFORCE_FILESYSTEM=1 \
  -sUSE_OFFSET_CONVERTER=1 \
  -sALLOW_MEMORY_GROWTH=1 \
  -sSTACK_SIZE=1mb \
  --embed-file assets@/assets \
  ../zig-out/lib/libstygian_unibuild_software_emscripten.a \
  -o \
  stygian.js

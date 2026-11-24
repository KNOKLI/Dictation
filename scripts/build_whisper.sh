#!/bin/zsh
# Собирает whisper.cpp статически в vendor/whisper (2026-11-25): приложение не зависит от Homebrew.
# Нужны только для сборки: git, cmake (brew install cmake). Пользователям ничего ставить не надо.
set -euo pipefail
cd "$(dirname "$0")/.."
VER=v1.9.5
SRC=vendor/whisper.cpp-src
OUT=$PWD/vendor/whisper
[[ -d $SRC ]] || git clone --depth 1 --branch $VER https://github.com/ggml-org/whisper.cpp.git $SRC
cmake -S $SRC -B $SRC/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DBUILD_SHARED_LIBS=OFF -DGGML_BACKEND_DL=OFF -DGGML_NATIVE=OFF \
  -DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16 \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_BLAS=ON -DGGML_OPENMP=OFF \
  -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF \
  -DCMAKE_INSTALL_PREFIX=$OUT >/dev/null
cmake --build $SRC/build -j 8 --config Release
cmake --install $SRC/build >/dev/null
echo "Готово: $OUT"; ls $OUT/lib

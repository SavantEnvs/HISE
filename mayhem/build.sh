#!/usr/bin/env bash
#
# mayhem/build.sh — builds the HLAC fuzz harness(es) and upstream's HLAC unit-test runner.
#
# HISE has no CMake/make build: its modules are unity-built into whatever Projucer project includes
# them. The mayhem targets only need the dependency-light modules (juce_core, juce_audio_basics,
# juce_audio_formats, hi_lac for the HLAC reader; juce_core, juce_events, juce_data_structures, hi_zstd
# for the zstd preset decompressor), so each of those is compiled here straight from its module .cpp.
# JUCE itself comes from the pinned dependency cache the Dockerfile fills (SPEC 6.2 item 19).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

JUCE_ROOT=$(ls -d /opt/toolchains/deps/juce-customized-* | head -n1)
OUT="$SRC/mayhem/build"          # gitignored by mayhem/.gitignore
SAN="$OUT/san" PLAIN="$OUT/plain"
mkdir -p "$SAN" "$PLAIN"

# JUCE_ROOT/inc is an empty directory next to JUCE_ROOT/JUCE: HISE's "../JUCE/modules/..." includes
# fall through to it when this checkout's JUCE submodule directory is empty.
DEFS=(-DNDEBUG=1 -DJUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1 -DJUCE_STANDALONE_APPLICATION=1
      -DJUCE_USE_CURL=0 -DJUCE_WEB_BROWSER=0 -DJUCE_MODAL_LOOPS_PERMITTED=0
      -DJUCE_MODULE_AVAILABLE_juce_core=1 -DJUCE_MODULE_AVAILABLE_juce_audio_basics=1
      -DJUCE_MODULE_AVAILABLE_juce_audio_formats=1 -DJUCE_MODULE_AVAILABLE_hi_lac=1
      -DJUCE_MODULE_AVAILABLE_juce_events=1 -DJUCE_MODULE_AVAILABLE_juce_data_structures=1
      -DJUCE_MODULE_AVAILABLE_hi_zstd=1)
# Exactly ONE copy of the JUCE modules may be visible, or their headers are redefined: the checked-out
# submodule when the build context carries it (CI: submodules: recursive), else the pinned cache copy.
if [ -f "$SRC/JUCE/modules/juce_core/juce_core.h" ]; then JUCE_MODULES="$SRC/JUCE/modules"; else JUCE_MODULES="$JUCE_ROOT/src/modules"; fi
INCS=(-I"$JUCE_ROOT/inc" -I"$JUCE_MODULES" -I"$SRC/mayhem/include")
CXXSTD=(-std=c++17 -w -fPIC)
LIBS=(-lpthread -ldl -lrt)

# SAN_CXX <src> <obj> [extra flags]: sanitized, DWARF<=3, SanCov-instrumented object
# ($SANITIZER_FLAGS carries no coverage flags, so fuzzer-no-link is added unconditionally).
SAN_CXX()  { local s=$1 o=$2; shift 2; $CXX "${CXXSTD[@]}" -O1 $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS "${DEFS[@]}" "${INCS[@]}" "$@" -c "$s" -o "$o"; }
# PLAIN_CXX <src> <obj> [extra flags]: the project's normal flags, for the test oracle.
PLAIN_CXX() { local s=$1 o=$2; shift 2; $CXX "${CXXSTD[@]}" -O2 $COVERAGE_FLAGS "${DEFS[@]}" "${INCS[@]}" "$@" -c "$s" -o "$o"; }

JUCE_MODS=(juce_core juce_audio_basics juce_audio_formats)
ZSTD_JUCE_MODS=(juce_core juce_events juce_data_structures)

# 1) JUCE objects (built once per tree; they are not edited by the project).
pids=()
for m in "${JUCE_MODS[@]}" juce_events juce_data_structures; do
  [ -s "$SAN/$m.o" ]   || { SAN_CXX   "$SRC/mayhem/juce/$m.cpp" "$SAN/$m.o"   & pids+=($!); }
  [ -s "$PLAIN/$m.o" ] || { PLAIN_CXX "$SRC/mayhem/juce/$m.cpp" "$PLAIN/$m.o" & pids+=($!); }
done
for p in "${pids[@]}"; do wait "$p"; done
pids=()

# 2) The project itself: hi_lac and hi_zstd (unity .cpp files), sanitized for fuzzing.
SAN_CXX "$SRC/hi_lac/hi_lac.cpp" "$SAN/hi_lac.o" & pids+=($!)
for u in hi_zstd_1 hi_zstd_2 hi_zstd_3; do
  SAN_CXX "$SRC/hi_zstd/$u.cpp" "$SAN/$u.o" & pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
SAN_CXX "$SRC/mayhem/lsan_off.cc" "$SAN/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$SAN/standalone_main.o"

# 3) Harnesses: libFuzzer binary + run-once standalone reproducer.
for h in fuzz_hlac_reader fuzz_zstd_expand; do
  SAN_CXX "$SRC/mayhem/$h.cpp" "$SAN/$h.o"
  if [ "$h" = fuzz_zstd_expand ]; then
    OBJS=("$SAN/$h.o" "$SAN/hi_zstd_1.o" "$SAN/hi_zstd_2.o" "$SAN/hi_zstd_3.o" "$SAN/lsan_off.o")
    for m in "${ZSTD_JUCE_MODS[@]}"; do OBJS+=("$SAN/$m.o"); done
  else
    OBJS=("$SAN/$h.o" "$SAN/hi_lac.o" "$SAN/lsan_off.o")
    for m in "${JUCE_MODS[@]}"; do OBJS+=("$SAN/$m.o"); done
  fi
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "${OBJS[@]}" "${LIBS[@]}" -o "/mayhem/$h"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "${OBJS[@]}" "$SAN/standalone_main.o" "${LIBS[@]}" -o "/mayhem/$h-standalone"
done

# 4) Upstream's HLAC and zstd unit tests with the project's NORMAL flags (no sanitizers); test.sh only runs them.
PLAIN_CXX "$SRC/hi_lac/hi_lac.cpp" "$PLAIN/hi_lac.o" -DHLAC_INCLUDE_TEST_SUITE=1
PLAIN_CXX "$SRC/tools/hlac_tool/Source/HlacTests.cpp" "$PLAIN/HlacTests.o" -DHLAC_INCLUDE_TEST_SUITE=1
PLAIN_CXX "$SRC/mayhem/hlac_unit_tests_main.cpp" "$PLAIN/hlac_unit_tests_main.o" -DHLAC_INCLUDE_TEST_SUITE=1
OBJS=("$PLAIN/hlac_unit_tests_main.o" "$PLAIN/HlacTests.o" "$PLAIN/hi_lac.o")
for m in "${JUCE_MODS[@]}"; do OBJS+=("$PLAIN/$m.o"); done
$CXX $COVERAGE_FLAGS "${OBJS[@]}" "${LIBS[@]}" -o "$OUT/hlac_unit_tests"

pids=()
for u in hi_zstd_1 hi_zstd_2 hi_zstd_3; do
  PLAIN_CXX "$SRC/hi_zstd/$u.cpp" "$PLAIN/$u.o" & pids+=($!)
done
PLAIN_CXX "$SRC/mayhem/zstd_unit_tests_main.cpp" "$PLAIN/zstd_unit_tests_main.o" & pids+=($!)
for p in "${pids[@]}"; do wait "$p"; done
OBJS=("$PLAIN/zstd_unit_tests_main.o" "$PLAIN/hi_zstd_1.o" "$PLAIN/hi_zstd_2.o" "$PLAIN/hi_zstd_3.o")
for m in "${ZSTD_JUCE_MODS[@]}"; do OBJS+=("$PLAIN/$m.o"); done
$CXX $COVERAGE_FLAGS "${OBJS[@]}" "${LIBS[@]}" -o "$OUT/zstd_unit_tests"

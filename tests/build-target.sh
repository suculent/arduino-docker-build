#!/usr/bin/env bash
#
# Build-chain smoke test: runs the real entrypoint (cmd.sh) against a dummy
# project and asserts that a plausible application image comes out.
#
# This exists because "docker build succeeded" says nothing about whether the
# image can compile a sketch. Six separate defects once shipped green that way,
# including one where the build reported SUCCESS while exporting the 3 kB
# partition table as firmware.bin.
#
set -euo pipefail

TARGET="${1:?usage: build-target.sh <esp8266|esp32>}"
SRC="/opt/tests/dummy-${TARGET}"
WS="/opt/workspace"
# Any real application image is far bigger than this; the esp32 partition table
# that used to be exported by mistake is 3 kB.
MIN_BYTES="${MIN_BYTES:-100000}"

[ -d "$SRC" ] || { echo "[test] FAIL: no dummy project at $SRC"; exit 1; }
cd /

prepare() {
  rm -rf "${WS:?}"
  mkdir -p "$WS"
  cp -R "$SRC/." "$WS/"
}

assert_firmware() {
  local phase="$1" size
  if [ ! -f "$WS/firmware.bin" ]; then
    echo "[test] FAIL (${phase}): firmware.bin was not exported"
    ls -la "$WS" || true
    exit 1
  fi
  size=$(stat -c%s "$WS/firmware.bin")
  if [ "$size" -lt "$MIN_BYTES" ]; then
    echo "[test] FAIL (${phase}): firmware.bin is ${size} B, below ${MIN_BYTES} B."
    echo "[test]   A too-small image means the wrong artefact was exported --"
    echo "[test]   e.g. the esp32 partition table instead of the application."
    ls -l "$WS/build"/*.bin 2>/dev/null || true
    exit 1
  fi
  echo "[test] OK (${phase}): firmware.bin ${size} B"
}

echo "[test] ${TARGET}: build 1/2 (clean workspace)"
prepare
/opt/cmd.sh
assert_firmware "clean build"

# Second build in the SAME workspace, deliberately leaving build/ behind.
# Arduino copies sketch-adjacent files into build/sketch/ with a "#line N"
# directive prepended, which used to shadow the real environment.json and
# silently drop every cflag on any rebuild. The dummy sketch #errors when its
# cflags are missing, so that regression fails here instead of shipping.
echo "[test] ${TARGET}: build 2/2 (rebuild over stale build/)"
rm -f "$WS/firmware.bin" "$WS/firmware.elf"
/opt/cmd.sh
assert_firmware "rebuild over stale build/"

echo "[test] ${TARGET}: PASS"

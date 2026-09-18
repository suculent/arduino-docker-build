#!/usr/bin/env bash
#
# Guard-the-guard: proves the build-chain tests can actually fail.
#
# The positive tests rely on the dummy sketch #error-ing when its cflags do not
# arrive. If those #ifndef guards ever stop tripping -- renamed define, sketch
# edited, environment.h no longer included -- the positive tests keep passing
# and silently assert nothing. This runs the same build with cflags REMOVED and
# requires it to fail, for that specific reason.
#
set -uo pipefail

WS=/opt/workspace
SRC=/opt/tests/dummy-esp8266
LOG=/tmp/negative-cflags.log
EXPECTED="cflags from environment.json never reached the compiler"

cd /
rm -rf "${WS:?}"
mkdir -p "$WS"
cp -R "$SRC/." "$WS/"

# Same project, but with the cflags key stripped out.
cat > "$WS/environment.json" <<'JSON'
{
  "ssid": "thinx-negative-test"
}
JSON

echo "[negative] building with cflags removed -- a FAILED build is the pass condition"
/opt/cmd.sh > "$LOG" 2>&1
rc=$?

if [ "$rc" -eq 0 ] && [ -f "$WS/firmware.bin" ]; then
  echo "[negative] FAIL: the build succeeded without cflags."
  echo "[negative]   The cflags guards in dummy.ino are not effective, which means"
  echo "[negative]   the positive build-chain tests are not really checking cflags."
  exit 1
fi

if ! grep -q "$EXPECTED" "$LOG"; then
  echo "[negative] FAIL: the build failed, but not via the expected guard."
  echo "[negative]   Expected to see: ${EXPECTED}"
  echo "[negative]   Got (last 30 lines):"
  tail -30 "$LOG"
  exit 1
fi

echo "[negative] OK: build failed on the cflags guard, as required"
echo "[negative] PASS"

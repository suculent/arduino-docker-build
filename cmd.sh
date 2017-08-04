#!/usr/bin/env bash

set -e

cd /opt/arduino-firmware

export PATH=$PATH:/opt/arduino/:/opt/arduino/java/bin/

if [ -z $DISPLAY ]; then
  echo "Simulating screen in headless mode, use `socat TCP-LISTEN:6000,reuseaddr,fork UNIX-CLIENT:\"$DISPLAY\"` "
  Xvfb :1 --nolisten tcp -ac -screen 0 1280x800x24 &
  xvfb="$!"
fi

if [ ! -z $@ ]; then
  echo "Running Arduino with arguments..."
  arduino "$@"
else
  echo "Testing Arduino..."
  pwd
  cd "test"
  arduino --verbose --pref build.path=$(pwd) --verify $(pwd)/test.ino
  ls
  cat *.txt
fi

echo "Done."

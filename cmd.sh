#!/usr/bin/env bash

cd /opt/arduino-firmware

export PATH=$PATH:/opt/arduino/:/opt/arduino/java/bin/

if [ -z $DISPLAY ]; then
  echo "Simulating screen in headless mode, use socat TCP-LISTEN:6000,reuseaddr,fork UNIX-CLIENT:\"$DISPLAY\" "
  Xvfb :1 -ac -screen 0 1280x800x24 &
  xvfb="$!"
fi

if [ ! -z $@ ]; then
  echo "Running Arduino with arguments..."
  arduino "$@"
else
  echo "Testing Arduino..."
  cd *
  pwd
  ls
  arduino --verbose --pref build.path=".." --verify ./*.ino
  ls ..
  cat ../*.txt
fi

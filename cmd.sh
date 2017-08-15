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
  echo "Building for Arduino..."
  pwd
  ls
  arduino --verbose --pref build.path=".." --verify ./*.ino
  ls
  mkdir ../build
  cp *.hex ../build/
  echo "Seaching for LINT results..."
  if [ -f "./*.txt" ];
    cat *.txt
    cp *.txt ../build/
  fi
fi

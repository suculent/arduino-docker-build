#!/usr/bin/env bash

cd /opt/workspace

export PATH=$PATH:/opt/arduino/:/opt/arduino/java/bin/

if [ -z $DISPLAY ]; then
  echo "Simulating screen in headless mode, use socat TCP-LISTEN:6000,reuseaddr,fork UNIX-CLIENT:\"$DISPLAY\" "
  Xvfb :1 -ac -screen 0 1280x800x24 &
  xvfb="$!"
fi

if [ ! -z $@ ]; then
  echo "Running from Docker for Arduino with arguments..."
  arduino "$@"
else
  echo "Building from Docker for Arduino..."
  #cd *
  pwd
  ls
  mkdir ../../build
  arduino --verbose --pref build.path="../../build" --verify ./*.ino
  RESULT=$?  
  echo "Seaching for LINT results..."
  if [ -f "../lint.txt" ]; then
    cat "../lint.txt"
    cp "../lint.txt" ../../lint.txt
  fi
  echo "Build artefacts in $(pwd):"
  #cd ../../build
  #cp ./*.with_bootloader.hex ../../firmware.bin
  #cp ./*.elf ../../
  #cd ../../
  pwd
  ls
  exit $RESULT
fi

#!/usr/bin/env bash

export PATH=$PATH:/opt/arduino/:/opt/arduino/java/bin/

set -e
set +e # skip errors

# Config options you may pass via Docker like so 'docker run -e "<option>=<value>"':
# - KEY=<value>

if [ -z "$WORKDIR" ]; then
  cd $WORKDIR
else
  echo "No working directory given."
  true
fi

if [ -z "$BOARD" ]; then
  BOARD="esp8266com:esp8266:d1_mini"
  echo "BOARD not defined, defaulting to $BOARD"
  if [ ! -f .board ]; then
    echo "You may store your desired value inside .board file in your repository."
  fi
fi

#
# Fetch libraries
#

if [[ ! -d /root/Arduino/hardware ]]; then
  mkdir -p /root/Arduino/hardware/esp8266com
  cd /root/Arduino/hardware/esp8266com
  git clone https://github.com/esp8266/Arduino.git esp8266
  cd esp8266/tools
  python get.py
fi

if [[ ! -d /root/Arduino/libraries ]]; then
  mkdir -p /root/Arduino/libraries
  cd /root/Arduino/libraries
  #git clone https://github.com/suculent/thinx-lib-esp8266-arduinoc
  arduino --install-library "THiNX"
fi

cd /opt/workspace

#
# Build
#

BUILD_DIR=/opt/workspace/build
if [[ -d $BUILD_DIR ]]; then
  rm -rf $BUILD_DIR
fi
mkdir $BUILD_DIR

RESULT=1

if [ -z $DISPLAY ]; then
  echo "Simulating screen in headless mode, use socat TCP-LISTEN:6000,reuseaddr,fork UNIX-CLIENT:\"$DISPLAY\" "
  Xvfb :1 -ac -screen 0 1280x800x24 &
  xvfb="$!"
fi

echo "Current directory: $(pwd)"
ls

if [ ! -z $@ ]; then
  echo "Running from Docker for Arduino with arguments..."
  arduino "$@"
else
  echo "Building from Docker for Arduino..."
  arduino --verbose --pref build.path="$BUILD_DIR" --board $BOARD --verify ./*.ino
  RESULT=$?
fi

if [[ $RESULT==1 ]]; then
  exit $RESULT
fi

#
# Export artefacts
#

echo "Seaching for LINT results..."
if [ -f "../lint.txt" ]; then
  cat "../lint.txt"
  cp -vf "../lint.txt" $BUILD_DIR/lint.txt
else
  echo "No lint results found..."
fi

echo "Build artefacts in $(pwd):"

pwd
ls

if [[ -f *.hex ]]; then
  cp -vf *.hex $BUILD_DIR
fi
if [[ -f *.elf ]]; then
  cp -vf *.elf $BUILD_DIR
fi

exit $RESULT

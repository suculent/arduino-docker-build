#!/usr/bin/env bash

export PATH=$PATH:/opt/arduino/:/opt/arduino/java/bin/
#set +e

set -e

# Config options you may pass via Docker like so 'docker run -e "<option>=<value>"':
# - KEY=<value>

if [ -z "$WORKDIR" ]; then
  cd $WORKDIR
else
  echo "No working directory given."
  true
fi

cd /opt/workspace

#
# Build
#

BUILD_DIR=/opt/workspace/build
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
  arduino --verbose --pref build.path="." --verify ./*.ino
  RESULT=$?
fi

if [[ $RESULT==1 ]]; then
  exit $RESULT
fi

#
# Export artefacts
#

if [[ -d $BUILD_DIR ]]; then
  rm -rf $BUILD_DIR
fi
mkdir build

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

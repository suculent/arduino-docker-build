#!/usr/bin/env bash

export PATH=$PATH:/opt/arduino/:/opt/arduino/java/bin/

parse_yaml() {
    local prefix=$2
    local s
    local w
    local fs
    s='[[:space:]]*'
    w='[a-zA-Z0-9_]*'
    fs="$(echo @|tr @ '\034')"
    sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" "$1" |
    awk -F"$fs" '{
    indent = length($1)/2;
    vname[indent] = $2;
    for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            printf("%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, $3);
        }
    }' | sed 's/_=/+=/g'
}

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

if [ -z "$FLASH_LD" ]; then
  echo "Using default flash_ld: d1_mini.build.flash_ld=eagle.flash.4m1m.ld"
else
  echo "Using custom flash_ld: $FLASH_LD"
  echo "$FLASH_LD" >> "/root/Arduino/hardware/esp8266com/esp8266/boards.txt"
fi

cd /opt/workspace

#
# Build
#

# Parse thinx.yml config

if [[ -f "thinx.yml" ]]; then
  echo "Reading thinx.yml:"
  eval $(parse_yaml thinx.yml)
  BOARD=${arduino_platform}:${arduino_arch}:${arduino_board}
  if [[ ! -z ${arduino_flash_ld} ]]; then
  	FLASH_LD="${arduino_board}.build.flash_ld=${arduino_flash_ld}"
  	echo "$FLASH_LD" >> "/root/Arduino/hardware/esp8266com/esp8266/boards.txt"
  fi
  echo "- board: $BOARD"
  echo "- libs: ${arduino_libs[@]}"
  echo "- flash_ld: $FLASH_LD"
fi

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

# Use default library if none set in thinx.yml
if [[ -z ${arduino_libs} ]]; then
	arduino_libs="THiNX"
fi

# Install managed libraries from thinx.yml
for lib in "${arduino_libs[@]}" do
	arduino --install-library $lib
done

# Install own libraries (overwriting managed libraries)
if [[ -d "./lib" ]]; then
    echo "Copying user libraries..."
    cp -vfR ./lib/** /root/Arduino/libraries
fi

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

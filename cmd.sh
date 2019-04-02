#!/usr/bin/env bash

export PATH=$PATH:/opt/arduino/:/opt/arduino/java/bin/

chmod +x /opt/arduino/arduino

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

set +e # skip errors

# Config options you may pass via Docker like so 'docker run -e "<option>=<value>"':
# - KEY=<value>

if [ -z "$WORKDIR" ]; then
  cd $WORKDIR
else
  echo "No custom working directory given, using current..."
  WORKDIR=$(PWD)
fi

cd /opt/workspace

#
# Build
#

# Parse thinx.yml config

SOURCE=.
F_CPU=80
FLASH_SIZE="4M"

YMLFILE=$(find /opt/workspace -name "thinx.yml" -maxdepth 2 | head -n 1)

if [[ ! -f $YMLFILE ]]; then
  echo "No thinx.yml found"
  exit 1
else
  echo "Reading thinx.yml:"
  cat "$YMLFILE"
  echo
  eval $(parse_yaml "$YMLFILE" "")
  BOARD=${arduino_platform}:${arduino_arch}:${arduino_board}

  # FLASH_LD this way may be already deprecated
  if [ ! -z "${arduino_flash_ld}" ]; then
  	FLASH_LD="${arduino_board}.menu.eesz.4M.build.flash_ld=${arduino_flash_ld}"
  	echo "$FLASH_LD" >> "/opt/arduino/hardware/espressif/esp8266/boards.txt"
  fi

  if [ ! -z "${arduino_flash_size}" ]; then
    FLASH_SIZE="${arduino_flash_size}"
  fi

  if [ ! -z "${arduino_f_cpu}" ]; then
    F_CPU="${arduino_f_cpu}"
  fi

  if [ ! -z "${arduino_source}" ]; then
    SOURCE="${arduino_source}"
  fi

  echo "- board: ${BOARD}"
  echo "- libs: ${arduino_libs}"
  echo "- flash_ld: $FLASH_LD"
  echo "- f_cpu: $F_CPU"
  echo "- flash_size: $FLASH_SIZE"
  echo "- source: $SOURCE"
fi

BUILD_DIR="/opt/workspace/build"
if [[ -d "$BUILD_DIR" ]]; then
  echo "Deleting: "
  ls $BUILD_DIR
  rm -vrf $BUILD_DIR
fi
mkdir $BUILD_DIR

RESULT=1

if [ -z "$DISPLAY" ]; then
  echo "Simulating screen in headless mode, use socat TCP-LISTEN:6000,reuseaddr,fork UNIX-CLIENT:\"$DISPLAY\" "
  Xvfb :99 &
  export DISPLAY=:99
  #Xvfb :1 -ac -screen 0 1280x800x24 &
  #xvfb="$!"
  # socat TCP-LISTEN:6000,reuseaddr,fork UNIX-CLIENT:\"$DISPLAY\"
  # export DISPLAY=:0.0
fi

cd $SOURCE

# Install own libraries (overwriting managed libraries)
if [ -d "./lib" ]; then
    echo "Copying user libraries..."
    cp -vfR ./lib/** /opt/arduino/libraries
fi

if [ -d "../lib" ]; then
    echo "Copying user libraries from folder level above..."
    cp -vfR ../lib/** /opt/arduino/libraries
fi

# Use default library if none set in thinx.yml
if [ -z "${arduino_libs}" ]; then
    arduino_libs="THiNX"
fi

# Install managed libraries from thinx.yml
for lib in ${arduino_libs}; do
  echo "Installing library $lib..."
	/opt/arduino/arduino --install-library $lib
done

echo "Installed libraries:"
ls -l /opt/arduino/libraries

# Locate nearest .ino file and enter its folder of not here
INO=$(find . -maxdepth 2 -name '*.ino')
if [ ! -f $INO ]; then
   echo "Finding sketch folder in " $(pwd)
   FOLDER=$(find . -maxdepth 4 -name '*.ino' -printf '%h' -quit | head -n 1)
   echo "Folder: " $FOLDER
   FILE=$(find $FOLDER -maxdepth 4 -name '*.ino' -quit | head -n 1)
   echo "Finding sketch file:"
   echo "File: " $FILE
   INO=$FOLDER/$FILE
   echo "INO:" $INO
   #pushd $FOLDER
fi


# exit on error
set -e

#pwd
#ls

if [ ! -z $@ ]; then
  echo "Running from Docker for Arduino with arguments..."
  /opt/arduino/arduino "$@"
else
  echo "Building from Docker for Arduino..."
  if [ ! -z $FOLDER ]; then
    echo "Build V1 (no folder)"

    echo "INO: ${INO}"

    /opt/arduino/arduino --verbose-build --verify \
    --pref build.path="/opt/workspace/build" \
    --pref build.f_cpu=$F_CPU \
    --pref build.flash_size=$FLASH_SIZE \
    --board $BOARD \
    $INO

    # /opt/arduino/arduino --verbose-build --verify --pref build.path="/opt/workspace/build" --pref build.f_cpu=80 --pref build.flash_size=4M --board d1_mini_pro "./src/src.ino"
    # /opt/arduino/arduino --verbose-build --verify --pref build.path="/opt/workspace/build" --pref build.f_cpu=$F_CPU --pref build.flash_size=$FLASH_SIZE --board $BOARD "${FILE}"
  else
    echo "Build V0 (with $INO) in $pwd"
    echo "Board: $BOARD"
    CMD="/opt/arduino/arduino --verbose-build --verify --pref build.path=$BUILD_DIR --pref build.f_cpu=$F_CPU --pref build.flash_size=$FLASH_SIZE --board $BOARD $INO"
    echo "CMD: ${CMD}"
    $(${CMD})
  fi
  RESULT=$?
fi

#if [ ! -z $FOLDER ]; then
    # popd $FOLDER
#fi

# Cleanup mess ig any...
rm -rf ./test
rm -rf ./.development
rm -rf ./.pioenvs
rm -rf ./build/**

#
# Export artefacts
#

pwd
ls -la

echo "Seaching for LINT results..."
if [ -f "../lint.txt" ]; then
  cat "../lint.txt"
  cp -vf "../lint.txt" $BUILD_DIR/lint.txt
else
  echo "No lint results found..."
fi

BUILD_PATH="/opt/workspace/build"
echo "Build artefacts (1) in $BUILD_PATH:"
ls -la $BUILD_PATH

echo "Build artefacts (2) in $BUILD_DIR:"
ls -la $BUILD_DIR

echo "Sketch dir:"
ls -la $BUILD_DIR/sketch

if [ -f *.hex ]; then
  cp -vf *.hex $BUILD_DIR
fi
if [[ -f *.elf ]]; then
  cp -vf *.elf $BUILD_DIR
fi

# Report build status using logfile
if [ $RESULT == 0 ]; then
  echo "THiNX BUILD SUCCESSFUL."
else
  echo "THiNX BUILD FAILED: $?"
fi

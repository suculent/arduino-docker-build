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

set +e # don't skip errors ("Selected library is not available" on install)

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

SOURCE=$(pwd)
F_CPU=80
FLASH_SIZE="4M"

YMLFILE=$(find /opt/workspace -name "thinx.yml" | head -n 1)

if [[ ! -f $YMLFILE ]]; then
  echo "No thinx.yml found"
  exit 1
else
  echo "Reading thinx.yml:"
  cat "$YMLFILE"
  echo
  eval $(parse_yaml "$YMLFILE" "")
  BOARD=${arduino_platform}:${arduino_arch}:${arduino_board}

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
  echo "- flash_ld: ${arduino_flash_ld} (esp8266)"
  echo "- partitions: ${PARTITIONS} (esp32)"
  echo "- f_cpu: $F_CPU"
  echo "- flash_size: $FLASH_SIZE"
  echo "- source: $SOURCE"
fi

# TODO: if platform = esp8266 (dunno why but this lib collides with ESP8266Wifi)
rm -rf /opt/arduino/libraries/WiFi

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

# Install own libraries (overwriting managed libraries)
if [ -d "./lib" ]; then
    echo "Copying user libraries..."
    cp -fR ./lib/** /opt/arduino/libraries
fi

# Use default library if none set in thinx.yml
if [ -z "${arduino_libs}" ]; then
    arduino_libs="THiNX"
fi

# Install managed libraries from thinx.yml
for lib in ${arduino_libs}; do
  echo "Installing library $lib..."
  set +e
	/opt/arduino/arduino --install-library $lib
  set -e
done

echo "Installed libraries:"
ls -la "/opt/arduino/libraries"

# before searching INOs, clear mess...
rm -rf ${SOURCE}/.development
rm -rf ${SOURCE}/lib/**/examples/**

# Locate nearest .ino file and enter its folder of not here
echo "Searching INO file in: ${SOURCE} from $(pwd)"
INO_FILE=$(find ${SOURCE} -name '*.ino') # todo: search only one
echo "INO Search Result: $INO_FILE"
if [[ ! -f $INO_FILE ]]; then
  echo "No INO found in " $(pwd)
  ls
  exit 1
fi

# Cleanup mess if any...
rm -rf ./test
rm -rf ./.development
rm -rf ./.pioenvs
rm -rf ./build/**

echo "==================== BUILDER STARTED ========================"

# exit on error
set +e

if [[ ! -z $@ ]]; then
  echo "Running builder..."
  /opt/arduino/arduino "$@"
else
  ls
  echo "Running builder..."
  echo "Sketch: $INO_FILE in: $(pwd)"
  echo "Target board: $BOARD"
  if [[ ${arduino_arch} == "esp32" ]]; then
    FLASH_INSERT="--pref build.partitions=$arduino_partitions"
  fi
  if [[ ${arduino_arch} == "esp8266" ]]; then
    FLASH_INSERT="--pref build.flash_ld=$arduino_flash_ld"
  fi
  CMD="/opt/arduino/arduino --verify --verbose-build $FLASH_INSERT --pref build.path=/opt/workspace/build --pref build.f_cpu=$arduino_f_cpu --pref build.flash_size=$arduino_flash_size --pref build.flash_ld=${arduino_flash_ld} --board $BOARD $INO_FILE"
  echo "Build command: ${CMD}"
  $(${CMD})
fi

echo "==================== BUILDER COMPLETED ========================"

#
# Export artefacts
#

echo "Seaching for Lint results..."
if [[ -f "../lint.txt" ]]; then
  echo "Lint output:"
  cat "../lint.txt"
  cp -vf "../lint.txt" $BUILD_DIR/lint.txt
else
  echo "No lint results found..."
fi

BUILD_PATH="/opt/workspace/build"
cd $BUILD_PATH

echo "Build artefacts in $BUILD_PATH:"
ls

# TODO: find one would be safer
BIN_FILE=$(find . -name '*.bin' | head -n 1)
ELF_FILE=$(find . -name '*.elf' | head -n 1)

if [[ ! -z $BIN_FILE ]]; then
  mv -v $BIN_FILE firmware.bin
  RESULT=0
fi

if [[ ! -z $ELF_FILE ]]; then
  chmod -x $ELF_FILE # security measure because the file gets built with +x and we don't like this
  mv -v $ELF_FILE firmware.elf
fi

if [[ -f "./build.options.json" ]]; then
  cat ./build.options.json
  echo ""
fi

# Report build status using logfile
if [[ $RESULT == 0 ]]; then
  echo "THiNX BUILD SUCCESSFUL."
else
  echo "THiNX BUILD FAILED: $RESULT"
fi

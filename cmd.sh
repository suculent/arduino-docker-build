#!/usr/bin/env bash

echo "arduino-docker-build-1.0.160-esp8266:${ESP8266_VERSION}-esp32:${ESP32_VERSION}"
echo $GIT_TAG

export PATH=$PATH:/opt/arduino/:/opt/arduino/java/bin/

chmod +x /opt/arduino/arduino

# Config options you may pass via Docker like so 'docker run -e "<option>=<value>"':
# - KEY=<value>

cd /opt/workspace

WORKDIR=$(pwd)

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

#
# Build
#

# Parse thinx.yml config

SOURCE=$(pwd)
F_CPU=80
FLASH_SIZE="4M"
TEST_SCRIPT=0
CFLAGS=""

YMLFILE=$(find /opt/workspace -name "thinx.yml" | head -n 1)

if [[ ! -f $YMLFILE ]]; then
  echo "No thinx.yml found"
  exit 1
else

  eval $(parse_yaml "$YMLFILE" "")
  BOARD=${arduino_platform}:${arduino_arch}:${arduino_board}
  echo "- board: ${BOARD}"

  if [ ! -z "${arduino_flash_size}" ]; then
    FLASH_SIZE="${arduino_flash_size}"
    echo "- flash_size: $FLASH_SIZE"
  fi

  if [ ! -z "${arduino_f_cpu}" ]; then
    F_CPU="${arduino_f_cpu}"
    echo "- f_cpu: $F_CPU"
  fi

  if [ ! -z "${arduino_source}" ]; then
    SOURCE="${arduino_source}"
    echo "- source: $SOURCE"
  fi

  if [ ! -z "${arduino_test}" ]; then
    TEST_SCRIPT="${arduino_test}"
  fi

  # output filename for the per-device environment file
  if [ ! -z "${environment_target}" ]; then
    ENVOUT="${WORKDIR}/${environment_target}" # e.g. src/env.h
    echo "- ENVOUT: ${ENVOUT}"
  fi

  echo "- libs: ${arduino_libs}"

  if [[ ! -z ${arduino_flash_ld} ]]; then
    echo "- flash_ld: ${arduino_flash_ld} (esp8266)"
  fi

  if [[ ! -z ${arduino_partitions} ]]; then
    PARTITIONS=${arduino_partitions} # may be deprecated
    echo "- partitions: ${arduino_partitions} (esp32)"
  fi

  echo "- test_script: $TEST_SCRIPT"
fi

# Parse environment.json
ENVFILE=$(find /opt/workspace -name "environment.json" | head -n 1)
ENVOUT=$(find /opt/workspace -name "environment.h" | head -n 1)

# echo "Will write to ENVOUT ${ENVOUT}"

if [[ ! -f $ENVFILE ]]; then
  echo "No environment.json found"
else
  echo "Generating per-device environment headers to: ${ENVOUT}"
  echo
  # Generate C-header from key-value JSON object
  arr=()
  # Print out header, will clear previous contents.
  echo "Touching file at ${ENVOUT}"
  touch ${ENVOUT}
  echo "/* This file is auto-generated. */" > ${ENVOUT}
  while IFS='' read -r keyname; do
    arr+=("$keyname")
    VAL=$(jq '.'$keyname $ENVFILE)

    if [[ ${keyname} == "cflags" ]]; then
      $CFLAGS+="${VAL}"
    else 
      NAME=$(echo "environment_${keyname}" | tr '[:lower:]' '[:upper:]')
      echo "#define ${NAME}" "$VAL" >> ${ENVOUT}
    fi
  done < <(jq -r 'keys[]' $ENVFILE)
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

echo "Cleaning libraries..."
rm -rf /opt/arduino/libraries/**

# Install own libraries (overwriting managed libraries)
if [ -d "./lib" ]; then
    echo "Copying user libraries..."
    cp -fR ./lib/** /opt/arduino/libraries
    # cp -fR ./lib8266/** /opt/arduino/libraries # should be ESP8266 only!
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

#echo "Installed libraries:"
#ls -la "/opt/arduino/libraries"

# before searching INOs, clear mess...
rm -rf ${SOURCE}/.development
rm -rf ${SOURCE}/lib/**/examples/**

# Locate nearest .ino file and enter its folder of not here
echo "Searching INO file in: ${SOURCE} from $(pwd)"
INO_FILE=$(find ${SOURCE} -maxdepth 3 -name '*.ino' ) # todo: search only one
echo "INO Search Result: $INO_FILE"
if [[ ! -f $INO_FILE ]]; then
  echo "None or too many INOs found in " $(pwd)
  exit 1
fi

# Cleanup mess if any...
#rm -rf ${SOURCE}/test
rm -rf ${SOURCE}/.development
rm -rf ${SOURCE}/.pioenvs
rm -rf ${SOURCE}/build/**

echo "-"

if [[ -f $TEST_SCRIPT ]]; then
  echo "Running test script ${TEST_SCRIPT}"
  # TODO ASAP: Manage test errors in order to break build immediately and prevent deploying build that failed tests.
  $( $TEST_SCRIPT )
else
  echo "No test script defined."
  echo
fi

echo "-"

# exit on error
set +e

if [[ ! -z $@ ]]; then
  echo "Running builder..."
  /opt/arduino/arduino "$@"
else
  echo "Running builder..."
  echo "Sketch: $INO_FILE in: $(pwd)"
  echo "Target board: $BOARD"
  if [[ ${arduino_arch} == "esp32" ]]; then
    FLASH_INSERT="--pref build.partitions=$arduino_partitions"
  fi
  if [[ ${arduino_arch} == "esp8266" ]]; then
    FLASH_INSERT="--pref build.flash_ld=$arduino_flash_ld"
  fi

  # original implementation without optional cflags (refactor to $CFLAGS_INSERT)
  if [[ "$CFLAGS" == "" ]]; then
    echo "Building normally."
    CMD="/opt/arduino/arduino \
    --verify \
    $FLASH_INSERT \
    --pref build.path=/opt/workspace/build \
    --pref build.f_cpu=$arduino_f_cpu \
    --pref build.flash_size=$arduino_flash_size \
    --pref build.flash_ld=${arduino_flash_ld} \
    --board $BOARD $INO_FILE"
  else
    echo "Building with CFLAGS: ${CFLAGS}"
    CMD="/opt/arduino/arduino \
    --verify \
    $FLASH_INSERT \
    --pref build.path=/opt/workspace/build \
    --pref build.f_cpu=$arduino_f_cpu \
    --pref build.flash_size=$arduino_flash_size \
    --pref build.flash_ld=${arduino_flash_ld} \
    --pref compiler.cpp.extra_flags=${CFLAGS} \
    --board $BOARD $INO_FILE"
  fi

  HR_CMD=$(echo "$CMD" | tr -s ' ')
  echo "Executing Build command: ${HR_CMD}"
  $CMD
fi

#
# Export artefacts
#

if [[ -f "../lint.txt" ]]; then
  echo "Lint output:"
  cat "../lint.txt"
  cp -vf "../lint.txt" $BUILD_DIR/lint.txt
else
  echo "No lint results found." #  TODO: Do something with them...
fi

BUILD_PATH="/opt/workspace/build"
cd $BUILD_PATH

BIN_FILE=$(find . -name '*.bin' | head -n 1)
ELF_FILE=$(find . -name '*.elf' | head -n 1)
SIG_FILE=$(find . -name '*.signed' | head -n 1)

if [[ ! -z $BIN_FILE ]]; then
  echo $BIN_FILE
  cp -v $BIN_FILE ../firmware.bin
  chmod 775 ../firmware.bin
  mv -v $BIN_FILE ./firmware.bin
  chmod 775 ./firmware.bin
  RESULT=0
fi

if [[ ! -z $ELF_FILE ]]; then
  echo $ELF_FILE
  chmod -x $ELF_FILE # security measure because the file gets built with +x and we don't like this
  cp -v $ELF_FILE ../firmware.elf
  chmod 775 ../firmware.elf
  mv -v $ELF_FILE ./firmware.elf
  chmod 775 ./firmware.elf
fi

if [[ ! -z $SIG_FILE ]]; then
  echo "Exporting signed binary..."
  echo $SIG_FILE
  rm -rf firmware.bin
  rm -rf ../firmware.bin
  cp -v $SIG_FILE ../firmware.bin
  chmod 775 ../firmware.bin
  mv -v $SIG_FILE ./firmware.bin
  chmod 775 ./firmware.bin
  RESULT=0
fi

# Report build status using logfile
if [[ $RESULT == 0 ]]; then
  # Do not touch, or be careful. This phrase is used later in log parsers to catch success state.
  echo "THiNX BUILD SUCCESSFUL."
else
  echo "THiNX BUILD FAILED: $?"
fi

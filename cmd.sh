#!/usr/bin/env bash

echo "arduino-docker-build-1.0.160-esp8266:${ESP8266_VERSION}-esp32:${ESP32_VERSION}"
echo $GIT_TAG

export PATH=$PATH:/opt/arduino/:/opt/arduino/java/bin/

chmod +x /opt/arduino/arduino

# Config options you may pass via Docker like so 'docker run -e "<option>=<value>"':
# - KEY=<value>

cd /opt/workspace

WORKDIR=$(pwd)

# --- thinx.yml ----------------------------------------------------------------
#
# thinx.yml is repository content, and the THiNX API writes decrypted devsec
# credentials into it before a build. It is read here and never eval'd or
# sourced: the old `eval $(parse_yaml ...)` ran any $(...), backtick or quote
# break-out in a value as shell, in a container that may hold docker.sock.
#
# thinx_yml_load FILE assigns, with plain `name=$value` assignments, only the
# names this script reads:
#   arduino_platform arduino_arch arduino_board arduino_flash_ld arduino_f_cpu
#   arduino_flash_size arduino_partitions arduino_libs arduino_source
#   arduino_test environment_target
# Any other name is ignored. Nothing is exported and nothing is printed.
#
# Names follow the old parse_yaml: the parent keys joined with "_" (two spaces
# of indent per level), e.g. arduino: / board: -> arduino_board. Values:
#  - key: "..."  quotes dropped; \" and \\ decoded (the escapes eval used to
#    decode the same way); any other backslash stays as it is;
#  - - "..."     a double-quoted list item: the same;
#  - key: ...    taken as written: $, `, ;, \ and quotes stay literal;
#  - a trailing CR (CRLF files) is dropped;
#  - a value that continues on the next line (block scalar |/>, folded plain
#    or multi-line quoted scalar) or holds a control character other than
#    tab (NUL included) is rejected; its variable is left as it was.
# A list item (`- item` under a key) used to append to a bash array, and this
# script reads ${name}, the array's first element. So for every name but
# arduino_libs a list item only sets a name that has no value yet: test: with
# the items "- a.sh" and "- b.sh" still gives arduino_test=a.sh.
# arduino_libs is the exception: its list items are joined with newlines, in
# order, so libs: with "- A", "- B" and "- C" gives arduino_libs="A<NL>B<NL>C"
# and arduino_install_libs installs all three (until 0.8.221 only the first
# was installed). A plain `libs: "A B"` is one library named "A B". A value
# never holds a newline of its own (multi-line values are rejected), so the
# newline only ever separates items.
#
# Same awk as thinx_yml_load in the THiNX worker (services/worker/builder-lib.sh)
# and the platformio, nodemcu and micropython builder images; keep them in step.
# A missing FILE sets nothing. Returns 0.
thinx_yml_load()
{
	[ -f "$1" ] || return 0

	thinx_yml_pairs=$(tr '\000' '\001' < "$1" | awk '
		function unescape_dq(s,    out, i, n, c, d) {
			out = ""
			n = length(s)
			for (i = 1; i <= n; i++) {
				c = substr(s, i, 1)
				if (c == "\\" && i < n) {
					d = substr(s, i + 1, 1)
					if (d == "\\" || d == "\"") {
						out = out d
						i++
						continue
					}
				}
				out = out c
			}
			return out
		}
		function flush() {
			if (pending != "") print pending
			pending = ""
		}
		{
			line = $0
			sub(/\r$/, "", line)
			match(line, /^[ \t]*/)
			ind = substr(line, 1, RLENGTH)
			rest = substr(line, RLENGTH + 1)
			match(rest, /^[A-Za-z0-9_]*/)
			key = substr(rest, 1, RLENGTH)
			rest = substr(rest, RLENGTH + 1)

			if (rest ~ /^[ \t]*:[ \t]*".*"[ \t]*$/) {
				style = "dq"
			} else if (rest ~ /^[ \t]*[:-]/) {
				style = "plain"
			} else {
				# Not a key line. Blank lines and comments are skipped;
				# anything else continues the previous value, which is
				# then multi-line and rejected.
				if (line !~ /^[ \t]*(#.*)?$/) pending = ""
				next
			}

			flush()

			indent = length(ind) / 2
			vname[indent] = key
			for (i in vname) { if (i > indent) { delete vname[i] } }

			value = rest
			if (style == "dq") {
				sub(/^[ \t]*:[ \t]*"/, "", value)
				sub(/"[ \t]*$/, "", value)
				value = unescape_dq(value)
			} else {
				sub(/^[ \t]*[:-][ \t]*/, "", value)
				if (value ~ /^".*"[ \t]*$/) {
					# - "item": eval dropped these quotes too.
					sub(/[ \t]*$/, "", value)
					value = unescape_dq(substr(value, 2, length(value) - 2))
				}
			}

			if (length(value) == 0) next
			if (style == "plain" && value ~ /^[|>][-+0-9]*[ \t]*$/) next

			tabless = value
			gsub(/\t/, "", tabless)
			if (tabless ~ /[[:cntrl:]]/) next

			vn = ""
			for (i = 0; i < indent; i++) { vn = (vn)(vname[i])("_") }
			name = vn key
			# A trailing "_" is a list item: the old parse_yaml made it "+=".
			op = "="
			if (sub(/_$/, "", name)) op = "+="
			if (name !~ /^[A-Za-z_][A-Za-z0-9_]*$/) next

			pending = name op value
		}
		END { flush() }
	')

	# The here-document expands $thinx_yml_pairs once; its text is not
	# expanded again, and each value is assigned, never evaluated.
	# `[ append ] && [ already set ] || name=value` skips a list item when the
	# name already has a value (see above); everything else assigns.
	# arduino_libs appends list items after a newline instead.
	thinx_yml_nl='
'
	while IFS= read -r thinx_yml_line
	do
		thinx_yml_name=${thinx_yml_line%%=*}
		thinx_yml_value=${thinx_yml_line#*=}
		thinx_yml_append=
		case "$thinx_yml_name" in
			*+) thinx_yml_append=1; thinx_yml_name=${thinx_yml_name%+} ;;
		esac
		case "$thinx_yml_name" in
			arduino_platform) [ -n "$thinx_yml_append" ] && [ -n "${arduino_platform+set}" ] || arduino_platform=$thinx_yml_value ;;
			arduino_arch) [ -n "$thinx_yml_append" ] && [ -n "${arduino_arch+set}" ] || arduino_arch=$thinx_yml_value ;;
			arduino_board) [ -n "$thinx_yml_append" ] && [ -n "${arduino_board+set}" ] || arduino_board=$thinx_yml_value ;;
			arduino_flash_ld) [ -n "$thinx_yml_append" ] && [ -n "${arduino_flash_ld+set}" ] || arduino_flash_ld=$thinx_yml_value ;;
			arduino_f_cpu) [ -n "$thinx_yml_append" ] && [ -n "${arduino_f_cpu+set}" ] || arduino_f_cpu=$thinx_yml_value ;;
			arduino_flash_size) [ -n "$thinx_yml_append" ] && [ -n "${arduino_flash_size+set}" ] || arduino_flash_size=$thinx_yml_value ;;
			arduino_partitions) [ -n "$thinx_yml_append" ] && [ -n "${arduino_partitions+set}" ] || arduino_partitions=$thinx_yml_value ;;
			arduino_libs)
				if [ -n "$thinx_yml_append" ] && [ -n "${arduino_libs+set}" ]; then
					arduino_libs=$arduino_libs$thinx_yml_nl$thinx_yml_value
				else
					arduino_libs=$thinx_yml_value
				fi ;;
			arduino_source) [ -n "$thinx_yml_append" ] && [ -n "${arduino_source+set}" ] || arduino_source=$thinx_yml_value ;;
			arduino_test) [ -n "$thinx_yml_append" ] && [ -n "${arduino_test+set}" ] || arduino_test=$thinx_yml_value ;;
			environment_target) [ -n "$thinx_yml_append" ] && [ -n "${environment_target+set}" ] || environment_target=$thinx_yml_value ;;
		esac
	done <<THINX_YML_PAIRS
$thinx_yml_pairs
THINX_YML_PAIRS

	unset thinx_yml_pairs thinx_yml_line thinx_yml_name thinx_yml_value thinx_yml_append thinx_yml_nl
	return 0
}

# arduino_install_libs ARDUINO: installs each library in $arduino_libs (one
# name per line, see thinx_yml_load) with `ARDUINO --install-library NAME`, in
# order; THiNX when $arduino_libs is empty.
#
# Each name is passed as one quoted argument: no word-splitting, no globbing,
# and arduino's stdin is /dev/null, not the list. Blanks around a name are
# trimmed. A name is installed only if it matches, in the C locale,
#   ^[A-Za-z0-9_][A-Za-z0-9 _.-]*(:[A-Za-z0-9._+-]+)?$   (at most 128 chars)
# i.e. an Arduino library name (letters, digits, space, _ . -; it must not
# start with a dash or a space) with an optional :version, which is what
# `arduino --install-library name[:version]` takes. Anything else, a comma
# (arduino would read it as a second library) included, is skipped with a
# "Skipping library" line. A failed install (library not available, or the
# same version already installed: arduino exits 1) is logged and the next one
# runs. Returns 0. Plain POSIX sh, so tests/thinx-yml-loader.sh can run it.
arduino_install_libs()
{
	arduino_install_list=${arduino_libs:-THiNX}
	while IFS= read -r arduino_install_lib
	do
		arduino_install_lib=${arduino_install_lib#"${arduino_install_lib%%[! 	]*}"}
		arduino_install_lib=${arduino_install_lib%"${arduino_install_lib##*[! 	]}"}
		[ -n "$arduino_install_lib" ] || continue
		if [ "${#arduino_install_lib}" -gt 128 ] ||
			! printf '%s\n' "$arduino_install_lib" |
				LC_ALL=C grep -Eq '^[A-Za-z0-9_][A-Za-z0-9 _.-]*(:[A-Za-z0-9._+-]+)?$'
		then
			echo "Skipping library '$arduino_install_lib': not a valid library name[:version]"
			continue
		fi
		echo "Installing library $arduino_install_lib..."
		if "$1" --install-library "$arduino_install_lib" < /dev/null; then
			:
		else
			echo "Library $arduino_install_lib not installed (arduino exited $?)"
		fi
	done <<THINX_LIBS
$arduino_install_list
THINX_LIBS
	unset arduino_install_list arduino_install_lib
	return 0
}

set +e # don't skip errors ("Selected library is not available" on install)

#
# Build
#

# Parse thinx.yml config

SOURCE=$(pwd)
F_CPU=80
FLASH_SIZE="4M"
TEST_SCRIPT="false"
CFLAGS=""

BUILD_DIR="/opt/workspace/build"

# Arduino copies sketch-adjacent files into <build>/sketch/ with a "#line N ..."
# directive prepended, so a stale build tree left by a previous run contains an
# environment.json that is NOT valid JSON. find's traversal returned that copy
# first, jq then failed with "Invalid numeric literal" and every cflag and
# environment define was silently dropped on any second build in a workspace.
# Never discover build inputs inside the build directory.
find_input() { # $1 = -name pattern
  find /opt/workspace -path "$BUILD_DIR" -prune -o -name "$1" -print | head -n 1
}

YMLFILE=$(find_input "thinx.yml")

if [[ ! -f $YMLFILE ]]; then
  echo "No thinx.yml found"
  exit 1
else

  thinx_yml_load "$YMLFILE"
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

  echo "- libs: ${arduino_libs//$'\n'/, }"

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
ENVFILE=$(find_input "environment.json")
ENVOUT=$(find_input "environment.h")

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
      # Append the raw cflags value to CFLAGS (passed later as
      # --pref compiler.cpp.extra_flags). Use jq -r so the compiler flags are
      # not wrapped in literal JSON quotes. NOTE: the leading "$" here used to
      # expand $CFLAGS and run "+=..." as a command, silently dropping cflags.
      CFLAGS+=$(jq -r '.cflags' "$ENVFILE")
    else
      NAME=$(echo "environment_${keyname}" | tr '[:lower:]' '[:upper:]')
      echo "#define ${NAME}" "$VAL" >> ${ENVOUT}
    fi
  done < <(jq -r 'keys[]' $ENVFILE)
fi

# TODO: if platform = esp8266 (dunno why but this lib collides with ESP8266Wifi)
rm -rf /opt/arduino/libraries/WiFi

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

# Install managed libraries from thinx.yml (THiNX when none are set).
arduino_install_libs /opt/arduino/arduino
# The old install loop ran `set -e` after each library and left it on, and the
# test-script step below relies on it ("Breaks build in case of failure").
set -e

#echo "Installed libraries:"
#ls -la "/opt/arduino/libraries"

# before searching INOs, clear mess...
rm -rf ${SOURCE}/.development
rm -rf ${SOURCE}/lib/**/examples/**

# Locate nearest .ino file and enter its folder of not here
echo "Searching INO file in: ${SOURCE} from $(pwd)"
INO_FILE=$(find ${SOURCE} -maxdepth 3 -path "$BUILD_DIR" -prune -o -name '*.ino' -print ) # todo: search only one
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

if [[ -f "./$TEST_SCRIPT" ]]; then
  echo "Running test script ${TEST_SCRIPT}"
  # Breaks build in case of failure, as required.
  $( $TEST_SCRIPT )
else
  echo "No test script defined."
  echo
fi

echo "-"

#  no exit on error (will be processed later)
set -e

if [[ ! -z $@ ]]; then
  echo "Running builder..."
  /opt/arduino/arduino "$@"
else
  echo "Running builder..."
  echo "Sketch: $INO_FILE in: $(pwd)"
  echo "Target board: $BOARD"
  # Build the arduino-builder argv as an array so multi-word values survive as
  # single arguments. A multi-flag CFLAGS (e.g. "-DDEBUG=1 -DFOO") must reach
  # arduino as ONE "compiler.cpp.extra_flags=..." token; the previous unquoted
  # "$CMD" string was word-split and only the first flag landed on the pref.
  cmd=( /opt/arduino/arduino --verify )

  # Only override a board default when thinx.yml actually supplies a value.
  # "--pref build.flash_ld=" (empty) REPLACES the board's own default with the
  # empty string instead of falling back to it; flash_ld was previously emitted
  # twice, both times possibly empty.
  add_pref() { # $1 = pref name, $2 = value
    if [[ -n "$2" ]]; then cmd+=( --pref "$1=$2" ); fi
  }

  if [[ ${arduino_arch} == "esp32" ]]; then
    add_pref "build.partitions" "$arduino_partitions"
  fi

  add_pref "build.f_cpu" "$arduino_f_cpu"
  add_pref "build.flash_size" "$arduino_flash_size"
  add_pref "build.flash_ld" "$arduino_flash_ld"

  cmd+=(
    --pref "build.path=/opt/workspace/build"
    # compiler.warning_level MUST be set explicitly. The esp8266 core builds its
    # warning flags as -c "{compiler.warning_flags}-cppflags", expecting
    # {compiler.warning_flags} to expand to a GCC @-response-file path
    # (tools/warnings/none). With no compiler.warning_level in preferences.txt the
    # IDE expands it to the empty string, leaving a literal "-cppflags" on the
    # command line, and EVERY esp8266 build dies with:
    #   xtensa-lx106-elf-g++: error: unrecognized command-line option '-cppflags'
    # "none" matches the core's own default (platform.txt: warnings/none).
    --pref "compiler.warning_level=none"
  )

  if [[ -n "$CFLAGS" ]]; then
    # compiler.cpp.extra_flags is NOT a free user slot on every core, and --pref
    # REPLACES it rather than appending. The esp32 core defaults it to "-MMD -c"
    # and puts it first in recipe.cpp.o.pattern, so overwriting it drops the -c:
    # g++ then tries to LINK each translation unit and the build dies with
    # "undefined reference to `main'". esp8266 leaves it empty, which is why
    # this only ever bit esp32. Read the core's own default out of its
    # platform.txt and keep it in front of our flags.
    CORE_EXTRA=""
    PLATFORM_TXT=$(find /opt/arduino/hardware /root/.arduino15/packages \
      -name platform.txt -path "*${arduino_arch}*" 2>/dev/null | head -n 1)
    if [[ -f "$PLATFORM_TXT" ]]; then
      CORE_EXTRA=$(sed -n 's/^compiler\.cpp\.extra_flags=//p' "$PLATFORM_TXT" | head -n 1)
      echo "Core default compiler.cpp.extra_flags (${PLATFORM_TXT}): '${CORE_EXTRA}'"
    else
      echo "WARNING: no platform.txt found for arch '${arduino_arch}'; cflags may drop core defaults"
    fi
    echo "Building with CFLAGS: ${CFLAGS}"
    cmd+=( --pref "compiler.cpp.extra_flags=${CORE_EXTRA:+${CORE_EXTRA} }${CFLAGS}" )
  else
    echo "Building normally."
  fi

  cmd+=( --board "$BOARD" "$INO_FILE" )

  echo "Executing Build command: ${cmd[*]}"
  "${cmd[@]}"
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

# The esp32 core emits several .bin artefacts beside the application image:
# <sketch>.bootloader.bin, <sketch>.partitions.bin and <sketch>.merged.bin.
# find's traversal order is arbitrary, so this used to export whichever came
# first -- in practice the 3 kB partition table -- as firmware.bin for every
# esp32 build, leaving the real application image behind. esp8266 emits only
# one .bin, so it happened to work there. Exclude the non-application artefacts.
BIN_FILE=$(find . -name '*.bin' \
  ! -name '*.bootloader.bin' ! -name '*.partitions.bin' ! -name '*.merged.bin' \
  | head -n 1)
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

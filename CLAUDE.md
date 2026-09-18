# CLAUDE.md

Guidance for working in this repo (the THiNX Arduino Docker build images).

## What this repo produces

Three Docker images on Docker Hub (`suculent/arduino-docker-build`), all built
from a shared base of Arduino IDE 1.8.19 + ESP toolchains:

| Tag       | Dockerfile           | Contents                          |
|-----------|----------------------|-----------------------------------|
| `latest`  | `Dockerfile`         | "Fat" image: ESP32 **and** ESP8266 |
| `esp32`   | `Dockerfile.esp32`   | ESP32-only                        |
| `esp8266` | `Dockerfile.esp8266` | ESP8266-only                      |

`cmd.sh` is the container entrypoint (the actual build driver invoked at runtime).

## Deployment is NON-TRIVIAL — read before pushing

CI (`.circleci/config.yml`) routes each deploy job to a **different git branch**
via branch filters. There is **one Dockerfile per image, but one branch per deploy**:

| Deploy job   | Triggers on branch | Builds               |
|--------------|--------------------|----------------------|
| `deployFat`  | `master` / `test`  | `Dockerfile`         |
| `deploy32`   | `esp32`            | `Dockerfile.esp32`   |
| `deploy8266` | `esp8266`          | `Dockerfile.esp8266` |

The `test` job runs on every branch and is a prerequisite; "test" here just means
**`docker build` succeeds** — there are no unit tests.

Consequences:
- **Pushing to `master` alone only redeploys the Fat image.** To ship esp32/esp8266
  changes you must also land the commit on the `esp32` and `esp8266` branches.
- The `esp32` / `esp8266` branches have historically **diverged** from `master`
  (older base images like `bullseye` and older `ESP*_VERSION` values), so they are
  not guaranteed to be fast-forwards. Always verify before pushing:
  `git ls-remote origin refs/heads/master refs/heads/esp32 refs/heads/esp8266`
  — if the three SHAs match, a plain push to all three is a fast-forward.
  (As of the DHI migration they were unified at `f2d940c`.)
- To unify all three on the master-line content when they *have* diverged,
  force-push the same commit — this overwrites divergent branch history, so
  confirm with the maintainer first:
  `git push --force origin <sha>:esp32 && git push --force origin <sha>:esp8266`
- Remote is named `origin` (`git@github.com:suculent/arduino-docker-build.git`).
  The repo is often checked out in **detached HEAD** at master's tip, so push
  explicitly by SHA or `HEAD:<branch>` rather than relying on the current branch.

## Verifying a base-image / dependency change

Builds target **linux/amd64** (see `build_and_push.sh`), so on Apple Silicon they
run under emulation (slow — the ESP32 image is ~5 GB and clones submodules).

To validate before pushing, build each Dockerfile with a full, uncached log:

```bash
docker build --no-cache --progress=plain --platform linux/amd64 \
  --build-arg GIT_TAG="$(git describe)" -f Dockerfile -t local-test .
```

When upgrading the Debian base, capture a baseline log on the OLD image first, then
diff against the new one — apt package availability is the usual breakage point.

### Long-standing build failures (fixed — keep them fixed)

`docker build` succeeding does **not** mean the image can compile a sketch. Both
targets used to fail at *runtime*, and both reproduced identically in the
published `suculent/arduino-docker-build:latest` (Debian 12 bookworm), so they
predated the trixie and DHI migrations. Always smoke-test an actual sketch, not
just the build.

- **esp8266: every build failed** with
  `xtensa-lx106-elf-g++: error: unrecognized command-line option '-cppflags'`.
  The core's `platform.txt:90` sets
  `compiler.cpp.flags=-c "{compiler.warning_flags}-cppflags" ...`, expecting
  `{compiler.warning_flags}` to expand to a GCC `@`-response-file path
  (`tools/warnings/none`, which *does* ship — along with `default-*`, `more-*`
  and `extra-*`). But `preferences.txt` carries **no `compiler.warning_level`
  key**, so the IDE expands the placeholder to the empty string and leaves a
  literal `-cppflags` on the command line. `compiler.c.flags:79` and
  `compiler.c.elf.flags:84` have the same construct.
  **Fix:** `cmd.sh` passes `--pref compiler.warning_level=none` (matching the
  core's own default). Do not drop it.

- **esp32: every build failed** with `Error: esp32: Unknown package`, because the
  Fat `Dockerfile` cloned arduino-esp32 straight into
  `/root/.arduino15/packages/esp32/`. That is not a layout Arduino 1.8.x
  recognises: the board-manager tree needs
  `packages/<packager>/hardware/<arch>/<version>/`.
  **Fix:** the Fat image now installs the core the same way `Dockerfile.esp32`
  does — into `/opt/arduino/hardware/espressif/esp32` (`HW_PATH`) — so both
  images expose the **same FQBN, `espressif:esp32:<board>`**, and one thinx.yml
  works on either.
  If you ever need the board-manager FQBN `esp32:esp32:<board>` instead, the
  other working layout is `packages/esp32/hardware/esp32/${ESP32_VERSION}/`;
  both resolve, but don't let the two images disagree.
  Fixing the layout exposed a second, separate esp32 blocker: **`python3-serial`
  (pyserial) is required**. A manual/git core install ships esptool as a Python
  package whose loader does `import serial` (the Board Manager build bundles a
  binary instead), so `elf2image` died with `ModuleNotFoundError: No module
  named 'serial'`. It is now in the apt list of `Dockerfile` and
  `Dockerfile.esp32` — the two that carry the esp32 core. `Dockerfile.esp8266`
  does not need it.

  Note esp32 and esp8266 do **not** share `thinx.yml` value formats: esp32's
  esptool wants `flash_size: "4MB"` where esp8266 wants `"4M"`, and the Arduino
  board id is `esp32` ("ESP32 Dev Module") — `esp32dev` is a PlatformIO name and
  is rejected as `Unknown board`.

- **cflags and all environment defines were silently dropped on any second build
  in the same workspace.** Arduino copies sketch-adjacent files into
  `<build>/sketch/` with a `#line N "..."` directive prepended, so a stale build
  tree contains an `environment.json` that is *not* valid JSON. `find`'s
  traversal returned that copy first and `jq` died with
  `parse error: Invalid numeric literal at line 1, column 6` — non-fatal, so the
  build continued with no `compiler.cpp.extra_flags` at all. The `build/` cleanup
  ran *after* this discovery, so it could not help.
  **Fix:** `cmd.sh` discovers inputs through `find_input()`, which prunes
  `$BUILD_DIR`. Use it for anything looked up under `/opt/workspace`.

- **Empty prefs clobbered board defaults.** `cmd.sh` emitted
  `--pref build.flash_ld=` (twice) and empty `build.f_cpu` / `build.flash_size`
  when `thinx.yml` omitted them, replacing the board's own default with an empty
  string rather than falling back to it.
  **Fix:** `add_pref()` only appends a pref when the value is non-empty.
  Note `F_CPU=80` / `FLASH_SIZE="4M"` near the top of `cmd.sh` are **logging
  only** — the argv reads `$arduino_f_cpu` / `$arduino_flash_size` directly.
  Don't "fix" them by wiring them in: `80` is not a valid esp8266 `f_cpu`
  (it wants Hz, e.g. `80000000L`), so the board default is the safer fallback.

### Base image: Docker Hardened Images (DHI)

Base image is `dhi.io/debian-base:trixie-dev` (migrated from `debian:13.5-slim`,
which came from `bookworm`). Same pattern as `../platformio-docker-build`.

- **`dhi.io` refuses anonymous pulls**, even for publicly entitled repos. Run
  `docker login dhi.io` (Docker Hub credentials — DHI is gated on Hub accounts)
  before building locally. In CI every job that runs `docker/build` needs a
  second `docker/check: {registry: dhi.io}` step alongside the Docker Hub one.
- **Use the `-dev` variant, never the bare `:trixie` runtime variant.** The
  runtime variant ships no package manager and no compiler, and defaults to
  `USER 65532`; these images are build toolchains that need apt at build time,
  gcc/python3/git at run time, and root-owned `/root/.arduino15`.
- **DHI strips `init-system-helpers`.** `x11-common`'s postinst calls
  `update-rc.d` and exits 127 without it, which cascades into `xvfb`,
  `libxtst6`, `libxi6`, `libsm6`, `libice6` and friends failing to configure —
  a hard build failure. All three Dockerfiles therefore install
  `init-system-helpers` in a separate apt step *before* the main package list.
  The X11 stack can't be dropped instead: `cmd.sh` starts `Xvfb :99` at runtime.
- `ca-certificates` is declared explicitly in the package list. The DHI base
  already ships it, but it was previously only inherited from `debian:slim`
  while `curl https://downloads.arduino.cc` and `git clone https://` depend on it.

### Known Debian 13 (trixie) notes

- **`software-properties-common` was removed in trixie** and is not needed here
  (`add-apt-repository` is never used) — it was dropped from all three Dockerfiles.
- Trixie ships Python 3.13 and `pip` enforces PEP 668 (externally-managed). The
  Dockerfiles don't `pip install` directly (ESP `get.py` only downloads toolchains),
  so this hasn't bitten — but watch for it if adding pip steps.
- All other apt packages kept the same names across the bookworm→trixie jump.

## Conventions

- `*.build.log` files are local build artifacts — **do not commit them.**
- `CHANGELOG.md` tracks `cmd.sh` build-feature versions (e.g. `cflags` support),
  not image/base-OS versions.

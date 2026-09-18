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

### Pre-existing runtime failures — do NOT mistake these for your regression

`docker build` succeeding does **not** mean the image can compile a sketch. Both
targets currently fail at *runtime*, and both reproduce identically in the
published `suculent/arduino-docker-build:latest` (Debian 12 bookworm), so they
predate the trixie and DHI migrations:

- **esp8266 — every** build fails with
  `xtensa-lx106-elf-g++: error: unrecognized command-line option '-cppflags'`.
  Origin is the esp8266 core's `platform.txt:90`, where
  `-c "{compiler.warning_flags}-cppflags"` is meant to expand to a GCC `@`-response
  file (`tools/warnings/none-cppflags`) but `{compiler.warning_flags}` expands
  empty, leaving the literal `-cppflags`. Note the core ships `default-*`,
  `more-*` and `extra-*` response files but **no `none-*`**, while
  `platform.txt:25` defaults to `.../warnings/none`. Unrelated to `cflags`:
  it fails with an `environment.json` that has no `cflags` key at all.
- **esp32** fails with `Error: esp32: Unknown package`. The Fat Dockerfile clones
  arduino-esp32 straight into `/root/.arduino15/packages/esp32/`, but Arduino 1.8.x
  requires `/root/.arduino15/packages/esp32/hardware/esp32/<version>/`.

When validating a base-image change, compare against the *old image's* behaviour
rather than against "a build should succeed" — run the same workspace through both.

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

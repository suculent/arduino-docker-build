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
  (older base images like `bullseye` and older `ESP*_VERSION` values). They are not
  guaranteed to be fast-forwards. Check `git diff master ssh/esp32 -- Dockerfile.esp32`
  before deciding to merge vs. force-push.
- To unify all three on the master-line content, force-push the same commit:
  `git push ssh master:master && git push --force ssh master:esp32 && git push --force ssh master:esp8266`
  (force-push overwrites divergent branch history — confirm with the maintainer first).
- Remote is named `ssh` (`git@github.com:suculent/arduino-docker-build.git`), not `origin`.
  The repo is often checked out in **detached HEAD** at master's tip.

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

### Known Debian 13 (trixie) migration notes

Base image is `debian:13.5-slim` (migrated from `bookworm`). When bumping Debian:
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

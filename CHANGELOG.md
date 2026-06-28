# CHANGELOG

0.8.172 - upgraded base image to `debian:13.5-slim` (Debian 13 "trixie"; dropped the now-removed `software-properties-common` package). Fixed the `cflags` feature (added in 0.8.0) which never actually reached the builder: the value is now appended to `CFLAGS` and passed as a single `--pref compiler.cpp.extra_flags` token, so multi-flag values work end-to-end.

0.8.0 - added support for `cflags` variable in `environment.json` – variable is directly transformed into `--pref compiler.cpp.extra_flags` arduino builder argument.

0.7.9 - Support for `environment.json` using to update `environment.h` file to allow custom builds from same source.
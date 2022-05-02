# Arduino Docker Build

[![Docker Pulls](https://img.shields.io/docker/pulls/suculent/arduino-docker-build.svg)](https://hub.docker.com/r/suculent/arduino-docker-build/) [![Docker Stars](https://img.shields.io/docker/stars/suculent/arduino-docker-build.svg)](https://hub.docker.com/r/suculent/arduino-docker-build/) [![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat)](https://github.com/suculent/arduino-docker-build/blob/master/LICENSE)
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=arduino-docker-build&metric=alert_status)](https://sonarcloud.io/dashboard?id=arduino-docker-build)
[![Vulnerabilities](https://sonarcloud.io/api/project_badges/measure?project=arduino-docker-build&metric=vulnerabilities)](https://sonarcloud.io/dashboard?id=arduino-docker-build)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=arduino-docker-build&metric=security_rating)](https://sonarcloud.io/dashboard?id=arduino-docker-build)
[![FOSSA Status](https://app.fossa.io/api/projects/git%2Bgithub.com%2Fsuculent%2Farduino-docker-build.svg?type=shield)](https://app.fossa.io/projects/git%2Bgithub.com%2Fsuculent%2Farduino-docker-build?ref=badge_shield)
[![CircleCI](https://circleci.com/gh/suculent/arduino-docker-build/tree/master.svg?style=svg)](https://circleci.com/gh/suculent/arduino-docker-build/tree/master)

Run the [Arduino](http://arduino.cc) command-line builder in a docker container. This image will take it from there and turn your Arduino project into a binary which you then can [flash to the ESP8266/ESP32](http://nodemcu.readthedocs.org/en/dev/en/flash/).


## Target audience

- Application developers

  They just need a ready-made firmware.

- Occasional firmware hackers

  They don't need full control over the complete tool chain and don't want to setup a Linux VM with the build environment.

**This image has been created for purposes of the [THiNX OpenSource IoT management platform](https://thinx.cloud).**

## Usage

### Install Docker
Follow the instructions at [https://docs.docker.com/get-started/](https://docs.docker.com/get-started/).

### Quick Start

Enter any Arduino project repository root. Builder expects thinx.yml file. To build the project, just run:

```
  docker run --rm -t -v `pwd`:/opt/workspace suculent/arduino-docker-build
```

### Run this image with Docker

**Preparation**

1. Install and run `socat` to tunnel the X11

```
	$ brew install socat
  	$ socat TCP-LISTEN:6000,reuseaddr,fork UNIX-CLIENT:\"$DISPLAY\"
```

2. Insert your IP address here to display Arduino IDE using X11/socat

```
	docker run --rm -ti -e DISPLAY=127.0.0.1:0 -v `pwd`:/opt/workspace suculent/arduino-docker-build
```

3. Start terminal and change to the your Arduino project repository (that contains mandatory directory containing your .ino file). Then run:

``docker run --rm -ti -v `pwd`:/opt/workspace suculent/arduino-docker-build``

Depending on the performance of your system it takes 1-3min until the compilation finishes. The first time you run this it takes longer because Docker needs to download the image and create a container.

:bangbang: If you have previously pulled this Docker image (e.g. with the command above) you should update the image from time to time to pull in the latest bug fixes:

`docker pull suculent/arduino-docker-build`

**Note for Windows users**

(Docker on) Windows handles paths slightly differently. The command thus becomes (`c` equals C drive i.e. `c:`):

`docker run --rm -it -v //c/Users/<user>/<arduino-builder>:/opt/arduino-builder suculent/arduino-docker-build`

If the Windows path contains spaces it would have to be wrapped in quotes as usual on Windows.

`docker run --rm -it -v "//c/Users/monster tune/<arduino-builder>"/opt/arduino-builder suculent/arduino-docker-build``

#### User libraries

In case there is a `lib` folder next to your `.ino` file, it will be copied to the build path from your repository.

#### Output
The firmware file is created in the `bin` sub folder of your root directory. You will also find a mapfile in the `bin` folder with the same name as the firmware file but with a `.map` ending.

#### Options
You can pass the following optional parameters to the Docker build like so `docker run -e "<parameter>=value" -e ...`.

- `WORKDIR` Just an parametrization example, will deprecate or be used for additional libraries.

#### Environment support

The builder is able to re-create designated environment.h (exact filename should be defined in thinx.yml) from environment.json.
The environment.h is used to customize variables in project.

In case you need to modify GCC CFLAGS using environment variables, use the `cflags` variable which will be passed to Arduino builder since 0.8.0.

### Flashing the built binary
There are several [tools to flash the firmware](http://nodemcu.readthedocs.org/en/dev/en/flash/) to the ESP8266/ESP32. If you were to use [esptool](https://github.com/themadinventor/esptool) (like I do) you'd run:

`esptool.py --port <seria-port> write_flash 0x00000 firmware.bin`

## Support
Don't leave comments on Docker Hub that are intended to be support requests. First, Docker Hub doesn't notify me when you write them, second I can't properly reply and third even if I could often it doesn't make much sense to keep them around forever and a day. Instead ask a question on [StackOverflow](http://stackoverflow.com/) and assign the `arduino` and `docker` tags.

For bugs and improvement suggestions create an issue at [https://github.com/suculent/arduino-docker-build/issues](https://github.com/suculent/arduino-docker-build/issues).

## Credits
Thanks to [Marcel Stoer](http://pfalcon-oe.blogspot.com/) who inspired me with his NodeMCU firmware builder on [http://frightanic.com](http://frightanic.com)

## Author
[Matěj Sychra @ THiNX](http://thinx.cloud)


## License
[![FOSSA Status](https://app.fossa.io/api/projects/git%2Bgithub.com%2Fsuculent%2Farduino-docker-build.svg?type=large)](https://app.fossa.io/projects/git%2Bgithub.com%2Fsuculent%2Farduino-docker-build?ref=badge_large)
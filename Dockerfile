FROM ubuntu
MAINTAINER suculent

RUN apt-get update && apt-get install -y -f software-properties-common \
  && add-apt-repository ppa:openjdk-r/ppa \
  && apt-get update \
  && apt-get install --allow-change-held-packages -y \
  wget \
  unzip \
  git \
  make \
  srecord \
  bc \
  xz-utils \
  gcc \
  curl \
  xvfb \
  python python-pip python-dev build-essential \
  libncurses-dev flex bison gperf python-serial \
  libxrender1 libxtst6 libxi6 openjdk-8-jdk

RUN curl https://downloads.arduino.cc/arduino-1.8.9-linux64.tar.xz > ./arduino-1.8.9-linux64.tar.xz \
 && unxz ./arduino-1.8.9-linux64.tar.xz \
 && ls -la \
 && tar -xvf arduino-1.8.9-linux64.tar \
 && rm -rf arduino-1.8.9-linux64.tar \
 && mv ./arduino-1.8.9 /opt/arduino \
 && cd /opt/arduino \
 && ls -la \
 && ./install.sh

RUN mkdir /opt/workspace

RUN mkdir -p /opt/arduino/hardware/espressif \
 && cd /opt/arduino/hardware/espressif \
 && git clone https://github.com/espressif/arduino-esp32.git esp32 \
 && cd esp32 \
 && git submodule update --init --recursive \
 && cd tools \
 && python get.py

RUN cd /opt/arduino/hardware/espressif \
  && git clone https://github.com/esp8266/Arduino.git esp8266 \
  && cd esp8266/tools \
  && python get.py \
  && echo "d1_mini.build.flash_ld=eagle.flash.4m1m.ld" >> "/opt/arduino/hardware/espressif/esp8266/boards.txt" \
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /opt/workspace
EXPOSE 22
COPY cmd.sh /opt/
CMD /opt/cmd.sh

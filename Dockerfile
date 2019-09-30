FROM ubuntu:16.04

RUN apt-get update -qq && apt-get install -qq -y --no-install-recommends -f software-properties-common \
  && add-apt-repository ppa:openjdk-r/ppa \
  && apt-get update \
  && apt-get install --no-install-recommends --allow-change-held-packages -y \
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
  python \
  python-pip \
  python-dev \
  build-essential \
  libncurses-dev \
  flex \
  bison \
  gperf \
  python-serial \
  libxrender1 \
  libxtst6 \
  libxi6 \
  openjdk-8-jre \
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /opt

RUN curl https://downloads.arduino.cc/arduino-1.8.9-linux64.tar.xz > ./arduino-1.8.9-linux64.tar.xz \
 && unxz ./arduino-1.8.9-linux64.tar.xz \
 && tar -xvf arduino-1.8.9-linux64.tar \
 && rm -rf arduino-1.8.9-linux64.tar \
 && mv ./arduino-1.8.9 ./arduino \
 && cd ./arduino \
 && ./install.sh

WORKDIR /opt/arduino/hardware/espressif

RUN git clone https://github.com/espressif/arduino-esp32.git esp32

WORKDIR /opt/arduino/hardware/espressif/esp32
RUN git submodule update --init --recursive \
 && rm -rf ./**/examples/**

WORKDIR /opt/arduino/hardware/espressif/esp32/tools
RUN python get.py

WORKDIR /opt/arduino/hardware/espressif
RUN git clone https://github.com/esp8266/Arduino.git esp8266
WORKDIR /opt/arduino/hardware/espressif/esp8266
RUN git checkout tags/2.5.2 \
  && rm -rf ./**/examples/**

WORKDIR /opt/arduino/hardware/espressif/esp8266/tools
RUN python get.py

RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add boards manager URL (warning, mismatch in boardsmanager vs. boards_manager in 2.6.0 coming up)
RUN /opt/arduino/arduino \
     --pref "boardsmanager.additional.urls=http://arduino.esp8266.com/stable/package_esp8266com_index.json" \
     --save-prefs \
  && /opt/arduino/arduino \
     --install-boards esp8266:esp8266 \
     --save-prefs

RUN mkdir /opt/workspace
WORKDIR /opt/workspace
COPY cmd.sh /opt/
CMD [ "/opt/cmd.sh" ]

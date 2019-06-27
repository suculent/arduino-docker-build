FROM ubuntu:16.04

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
  openjdk-8-jdk \
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN curl https://downloads.arduino.cc/arduino-1.8.9-linux64.tar.xz > ./arduino-1.8.9-linux64.tar.xz \
 && unxz ./arduino-1.8.9-linux64.tar.xz \
 && tar -xvf arduino-1.8.9-linux64.tar \
 && rm -rf arduino-1.8.9-linux64.tar \
 && mv ./arduino-1.8.9 /opt/arduino \
 && cd /opt/arduino \
 && ./install.sh

WORKDIR /opt/arduino/hardware/espressif

RUN git clone https://github.com/espressif/arduino-esp32.git esp32 \
 && cd esp32 \
 && git submodule update --init --recursive \
 && rm -rf ./**/examples/** \
 && cd tools \
 && python get.py

RUN git clone https://github.com/esp8266/Arduino.git esp8266 \
  && cd ./esp8266 \
  && git checkout tags/2.5.0 \
  && rm -rf ./**/examples/** \
  && cd ./tools \
  && python get.py \
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add boards manager URL (warning, mismatch in boardsmanager vs. boards_manager in 2.6.0 coming up)
RUN /opt/arduino/arduino --pref "boardsmanager.additional.urls=http://arduino.esp8266.com/stable/package_esp8266com_index.json" --save-prefs \
    && /opt/arduino/arduino --install-boards esp8266:esp8266 --save-prefs

RUN mkdir /opt/workspace
WORKDIR /opt/workspace
COPY cmd.sh /opt/
CMD [ "/opt/cmd.sh" ]

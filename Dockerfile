FROM ubuntu:20.04

ARG GIT_TAG

ENV ARDUINO_VERSION="1.8.19"
ENV GIT_TAG=${GIT_TAG}
ENV DEBIAN_FRONTEND=noninteractive

ENV ESP32_VERSION="2.0.2"
ENV ESP8266_VERSION="2.7.4"

RUN apt -y -qq update && \
  apt -y -qq --no-install-recommends --allow-change-held-packages install \
  software-properties-common \
  wget \
  zip \
  unzip \
  git \
  make \
  srecord \
  bc \
  xz-utils \
  gcc \
  curl \
  xvfb \
  python3 \
  python3-dev \
  python3-pip \
  build-essential \
  libncurses-dev \
  flex \
  bison \
  gperf \
  libxrender1 \
  libxtst6 \
  libxi6 \
  jq \
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /opt

ENV HW_PATH=/root/.arduino15/packages
# /root/.arduino15/packages/esp8266/hardware/esp8266

# Get pinned version of Arduino IDE
RUN curl https://downloads.arduino.cc/arduino-$ARDUINO_VERSION-linux64.tar.xz > ./arduino-$ARDUINO_VERSION-linux64.tar.xz \
 && unxz -q ./arduino-$ARDUINO_VERSION-linux64.tar.xz \
 && tar -xvf arduino-$ARDUINO_VERSION-linux64.tar \
 && rm -rf arduino-$ARDUINO_VERSION-linux64.tar \
 && mv ./arduino-$ARDUINO_VERSION ./arduino \
 && cd ./arduino \
 && ./install.sh \
 && rm -rf ${HW_PATH}/*

# Get latest ESP32 Arduino framework
WORKDIR ${HW_PATH}
RUN git clone --depth=1 --branch $ESP32_VERSION https://github.com/espressif/arduino-esp32.git esp32
WORKDIR ${HW_PATH}/esp32
RUN pwd && ls -la && git submodule update --init --recursive \
 && rm -rf ./**/examples/** ./.git

# Get ESP32 tools
WORKDIR ${HW_PATH}/esp32/tools
RUN pwd && ls -la && python3 --version && python3 get.py

# Get latest ESP8266 Arduino framework
WORKDIR ${HW_PATH}
RUN ls -la && git clone --depth=1 --branch $ESP8266_VERSION https://github.com/esp8266/Arduino.git esp8266
WORKDIR ${HW_PATH}/esp8266
RUN ls -la && git submodule update --init --recursive \
 && rm -rf ./.git

# Get ESP8266 tools
WORKDIR ${HW_PATH}/esp8266/tools
RUN ls -la && python3 --version && python3 get.py

# Hardening and optimization: clean apt lists
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

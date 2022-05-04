FROM debian:bullseye-slim

ARG GIT_TAG

ENV ARDUINO_VERSION="1.8.19"
ENV GIT_TAG=${GIT_TAG}
ENV DEBIAN_FRONTEND=noninteractive

ENV ESP32_VERSION="2.0.2"

# Arduino installs 3.0.2 by default, we'll delete that and override
ENV ESP8266_VERSION="2.6.3"

RUN apt -y -qq update && \
  apt -y -qq --no-install-recommends --allow-change-held-packages install \
  software-properties-common \
  wget \
  zip \
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

# Get pinned version of Arduino IDE
RUN curl https://downloads.arduino.cc/arduino-$ARDUINO_VERSION-linux64.tar.xz > ./arduino-$ARDUINO_VERSION-linux64.tar.xz \
 && unxz -q ./arduino-$ARDUINO_VERSION-linux64.tar.xz \
 && tar -xvf arduino-$ARDUINO_VERSION-linux64.tar \
 && rm -rf arduino-$ARDUINO_VERSION-linux64.tar \
 && mv ./arduino-$ARDUINO_VERSION ./arduino \
 && cd ./arduino \
 && ./install.sh \
 && rm -rf /root/.arduino15/packages/esp8266/hardware/esp8266/3.0.2 \
 && mkdir -p ${HW_PATH} \
 && cd ${HW_PATH} \
 && git config --global advice.detachedHead false \
 && git clone --depth=1 --branch $ESP32_VERSION https://github.com/espressif/arduino-esp32.git esp32 \
 && cd ${HW_PATH}/esp32 \
 && pwd && ls -la && git submodule update --init --recursive \
 && rm -rf ./**/examples/** ./.git \
 && cd ${HW_PATH}/esp32/tools \
 && python3 get.py \
 && mkdir /opt/workspace \
 && /opt/arduino/arduino \
    --pref "boardsmanager.additional.urls=http://arduino.esp8266.com/stable/package_esp8266com_index.json" \
    --save-prefs \
 && /opt/arduino/arduino \
     --install-boards esp8266:esp8266:${ESP8266_VERSION} \
     --save-prefs

WORKDIR /opt/workspace
COPY cmd.sh /opt/
CMD [ "/opt/cmd.sh" ]

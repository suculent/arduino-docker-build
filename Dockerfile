FROM ubuntu
MAINTAINER suculent

RUN apt-get update && apt-get install -y \
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
  python python-pip python-dev build-essential

RUN curl https://downloads.arduino.cc/arduino-1.8.5-linux64.tar.xz > ./arduino-1.8.5-linux64.tar.xz \
 && unxz ./arduino-1.8.5-linux64.tar.xz \
 && ls -la \
 && tar -xvf arduino-1.8.5-linux64.tar \
 && rm -rf arduino-1.8.5-linux64.tar \
 && mv ./arduino-1.8.5 /opt/arduino \
 && cd /opt/arduino \
 && ls -la \
 && ./install.sh

RUN mkdir /opt/workspace

RUN mkdir -p /root/Arduino/hardware/esp8266com \
  && cd /root/Arduino/hardware/esp8266com \
  && git clone https://github.com/esp8266/Arduino.git esp8266 \
  && cd esp8266/tools \
  && python get.py \
  && echo "d1_mini.build.flash_ld=eagle.flash.4m1m.ld" >> "/root/Arduino/hardware/esp8266com/esp8266/boards.txt"
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /opt/workspace
EXPOSE 22
COPY cmd.sh /opt/
CMD /opt/cmd.sh

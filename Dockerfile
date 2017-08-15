FROM ubuntu
MAINTAINER suculent

RUN apt-get update && apt-get install -y wget unzip git make srecord bc xz-utils gcc curl xvfb

RUN curl https://downloads.arduino.cc/arduino-1.8.3-linux64.tar.xz > ./arduino-1.8.3-linux64.tar.xz \
 && unxz ./arduino-1.8.3-linux64.tar.xz \
 && ls -la \
 && tar -xvf arduino-1.8.3-linux64.tar \
 && rm -rf arduino-1.8.3-linux64.tar \
 && mv ./arduino-1.8.3 /opt/arduino \
 && cd /opt/arduino \
 && ls -la \
 && ./install.sh

RUN mkdir /opt/workspace
RUN mkdir /opt/workspace/test
RUN mkdir /opt/workspace/build
WORKDIR /opt/workspace
EXPOSE 22
COPY cmd.sh /opt/
CMD /opt/cmd.sh

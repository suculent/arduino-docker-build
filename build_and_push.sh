#!/bin/bash

DOCKER_HUB_REPO=suculent/$(basename $(pwd))
GIT_TAG=$(git describe)
docker build --platform linux/amd64 . -t $DOCKER_HUB_REPO
if [[ $?==0 ]]; then
  docker push $DOCKER_HUB_REPO
fi

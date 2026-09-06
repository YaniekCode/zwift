#!/bin/bash

echo "Installing Zwift in a Docker container"
# Installs Zwift in a Docker container
docker run --rm -d \
	--device=/dev/dri:/dev/dri \
	--privileged \
	-p 6080:6080 \
	-v zwift-data:/home/zwift \
	-v /run/user/1000/pulse:/run/user/1000/pulse \
	--name zwift \
	zwift \
	--install

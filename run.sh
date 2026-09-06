#!/bin/bash

docker run --rm \
    --device=/dev/dri/card1 \
    --device=/dev/dri/renderD128 \
    --group-add 984 \
    --group-add 988 \
    -p 6080:6080 \
    -p 5901:5901 \
    zwift

#!/usr/bin/env bash

set -euo pipefail

IMAGE="zwift:latest"
CONTAINER="zwift"
VOLUME="zwift-data"

usage() {
    cat <<EOF

Zwift Docker

Usage:
  ./zwift build
  ./zwift install
  ./zwift start
  ./zwift stop
  ./zwift restart
  ./zwift update
  ./zwift status
  ./zwift logs
  ./zwift shell
  ./zwift remove

EOF
}

docker_run_args() {
    cat <<EOF
--name ${CONTAINER}
--hostname zwift
--restart unless-stopped

--device /dev/dri:/dev/dri
--group-add video
--group-add render

-v ${VOLUME}:/home/zwift

-v /run/dbus:/run/dbus:ro

-v /run/user/1000/pulse:/run/user/1000/pulse

-p 6080:6080

--privileged
EOF
}

build() {
    echo "[+] Building Zwift image..."
    docker build -t "${IMAGE}" .
}

install() {
    build

    docker rm -f "${CONTAINER}" 2>/dev/null || true

    docker run \
        $(docker_run_args) \
        "${IMAGE}" \
        --install
}

start() {
    if docker ps -q -f "name=^${CONTAINER}$" | grep -q .; then
        echo "[+] Zwift is already running."
        return
    fi

    docker start "${CONTAINER}" 2>/dev/null || \
    docker run \
        $(docker_run_args) \
        "${IMAGE}"
}

stop() {
    docker stop "${CONTAINER}"
}

restart() {
    docker restart "${CONTAINER}"
}

update() {
    docker exec \
        -it "${CONTAINER}" \
        /usr/local/bin/update_zwift.sh
}

status() {
    docker ps \
        -a \
        --filter "name=^${CONTAINER}$"
}

logs() {
    docker logs -f "${CONTAINER}"
}

shell() {
    docker exec -it "${CONTAINER}" bash
}

remove() {
    docker rm -f "${CONTAINER}" 2>/dev/null || true
}

case "${1:-}" in
    build)   build ;;
    install) install ;;
    start)   start ;;
    stop)    stop ;;
    restart) restart ;;
    update)  update ;;
    status)  status ;;
    logs)    logs ;;
    shell)   shell ;;
    remove)  remove ;;
    *)       usage ;;
esac
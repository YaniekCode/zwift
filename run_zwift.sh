#!/usr/bin/env bash

set -uo pipefail

export HOME=/home/zwift
export WINEPREFIX=/home/zwift/.wine
export DISPLAY=:1

readonly ZWIFT_INSTALL_DIR="${ZWIFT_INSTALL_DIR:?}"


# ============================================================
# Helpers
# ============================================================

wine_task_info() {

    local task_name="${1:?}"

    wine tasklist \
        /fo list \
        /fi "IMAGENAME eq ${task_name}"
}


wine_task_pid() {

    local task_name="${1:?}"

    wine_task_info "${task_name}" \
        | grep -m1 -Po '^PID:[\t ]*\K[0-9]+'
}


is_wine_task_running() {

    local task_name="${1:?}"

    [[ -n "$(wine_task_info "${task_name}" || true)" ]]
}


kill_wine_task() {

    local task_name="${1:?}"

    if is_wine_task_running "${task_name}"; then

        echo "Stopping ${task_name}..."

        wine taskkill \
            /f \
            /im "${task_name}" \
            >/dev/null 2>&1 \
            || true

    fi
}


# ============================================================
# Verify installation
# ============================================================

if [[ ! -f "${ZWIFT_INSTALL_DIR}/ZwiftApp.exe" ]]; then

    echo
    echo "ERROR: ZwiftApp.exe not found:"
    echo
    echo "  ${ZWIFT_INSTALL_DIR}/ZwiftApp.exe"
    echo

    exit 1
fi


echo
echo "ZwiftApp.exe found."
echo


# ============================================================
# Wine path
# ============================================================

zwift_wine_dir="$(winepath -w "${ZWIFT_INSTALL_DIR}")"

if [[ -z "${zwift_wine_dir}" ]]; then

    echo "ERROR: winepath failed."

    exit 1
fi


echo "Zwift directory:"
echo "${zwift_wine_dir}"
echo


# ============================================================
# Start launcher
# ============================================================

echo "Starting Zwift Launcher..."

wine start \
    /d "${zwift_wine_dir}" \
    ZwiftLauncher.exe \
    SilentLaunch


# ============================================================
# Wait for launcher
# ============================================================

echo "Waiting for ZwiftLauncher.exe..."

launcher_pid=""

for i in $(seq 1 60); do

    if is_wine_task_running ZwiftLauncher.exe; then

        launcher_pid="$(wine_task_pid ZwiftLauncher.exe || true)"

        if [[ -n "${launcher_pid}" ]]; then
            break
        fi

    fi

    sleep 1

done


if [[ -z "${launcher_pid}" ]]; then

    echo "ERROR: ZwiftLauncher.exe did not start."

    exit 1
fi


echo
echo "Launcher PID: ${launcher_pid}"
echo


# ============================================================
# Start actual Zwift process
# ============================================================

echo "Starting ZwiftApp.exe..."

wine start \
    /d "${zwift_wine_dir}" \
    /unix \
    /usr/local/bin/runfromprocess-rs.exe \
    "${launcher_pid}" \
    ZwiftApp.exe


# ============================================================
# Wait for game
# ============================================================

echo "Waiting for ZwiftApp.exe..."

for i in $(seq 1 60); do

    if is_wine_task_running ZwiftApp.exe; then

        echo "ZwiftApp.exe started."

        break
    fi

    sleep 1

done


if ! is_wine_task_running ZwiftApp.exe; then

    echo
    echo "ERROR: ZwiftApp.exe failed to start."
    echo

    exit 1
fi


# ============================================================
# Launcher no longer needed
# ============================================================

sleep 3

kill_wine_task ZwiftLauncher.exe


echo
echo "========================================"
echo " Zwift is running"
echo "========================================"
echo


# ============================================================
# Monitor
# ============================================================

while is_wine_task_running ZwiftApp.exe; do

    sleep 5

done


echo
echo "Zwift exited."

exit 0

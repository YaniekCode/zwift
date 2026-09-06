#!/usr/bin/env bash

set -uo pipefail

export HOME=/home/zwift
export WINEPREFIX=/home/zwift/.wine
export DISPLAY=:1

readonly ZWIFT_INSTALL_DIR="${ZWIFT_INSTALL_DIR:?}"


# ============================================================
# Helpers
# ============================================================

# Print green [+] and a text message
log() {
    printf '\033[1;32m[+]\033[0m %s\n' "$*"
}

# Print red [!] and an error message
die() {
    printf '\033[1;31m[!]\033[0m %s\n' "$*" >&2
    exit 1
}

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
        log "Stopping ${task_name}..."

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
    die "ZwiftApp.exe not found: ${ZWIFT_INSTALL_DIR}/ZwiftApp.exe"
fi

log "Zwift installation found."


# ============================================================
# Wine path
# ============================================================

zwift_wine_dir="$(winepath -w "${ZWIFT_INSTALL_DIR}")" || \
    die "winepath failed."

if [[ -z "${zwift_wine_dir}" ]]; then
    die "Wine Zwift directory is empty."
fi

log "Zwift directory: ${zwift_wine_dir}"


# ============================================================
# Start launcher
# ============================================================

log "Starting Zwift Launcher..."

wine start \
    /d "${zwift_wine_dir}" \
    ZwiftLauncher.exe \
    SilentLaunch \
    || die "Unable to start Zwift Launcher."


# ============================================================
# Wait for launcher
# ============================================================

log "Waiting for Zwift Launcher..."

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
    die "ZwiftLauncher.exe did not start."
fi

log "Launcher PID: ${launcher_pid}"


# ============================================================
# Start actual Zwift process
# ============================================================

log "Starting Zwift..."

wine start \
    /d "${zwift_wine_dir}" \
    /unix \
    /usr/local/bin/runfromprocess-rs.exe \
    "${launcher_pid}" \
    ZwiftApp.exe \
    || die "Unable to start ZwiftApp.exe."


# ============================================================
# Wait for game
# ============================================================

log "Waiting for Zwift..."

game_started=false

for i in $(seq 1 60); do
    if is_wine_task_running ZwiftApp.exe; then
        game_started=true
        break
    fi

    sleep 1
done

if [[ "${game_started}" != true ]]; then
    die "ZwiftApp.exe failed to start."
fi

log "ZwiftApp.exe started."


# ============================================================
# Launcher no longer needed
# ============================================================

sleep 3

kill_wine_task ZwiftLauncher.exe


# ============================================================
# Running
# ============================================================

printf '\n'
printf '\033[1;32m========================================\033[0m\n'
printf '\033[1;32m Zwift is running\033[0m\n'
printf '\033[1;32m========================================\033[0m\n'
printf '\n'


# ============================================================
# Monitor
# ============================================================

while is_wine_task_running ZwiftApp.exe; do
    sleep 5
done


printf '\n'
log "Zwift exited."

exit 0
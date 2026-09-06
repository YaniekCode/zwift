#!/usr/bin/env bash

set -uo pipefail

export HOME=/home/zwift
export WINEPREFIX=/home/zwift/.wine

readonly ZWIFT_INSTALL_DIR="${ZWIFT_INSTALL_DIR:?}"
readonly ZWIFT_DATA_DIR="${ZWIFT_DATA_DIR:?}"


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

is_wine_task_running() {
    local task_name="${1:?}"

    [[ -n "$(wine_task_info "${task_name}" || true)" ]]
}

get_current_version() {
    local version_filename="Zwift_ver_cur.xml"

    if [[ -f "${ZWIFT_INSTALL_DIR}/Zwift_ver_cur_filename.txt" ]]; then
        version_filename="$(
            tr '\0' '\n' \
                < "${ZWIFT_INSTALL_DIR}/Zwift_ver_cur_filename.txt"
        )"
    fi

    if [[ ! -f "${ZWIFT_INSTALL_DIR}/${version_filename}" ]]; then
        echo "none"
        return
    fi

    grep -oP \
        'sversion="\K.*?(?=\s)' \
        "${ZWIFT_INSTALL_DIR}/${version_filename}" \
        2>/dev/null \
        | cut -f1 -d' ' \
        || echo "none"
}

get_latest_version() {
    wget \
        --no-cache \
        --quiet \
        -O - \
        https://cdn.zwift.com/gameassets/Zwift_Updates_Root/Zwift_ver_cur.xml \
        | grep -oP 'sversion="\K.*?(?=")' \
        | cut -f1 -d' '
}


# ============================================================
# Install
# ============================================================

install_zwift() {
    log "Initializing Wine..."

    WINEDLLOVERRIDES="mscoree,mshtml=" \
        wineboot -u \
        || die "Wine initialization failed"

    log "Installing .NET 4.8..."

    winetricks \
        -q \
        corefonts \
        dotnet48 \
        d3dcompiler_47 \
        || die "Wine components installation failed"

    log "Installing WebView2..."

    wget \
        --quiet \
        -O /tmp/webview2-setup.exe \
        https://go.microsoft.com/fwlink/p/?LinkId=2124703 \
        || die "WebView2 download failed"

    wine /tmp/webview2-setup.exe \
        /silent \
        /install \
        || die "WebView2 installation failed"

    rm -f /tmp/webview2-setup.exe

    log "Configuring Wine graphics..."

    wine reg.exe add \
        'HKCU\Software\Wine\Drivers' \
        /f \
        /v Graphics \
        /d x11,wayland \
        || die "Wine graphics configuration failed"

    log "Downloading Zwift installer..."

    wget \
        --quiet \
        -O /tmp/ZwiftSetup.exe \
        https://cdn.zwift.com/app/ZwiftSetup.exe \
        || die "Zwift installer download failed"

    log "Installing Zwift Launcher..."

    wine /tmp/ZwiftSetup.exe \
        /SP- \
        /VERYSILENT \
        /SUPPRESSMSGBOXES \
        /NORESTART \
        /NOCANCEL \
        || die "Zwift Launcher installation failed"

    rm -f /tmp/ZwiftSetup.exe
}


# ============================================================
# Update through Zwift Launcher
# ============================================================

update_zwift() {
    local latest
    local current

    latest="$(get_latest_version)" || {
        echo "ERROR: unable to get latest Zwift version"
        return 1
    }

    current="$(get_current_version)"

    printf '\n'
    printf 'Current Zwift version: %s\n' "${current}"
    printf 'Latest Zwift version:  %s\n' "${latest}"
    printf '\n'

    if [[ "${current}" == "${latest}" ]]; then
        log "Zwift is already up to date."
        return 0
    fi

    log "Starting Zwift Launcher..."

    local wine_dir

    wine_dir="$(winepath -w "${ZWIFT_INSTALL_DIR}")" || {
        echo "ERROR: winepath failed"
        return 1
    }

    wine start \
        /d "${wine_dir}" \
        ZwiftLauncher.exe \
        SilentLaunch \
        || {
            echo "ERROR: unable to start Zwift Launcher"
            return 1
        }

    log "Zwift Launcher started."

    local original_version="${current}"
    local counter=1
    local max_iterations=120

    while \
        [[ "${current}" == "${original_version}" ]] &&
        [[ ${counter} -le ${max_iterations} ]] &&
        is_wine_task_running ZwiftLauncher.exe
    do
        printf '\r\033[K'
        printf '[+] Updating Zwift... (%d/%d)' \
            "${counter}" \
            "${max_iterations}"

        sleep 5

        current="$(get_current_version)"
        counter=$((counter + 1))
    done

    printf '\n'

    if [[ "${current}" == "${original_version}" ]]; then
        echo
        echo "ERROR: Zwift update timed out."
        echo
        return 1
    fi

    if [[ "${current}" != "${latest}" ]]; then
        echo
        echo "ERROR: unexpected Zwift version."
        echo "Expected: ${latest}"
        echo "Actual:   ${current}"
        echo
        return 1
    fi

    log "Zwift ${current} installed."

    return 0
}


# ============================================================
# Main
# ============================================================

if [[ "${1:-}" == "--install" ]]; then

    log "Installing Zwift..."

    if [[ -f "${ZWIFT_INSTALL_DIR}/ZwiftLauncher.exe" ]]; then
        log "Zwift Launcher already installed."
    else
        install_zwift
    fi
fi


if [[ ! -f "${ZWIFT_INSTALL_DIR}/ZwiftLauncher.exe" ]]; then
    die "ZwiftLauncher.exe not found. Run the container with --install."
fi


log "Updating Zwift..."

update_zwift || {
    die "Zwift update failed."
}


# ============================================================
# Cleanup
# ============================================================

rm -f /tmp/ZwiftSetup.exe
rm -f /tmp/webview2-setup.exe

exit 0
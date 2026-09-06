#!/usr/bin/env bash

set -uo pipefail

export HOME=/home/zwift
export WINEPREFIX=/home/zwift/.wine

readonly ZWIFT_INSTALL_DIR="${ZWIFT_INSTALL_DIR:?}"
readonly ZWIFT_DATA_DIR="${ZWIFT_DATA_DIR:?}"


# ============================================================
# Helpers
# ============================================================

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

    echo
    echo "========================================"
    echo " Initializing Wine"
    echo "========================================"
    echo

    WINEDLLOVERRIDES="mscoree,mshtml=" \
        wineboot -u || return 1


    echo
    echo "========================================"
    echo " Installing Wine dependencies"
    echo "========================================"
    echo

    winetricks \
        -q \
        corefonts \
        dotnet48 \
        d3dcompiler_47 \
        || return 1


    echo
    echo "========================================"
    echo " Installing WebView2"
    echo "========================================"
    echo

    wget \
        -O /tmp/webview2-setup.exe \
        https://go.microsoft.com/fwlink/p/?LinkId=2124703 \
        || return 1

    wine /tmp/webview2-setup.exe \
        /silent \
        /install \
        || return 1


    echo
    echo "========================================"
    echo " Configuring Wine graphics"
    echo "========================================"
    echo

    wine reg.exe add \
        'HKCU\Software\Wine\Drivers' \
        /f \
        /v Graphics \
        /d x11,wayland \
        || return 1


    echo
    echo "========================================"
    echo " Downloading Zwift installer"
    echo "========================================"
    echo

    wget \
        -O /tmp/ZwiftSetup.exe \
        https://cdn.zwift.com/app/ZwiftSetup.exe \
        || return 1


    echo
    echo "========================================"
    echo " Installing Zwift Launcher"
    echo "========================================"
    echo

    wine /tmp/ZwiftSetup.exe \
        /SP- \
        /VERYSILENT \
        /SUPPRESSMSGBOXES \
        /NORESTART \
        /NOCANCEL \
        || return 1
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

    echo
    echo "Current Zwift version: ${current}"
    echo "Latest Zwift version:  ${latest}"
    echo


    if [[ "${current}" == "${latest}" ]]; then

        echo "Zwift is already up to date."

        return 0
    fi


    echo
    echo "Starting Zwift Launcher..."
    echo


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


    echo "Zwift Launcher started."


    local original_version="${current}"

    local counter=1
    local max_iterations=120


    while \
        [[ "${current}" == "${original_version}" ]] &&
        [[ ${counter} -le ${max_iterations} ]] &&
        is_wine_task_running ZwiftLauncher.exe
    do

        echo \
            "Downloading/updating Zwift... " \
            "(${counter}/${max_iterations})"

        sleep 5

        current="$(get_current_version)"

        counter=$((counter + 1))

    done


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


    echo
    echo "========================================"
    echo " Zwift ${current} installed"
    echo "========================================"
    echo

    return 0
}


# ============================================================
# Main
# ============================================================

if [[ "${1:-}" == "--install" ]]; then

    if [[ -f "${ZWIFT_INSTALL_DIR}/ZwiftLauncher.exe" ]]; then

        echo "Zwift Launcher already installed."

    else

        echo "Installing Zwift..."

        install_zwift || {
            echo "ERROR: Zwift installation failed."
            exit 1
        }

    fi
fi


if [[ ! -f "${ZWIFT_INSTALL_DIR}/ZwiftLauncher.exe" ]]; then

    echo
    echo "ERROR: ZwiftLauncher.exe not found."
    echo "Run:"
    echo
    echo "  docker run ... --install"
    echo

    exit 1
fi


echo "Updating Zwift..."

update_zwift || {
    echo "ERROR: Zwift update failed."
    exit 1
}


# ============================================================
# Don't delete Zwift data!
# ============================================================

rm -f /tmp/ZwiftSetup.exe
rm -f /tmp/webview2-setup.exe

exit 0

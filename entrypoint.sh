#!/usr/bin/env bash

set -uo pipefail

export HOME=/home/zwift
export WINEPREFIX=/home/zwift/.wine

VNC_DISPLAY=:1
VNC_GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
VNC_DEPTH="${VNC_DEPTH:-24}"

cleanup() {
    echo
    echo "Stopping Zwift container..."

    if [[ -n "${NOVNC_PID:-}" ]]; then
        kill "${NOVNC_PID}" 2>/dev/null || true
    fi

    tigervncserver -kill :1 2>/dev/null || true

    wineserver -k 2>/dev/null || true
}

trap cleanup EXIT INT TERM

echo "==================================================="
echo " Zwift Docker"
echo "==================================================="
echo
echo "Wine prefix: ${WINEPREFIX}"
echo "Resolution: ${VNC_GEOMETRY}"
echo

mkdir -p \
	"${HOME}/.config/tigervnc" \
	"${HOME}/.cache" \
	"${HOME}/.local/share"

#===================================================
# XFCE startup 
#===================================================

cat > "${HOME}/.config/tigervnc/xstartup" <<'EOF'
#!/bin/sh

unset SESSION_MANAGER
unser DBUS_SESSION_BUS_ADDRESS

export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce

exec startxfce4
EOF

chmod +x "${HOME}/.config/tigervnc/xstartup"

#===================================================
# Start TigerVNC 
#===================================================

echo "Starting TigerVNC..."

tigervncserver "${VNC_DISPLAY}" \
	-geometry "${VNC_GEOMETRY}" \
	-depth "${VNC_DEPTH}" \
	-SecurityTypes None
	# -localhost no

#===================================================
# Start noVNC 
#===================================================

echo "Starting noVNC..."

/opt/noVNC/utils/novnc_proxy \
	--vnc localhost:5901 \
	--listen 0.0.0.0:6080 &

NOVNC_PID=$!

#===================================================
# Give x server a moment 
#===================================================

sleep 3

export DISPLAY=:1

echo
echo "==================================================="
echo " Desktop ready"
echo "==================================================="
echo
echo "VNC:   port 5901"
echo "noVNC: port 6080"
echo
echo "Open:"
echo "http://<docker-host>:6080/vnc.html"
echo

#===================================================
# Wine initialization / install / run
#===================================================

if [[ "${1:-}" == "--install" ]]; then
	
	echo "Starting Zwift installation..."
	echo

	/usr/local/bin/update_zwift.sh --install

	echo
	echo "Zwift installation/update finished."
	echo

	echo "You can now run the container normally."
	echo

	# Keep container alive so user can inspect Wine.
	while true; do
		sleep 3600
	done

fi

#===================================================
# Normal startup
#===================================================

if [[ ! -f "${ZWIFT_INSTALL_DIR}/ZwiftApp.exe" ]]; then

	echo
	echo "ERROR:"
	echo "ZwiftApp.exe was not found."
	echo
	echo "Run the container with:"
	echo
	echo "  --install"
	echo

	while true; do
		sleep 3600
	done

fi

echo "Starting Zwift..."

exec /usr/local/bin/run_zwift.sh

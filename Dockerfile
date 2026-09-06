ARG DEBIAN_VERSION=trixie

#===================================================
# Build runfromprocess-rs
#===================================================
FROM rust:1.98.0-slim-trixie AS build-runfromprocess

ARG RUNFROMPROCESS_VERSION=a3d003c07d1bd11ff93c4cac96d2c3aa5deb8471

# Install prerequisites
# - mingw to cross-compile for windows
# - rust cross-compiler for windows
RUN apt-get update \
	&& apt-get install --no-install-recommends -y \
		g++-mingw-w64-x86-64 \
	&& rm -rf /var/lib/apt/lists/* \
	&& rustup target add x86_64-pc-windows-gnu

# Build runfromprocess
WORKDIR /usr/src
ADD https://github.com/quietvoid/runfromprocess-rs.git#${RUNFROMPROCESS_VERSION} .
RUN cargo build --target x86_64-pc-windows-gnu --release


#===================================================
# Wine base 
#===================================================
FROM debian:${DEBIAN_VERSION}-slim

# Wine
# - 11.0	: support 32-bit applications through wow64
# - 10.17	: default to egl for opengl in x11
# - 9.9		: support native wayland
# Winetricks
# - 20260125	: webview2 in zwift launcher works

ARG DEBIAN_VERSION
ARG WINE_BRANCH="devel"
ARG WINE_VERSION="=9.9~${DEBIAN_VERSION}-1"

ARG WINETRICKS_VERSION=20260125
ARG WINETRICKS_CHECKSUM=431f82fc74000e6c864409f1d8fb495d696c03928808e3e8acffc45179312a7b

# Select default options when prompted
# Ideal for automatic usage
ENV DEBIAN_FRONTEND=noninteractive

# Install prerequisites
# - ca-certificates for wget and curl
# - cabextract for winetricks
# - curl used in zwift authentication script
# - libegl1 and libgl1 for GL library
# - libvulkan1 for vulkan loader library
# - procps for pgrep
# - wget for downloading winehq key
# - winbind for ntml_auth required by zwift/wine
RUN dpkg --add-architecture i386 \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		cabextract \
		curl \
		wget \
		git \
		python3 \
		procps \
		winbind \
		dbus-x11 \
		xdg-utils \
		\
		# TigerVNC
		tigervnc-standalone-server \
		tigervnc-common \
		tigervnc-tools \
		\
		# XFCE
		xfce4 \
		xfce4-terminal \
		\
		# Graphics / Vulkan
		libegl1 \
		libgl1 \
		libvulkan1 \
		mesa-utils \
		mesa-vulkan-drivers \
		vulkan-tools \
		\
	&& rm -rf /var/lib/apt/lists/*

#===================================================
# WineHQ 
#===================================================
RUN wget -qO /etc/apt/trusted.gpg.d/winehq.asc \
		https://dl.winehq.org/wine-builds/winehq.key \
	&& echo "deb https://dl.winehq.org/wine-builds/debian/ ${DEBIAN_VERSION} main" \ 
		> /etc/apt/sources.list.d/winehq.list \
 	&& apt-get update \
	&& apt-get install --no-install-recommends -y \
		wine-${WINE_BRANCH}${WINE_VERSION} \
		wine-${WINE_BRANCH}-amd64${WINE_VERSION} \
		wine-${WINE_BRANCH}-i386${WINE_VERSION} \
		winehq-${WINE_BRANCH}${WINE_VERSION} \
	&& rm -rf /var/lib/apt/lists/*

#===================================================
# Winetricks 
#===================================================
ADD --checksum=sha256:${WINETRICKS_CHECKSUM} \ 
	--chmod=755 \
	https://raw.githubusercontent.com/Winetricks/winetricks/${WINETRICKS_VERSION}/src/winetricks \
	/usr/local/bin/

#===================================================
# User 
#===================================================
# Create a passwordless user zwift and make nvidia libraries discoverable
#RUN adduser --disabled-password --gecos '' --home /home/zwift --shell /bin/bash zwift
	#&& echo "/usr/local/nvidia/lib" >> /etc/ld.so.conf.d/nvidia.conf \
	#&& echo "/usr/local/nvidia/lib64" >> /etc/ld.so.conf.d/nvidia.conf
RUN useradd \
	--create-home \
	--shell /bin/bash \
	zwift

# Required for non-glvnd setups
# ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/usr/lib/i386-linux-gnu:/usr/local/nvidia/lib:/usr/local/nvidia/lib64

#===================================================
# noVNC + websockify 
#===================================================
RUN git clone \
		--depth 1 \
		https://github.com/novnc/noVNC.git \
		/opt/noVNC \
	&& git clone \
        	--depth 1 \
        	https://github.com/novnc/websockify.git \
        	/opt/noVNC/utils/websockify \
    	&& chown -R zwift:zwift /opt/noVNC


#===================================================
# Wine / Zwift environment 
#===================================================
#ENV NVIDIA_VISIBLE_DEVICES=all
#ENV NVIDIA_DRIVER_CAPABILITIES=all
#ENV WINEDEBUG=fixme-all
ENV HOME="/home/zwift"
ENV WINEPREFIX="/home/zwift/.wine"
ENV WINE_USER_HOME="/home/zwift/.wine/drive_c/users/zwift"
ENV ZWIFT_DATA_DIR="/home/zwift/.wine/drive_c/users/zwift/AppData/Local/Zwift"
ENV ZWIFT_INSTALL_DIR="/home/zwift/.wine/drive_c/Program Files (x86)/Zwift"

#===================================================
# Wine / Zwift environment 
#===================================================
COPY --from=build-runfromprocess \
	/usr/src/target/x86_64-pc-windows-gnu/release/runfromprocess-rs.exe \
	/bin/runfromprocess-rs.exe


#===================================================
# Scripts 
#===================================================
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=755 update_zwift.sh /usr/local/bin/update_zwift.sh
COPY --chmod=755 run_zwift.sh /usr/local/bin/run_zwift.sh

USER zwift

WORKDIR /home/zwift

EXPOSE 5901
EXPOSE 6080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

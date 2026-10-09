# SPDX-License-Identifier: GPL-2.0-or-later
#
# Windows 11 as a Cha Portal environment (experimental).
#
# Windows runs in QEMU/KVM inside the app container. Its 3D goes through
# Neptune: the guest's viogpu3d driver sends D3D11 to virglrenderer's Neptune
# context in QEMU, which runs it on DXVK over the node's Vulkan GPU. QEMU's own
# GTK window is the app: a Wayland client of the streamer's compositor, so the
# picture, the keyboard, the pointer and the sound go through Cha as for any
# other app.
#
# Built from source, pinned, with our patches in patches/:
#   QEMU           utmapp/qemu, dev/neptune-linux          (GPL-2.0)  the Neptune virtio-gpu device
#   virglrenderer  utmapp/virglrenderer, dev/neptune-linux (MIT)      the Neptune context
#   DXVK           osy/dxvk, master                        (zlib)     native (Linux) D3D11 on Vulkan

ARG BASE=ghcr.io/ban-red/cha-env-base:0.4.0
ARG UBUNTU=ubuntu:26.04

FROM ${UBUNTU} AS build

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bison build-essential ca-certificates cmake flex git glslang-tools \
      meson ninja-build pkg-config python3 python3-venv python3-yaml \
      libaio-dev libcap-ng-dev libdrm-dev libegl-dev libepoxy-dev libgbm-dev \
      libgl-dev libglib2.0-dev libgnutls28-dev libgtk-3-dev libjpeg-dev \
      libpixman-1-dev libpng-dev libpulse-dev libseccomp-dev libslirp-dev \
      liburing-dev libusb-1.0-0-dev \
      libusbredirparser-dev libvulkan-dev libwayland-dev libx11-dev \
      libxext-dev libxkbcommon-dev wayland-protocols zlib1g-dev libzstd-dev

ARG DXVK_REV=404240fdacf47470b02c76d6e684639a95dc7387
ARG VIRGLRENDERER_REV=b2e55fdd2fef9806845322cf24b65bd77730c44d
ARG QEMU_REV=1d8d9d917da0545d0b2145d241fbaf9c3d6eda07

# Our own fixes, from debugging on the node (patches/README.md).
COPY patches /patches

RUN git clone --filter=blob:none https://github.com/osy/dxvk.git /src/dxvk \
 && git -C /src/dxvk checkout "$DXVK_REV" \
 && git -C /src/dxvk submodule update --init --recursive \
 && for p in /patches/dxvk/*.patch; do git -C /src/dxvk apply "$p" || exit 1; done \
 && LDFLAGS='-Wl,-rpath,$ORIGIN' meson setup /build/dxvk /src/dxvk \
      --buildtype=release --prefix=/opt/neptune --libdir=lib \
      -Denable_d3d8=false -Denable_d3d9=false -Denable_d3d10=false \
      -Denable_d3d11=true -Denable_dxgi=true \
      -Dnative_glfw=disabled -Dnative_sdl2=disabled -Dnative_sdl3=disabled \
      -Dnative_headless=true \
 && meson install -C /build/dxvk

RUN git clone --filter=blob:none https://github.com/utmapp/virglrenderer.git /src/virglrenderer \
 && git -C /src/virglrenderer checkout "$VIRGLRENDERER_REV" \
 && for p in /patches/virglrenderer/*.patch; do git -C /src/virglrenderer apply "$p" || exit 1; done \
 && PKG_CONFIG_PATH=/opt/neptune/lib/pkgconfig \
    meson setup /build/virglrenderer /src/virglrenderer \
      --buildtype=release --prefix=/opt/neptune --libdir=lib \
      -Dvenus=true -Dneptune=true -Drender-server-worker=process \
      -Dcheck-gl-errors=false -Dtests=false -Dvtest=false \
 && meson install -C /build/virglrenderer

# Only what the VM uses: KVM, GTK with OpenGL (the window Cha streams),
# virglrenderer, PulseAudio (the streamer's sound server), slirp. qemu-img is
# needed for the disk. No SPICE: Cha streams the GTK window, and UTM's
# spice-display.c doesn't build against Linux GBM at this commit.
RUN git clone --filter=blob:none https://github.com/utmapp/qemu.git /src/qemu \
 && git -C /src/qemu checkout "$QEMU_REV" \
 && for p in /patches/qemu/*.patch; do git -C /src/qemu apply "$p" || exit 1; done \
 && mkdir -p /build/qemu && cd /build/qemu \
 && PKG_CONFIG_PATH=/opt/neptune/lib/pkgconfig \
    LDFLAGS=-Wl,-rpath,/opt/neptune/lib \
    /src/qemu/configure \
      --prefix=/opt/neptune \
      --target-list=x86_64-softmmu \
      --enable-kvm --enable-gtk --enable-opengl --enable-virglrenderer \
      --disable-spice --enable-slirp --enable-tools \
      --audio-drv-list=pa \
      --disable-sdl --disable-vnc-sasl --disable-docs --disable-werror \
 && make -j"$(nproc)" \
 && make install \
 && rm -rf /opt/neptune/share/doc /opt/neptune/include /opt/neptune/lib/pkgconfig \
 && { find /opt/neptune -type f \( -name '*.so*' -o -perm -u+x \) -exec strip --strip-unneeded {} + 2>/dev/null || true; } \
 && test -x /opt/neptune/bin/qemu-system-x86_64

FROM ${BASE}

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      dosfstools mtools ovmf python3 swtpm \
      libaio1t64 libcap-ng0 libdrm2 libepoxy0 libglib2.0-0t64 libgnutls30t64 \
      libgtk-3-0t64 libjpeg-turbo8 libpixman-1-0 libpng16-16t64 libseccomp2 \
      libslirp0 liburing2 libusb-1.0-0 libusbredirparser1t64 \
      libzstd1 mesa-vulkan-drivers vulkan-tools

COPY --from=build /opt/neptune /opt/neptune
# Fail the build, not the launch, on a library the runtime lacks.
RUN test -x /opt/neptune/bin/qemu-system-x86_64 \
 && missing=$(ldd /opt/neptune/bin/qemu-system-x86_64 /opt/neptune/bin/qemu-img \
                  /opt/neptune/lib/*.so /opt/neptune/libexec/* 2>/dev/null | grep 'not found' | sort -u) \
 && if [ -n "$missing" ]; then echo "$missing" >&2; exit 1; fi

COPY unattend /opt/cha-windows/unattend
COPY bin/cha-windows /usr/local/bin/cha-windows

# DXVK runs inside virglrenderer's render worker with no window system.
ENV NPT_D3D11_LIBRARY_PATH=/opt/neptune/lib/libdxvk_d3d11.so \
    NPT_DXGI_LIBRARY_PATH=/opt/neptune/lib/libdxvk_dxgi.so \
    DXVK_WSI_DRIVER=Headless \
    GDK_BACKEND=wayland

USER cha
CMD ["cha-windows"]

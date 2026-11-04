# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# LibrePods (AirPods control): built from source on every image build, because the
# published Linux release is far behind. The Rust rewrite on the `linux/rust` branch is
# what upstream recommends. CI passes the branch's current commit SHA as LIBREPODS_REF,
# which also busts the layer cache whenever upstream changes.
# Built on the same base as the final image so the binary links against identical libs.
FROM ghcr.io/ublue-os/aurora-dx:testing AS librepods-builder
ARG LIBREPODS_REPO=https://github.com/librepods-org/librepods.git
ARG LIBREPODS_REF=linux/rust
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=tmpfs,dst=/tmp \
    dnf5 install -y --setopt=install_weak_deps=False \
        cargo rust gcc pkgconf-pkg-config dbus-devel pulseaudio-libs-devel git && \
    git init -q /src && cd /src && \
    git remote add origin "${LIBREPODS_REPO}" && \
    git fetch -q --depth 1 origin "${LIBREPODS_REF}" && \
    git checkout -q FETCH_HEAD && \
    echo "Building LibrePods $(git rev-parse HEAD)" && \
    cd linux-rust && \
    CARGO_HOME=/tmp/cargo cargo build --release --locked && \
    mkdir -p /out/usr/bin /out/usr/share/applications /out/usr/share/icons/hicolor/256x256/apps /out/usr/share/librepods && \
    install -m755 target/release/librepods /out/usr/bin/librepods && \
    install -m644 assets/me.kavishdevar.librepods.desktop /out/usr/share/applications/me.kavishdevar.librepods.desktop && \
    install -m644 assets/icon.png /out/usr/share/icons/hicolor/256x256/apps/me.kavishdevar.librepods.png && \
    git -C /src rev-parse HEAD > /out/usr/share/librepods/commit

# Base Image
FROM ghcr.io/ublue-os/aurora-dx:testing

COPY --from=librepods-builder /out/ /

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
#
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN ln -sf /run /var/run

RUN rm -rf /var/run && \
    ln -s /run /var/run && \
    dnf clean all && \
    rm -rf /var/lib/dnf /var/cache/dnf /var/log/dnf*

RUN bootc container lint

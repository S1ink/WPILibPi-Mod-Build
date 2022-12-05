ARG BASE_IMAGE=i386/debian:bullseye
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get -y update && \
    apt-get -y install --no-install-recommends \
        git vim parted pkg-config \
        quilt coreutils qemu-user-static debootstrap zerofree zip dosfstools \
        libarchive-tools libcap2-bin rsync grep udev xz-utils curl xxd file kmod bc\
        binfmt-support ca-certificates qemu-utils kpartx fdisk gpg \
        build-essential cmake python3 python3-distutils python3-jinja2 ant sudo openjdk-17-jdk \
    && rm -rf /var/lib/apt/lists/*
# RUN echo "deb http://deb.debian.org/debian testing main non-free contrib" >> /etc/apt/sources.list &&  apt-get -y update && \
#         apt-get -y install --no-install-recommends g++-11-arm-linux-gnueabihf && \
#     sed -i '$d' /etc/apt/sources.list && apt-get -y update

COPY . /pi-gen/

VOLUME [ "/pi-gen/work", "/pi-gen/deploy"]

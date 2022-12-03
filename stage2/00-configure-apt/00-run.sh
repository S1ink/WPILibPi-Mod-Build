#!/bin/bash -e

echo "adding repo for edgetpu"
echo "deb https://packages.cloud.google.com/apt coral-edgetpu-stable main" > "${ROOTFS_DIR}/etc/apt/sources.list.d/coral-edgetpu.list"

wget -O- https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo tee /etc/apt/trusted.gpg.d/coral-edgetpu.gpg
#cat files/edgetpu.gpg | gpg --dearmor > "${ROOTFS_DIR}/etc/apt/trusted.gpg.d/coral-edgetpu.gpg"
#on_chroot apt-key add - < files/edgetpu.gpg
on_chroot << EOF
apt-get update
apt-get dist-upgrade -y
EOF

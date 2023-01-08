#!/bin/bash -e

echo "${TARGET_HOSTNAME}" > "${ROOTFS_DIR}/etc/hostname"
echo "127.0.1.1		${TARGET_HOSTNAME}" >> "${ROOTFS_DIR}/etc/hosts"

# ln -sf /dev/null "${ROOTFS_DIR}/etc/systemd/network/99-default.link"
on_chroot << EOF
	SUDO_USER="${FIRST_USER_NAME}" raspi-config nonint do_net_names 1
EOF
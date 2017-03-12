#!/usr/bin/env bash

drive="$1"
keyfile="$2"
mapper="$3"

MOUNTPOINT="/mnt/drive2"

function check_empty() {
    if [[ -z "${1// }" ]]
    then
        echo "USAGE:"
        echo "        ./chroot.sh [drive] [keyfile] [mapper]"
        exit 1
    fi
}

function mount_fn() {
    sudo mount -o subvol="@${1}" "/dev/mapper/${mapper}" "${MOUNTPOINT}/${2}"
}


check_empty "$drive"
check_empty "$keyfile"
check_empty "$mapper"


set -x

sudo cryptsetup luksOpen "${drive}2" "${mapper}" --key-file "${keyfile}"

sudo mount -o subvol=@ "/dev/mapper/${mapper}" "${MOUNTPOINT}"
sudo mkdir -p ${MOUNTPOINT}/{home,.snapshots,data,var/{cache/pacman/pkg,abs,tmp,log},srv,boot}

mount_fn home home
mount_fn snapshots .snapshots
mount_fn data data
mount_fn pkg var/cache/pacman/pkg
mount_fn abs var/abs
mount_fn tmp var/tmp
mount_fn log var/log
mount_fn srv srv

sudo mount "${drive}1" "${MOUNTPOINT}/boot"

sudo arch-chroot "${MOUNTPOINT}" /bin/bash

sudo umount -R "${MOUNTPOINT}"
sudo cryptsetup close "${mapper}"

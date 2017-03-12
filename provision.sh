#!/usr/bin/env bash

##
# BASICALLY JUST:
# https://github.com/NicoHood/NicoHood.github.io/wiki/Raspberry-Pi-Encrypted-Btrfs-Root
# but automated, and with a keyfile
##

drive="$1"
keyname="$2"
keypart="$3"
mapper="$4"


MOUNTPOINT="/mnt/drive2"
KEYMOUNT="/mnt/external"
ARCH_PACKAGE="ArchLinuxARM-rpi-latest.tar.gz"

function check_empty() {
    if [[ -z "${1// }" ]]
    then
        echo "USAGE:"
        echo "        ./provision.sh [drive] [keyname] [key partition] [mapper]"
        exit 1
    fi
}

function check_drive_use() {
    for line in $(lsblk "${1}" -o mountpoint | grep -vi "mountpoint");
    do
        if [[ ! -z "${line// }" ]]
        then
            echo "Error: ${1} is mounted at ${line}"
            exit 1
        fi
    done
}

function create_fn {
    sudo btrfs subvolume create "${MOUNTPOINT}/@${1}"
}

function mount_fn() {
    sudo mount -o subvol="@${1}" "/dev/mapper/${mapper}" "${MOUNTPOINT}/${2}"
}

keyfile="${KEYMOUNT}/${keyname}"

check_empty "${drive}"
check_empty "${keyfile}"
check_empty "${keypart}"
check_empty "${mapper}"

keyuuid=$(lsblk "${keypart}" -o uuid | tail -1)
keypart_fstype=$(lsblk "${keypart}" -o fstype | tail -1)

if [[ -z "${keyuuid// }" ]]
then
    echo "Error: could not get UUID from ${keypart}"
    exit 1
fi

if [[ -z "${keypart_fstype// }" ]]
then
    echo "Error: could not get filesystem type from ${keypart}"
    exit 1
fi


check_drive_use "${drive}"


set -x


sudo fdisk "${drive}" <<EOF
o
n



+100M
t
c
n




w

EOF

sudo dd if=/dev/zero of="${drive}1" bs=4M
sudo dd if=/dev/zero of="${drive}2" bs=4M

sudo mount "${keypart}" "${KEYMOUNT}"

if [ ! -f "${keyfile}" ]
then
    sudo dd bs=512 count=4 if=/dev/urandom of="${keyfile}"
fi

sudo cryptsetup luksFormat -c aes-xts-plain64 -s 512 -h sha512 --use-random -i 3000 "${drive}2" "${keyfile}"
sudo cryptsetup luksOpen "${drive}2" "${mapper}" --key-file "${keyfile}"

sudo mkdir -p ${MOUNTPOINT}

sudo mkfs.btrfs "/dev/mapper/${mapper}"
sudo mount "/dev/mapper/${mapper}" ${MOUNTPOINT}

sudo btrfs subvolume create "${MOUNTPOINT}/@"
create_fn home
create_fn snapshots
create_fn data
create_fn pkg
create_fn abs
create_fn tmp
create_fn log
create_fn srv

sudo umount -R ${MOUNTPOINT}

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

sudo mkfs.vfat "${drive}1"
sudo mount "${drive}1" ${MOUNTPOINT}/boot

if [ ! -f "${ARCH_PACKAGE}" ]
then
    curl -LO "http://os.archlinuxarm.org/os/${ARCH_PACKAGE}"
fi

sudo bsdtar -xpf ${ARCH_PACKAGE} -C ${MOUNTPOINT}
sync

sudo pacman -S arch-install-scripts -y --needed --noconfirm

sudo genfstab -U "${MOUNTPOINT}" | sudo tee "${MOUNTPOINT}/etc/fstab"
sudo arch-chroot "${MOUNTPOINT}" /bin/bash <<EOF
pacman -Syu --noconfirm
pacman -S mkinitcpio --needed --noconfirm
pacman -S btrfs-progs --needed --noconfirm
pacman -S sudo --needed --noconfirm
pacman -S bash-completion --needed --noconfirm

sed -i 's/^HOOKS=".*block/\0 keymap encrypt/g' /etc/mkinitcpio.conf
sed -i "s#^BINARIES=\"#\0/usr/bin/btrfs#g" /etc/mkinitcpio.conf
mkinitcpio -k \$(uname -r) -g /boot/initrd -c /etc/mkinitcpio.conf

echo "initramfs initrd followkernel" >> /boot/config.txt
sed -i "s#root[^ ]*#cryptdevice=UUID=\$(blkid ${drive}2 -o value -s UUID):${mapper} cryptkey=UUID=${keyuuid}:${keypart_fstype}:/${keyname} root=/dev/mapper/${mapper} rootflags=subvol=/@#g" /boot/cmdline.txt

sed -i '/%wheel.ALL=(ALL) ALL/s/^# //g' /etc/sudoers
usermod -a -G users alarm
usermod -a -G wheel alarm
passwd -l root
EOF

sudo umount -R "${MOUNTPOINT}"
sudo cryptsetup close "${mapper}"

echo "Don't forget to change passwords!"

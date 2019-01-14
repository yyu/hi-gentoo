####!/usr/bin/env bash

dev=/dev/nvme1n1
dev1=${dev}p1
dev2=${dev}p2
mount_point=/mnt/gentoo
downloads=/tmp/gentoo

bootfs="$mount_point/1"
rootfs="$mount_point/2"

setup_kissbash() {
    rm -rf /tmp/.kissbash
    git clone https://github.com/yyu/kissbash.git /tmp/.kissbash

    export KISSBASH_PATH=/tmp/.kissbash/kissbash

    . $KISSBASH_PATH/console/lines
    . $KISSBASH_PATH/exec/explicitly
}

drproper() {
    for d in $dev1 $dev2; do
        color ylw "checking $d"
        if grep $d <(explicitly mount | grep ^/dev | tee_serr_with_color YLW); then
            explicitly sudo umount $d
        fi
    done
    explicitly mount | grep ^/dev | serr_with_color YLW
}

let_there_be_disk() {
    serr_with_color YLW '--------------------------------------------------------------------------------'
    explicitly sudo dd if=/dev/zero of=/dev/nvme1n1 bs=1M count=333
    explicitly sed -E 's/ *(#.*)*//g' > /tmp/fdisk.input << "EOF"
        o # clear the in memory partition table
        n # new partition
        p # primary partition
        1 # partition number 1
          # default - start at beginning of disk 
        +256M # boot parttion
        n # new partition
        p # primary partition
        2 # partion number 2
          # default, start immediately after preceding partition
          # default, extend partition to end of disk
        a # make a partition bootable
        1 # bootable partition is partition 1 -- /dev/sda1
        p # print the in-memory partition table
        w # write the partition table
        q # and we're done
EOF
cat /tmp/fdisk.input | tee_serr_with_color YLW | explicitly sudo fdisk $dev | grep -C 999 --color -E '\([^)/]*\):'
    #explicitly sudo fdisk $dev < /tmp/fdisk.input
    explicitly sudo fdisk -l $dev
    explicitly sudo mkfs.ext4 -F $dev1 | grep -C 999 --color 'UUID.*'
    explicitly sudo mkfs.ext4 -F $dev2 | grep -C 999 --color 'UUID.*'
}

mount_disk() {
    explicitly sudo mkdir -p $bootfs
    explicitly sudo mkdir -p $rootfs
    explicitly sudo mount $dev1 $bootfs
    explicitly sudo mount $dev2 $rootfs
}

stage4() {
    local folder=distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd/
    local tarball=stage4-amd64-systemd-20190108.tar.bz2

    mkdir -p $downloads
    cd $downloads
    if [ ! -f $tarball ]; then
        color ylw "$tarball exists"
        explicitly wget --recursive --no-parent http://$folder
    fi

    sudo cp -v $folder/$tarball $rootfs
    cd $rootfs
    explicitly sudo tar xpf "$tarball" --xattrs-include='*.*' --numeric-owner
    explicitly sudo rm $tarball
}

let_there_be_portage() {
    sudo mkdir -p $rootfs/etc/portage/repos.conf
    sudo cp -f $rootfs/usr/share/portage/config/repos.conf $rootfs/etc/portage/repos.conf/gentoo.conf

    local url=http://distfiles.gentoo.org/snapshots/portage-latest.tar.xz
    local tarball=`basename "$url"`

    mkdir -p $downloads
    cd $downloads
    if [ ! -f $tarball ]; then
        color ylw "$tarball exists"
        explicitly wget $url
    fi
    sudo cp -v $tarball $rootfs
    cd $rootfs
    explicitly sudo tar xpf "$tarball" -C usr --xattrs-include='*.*' --numeric-owner
    explicitly sudo rm $tarball
}

adjust_bootfs() {
    sudo mv -v * "$rootfs"/boot/* "$bootfs"/
    sudo umount "$bootfs"
    sudo mount $dev1 "$rootfs"/boot
    bootfs="$rootfs"/boot
}

sofarsogood() {
    let_there_be_disk
    mount_disk
    stage4
    let_there_be_portage
}



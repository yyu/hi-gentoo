####!/usr/bin/env bash

SELF="${BASH_SOURCE[0]}"
naked_self=`basename $SELF`

#export dev=/dev/nvme1n1
#export dev1=${dev}p1
#export dev2=${dev}p2

export dev=/dev/xvdf
export dev1=${dev}1
export dev2=${dev}2

export mount_point=/mnt/gentoo
export downloads=/tmp/gentoo

export bootfs="$mount_point/1"
export rootfs="$mount_point/2"
export bootfs_label=boot
export rootfs_label=rootfs

setup_kissbash() {
    echo -e "\033[32msetup_kissbash--------------------------------------------------------------------------------\033[0m"

    rm -rf /tmp/.kissbash
    git clone https://github.com/yyu/kissbash.git /tmp/.kissbash

    export KISSBASH_PATH=/tmp/.kissbash/kissbash

    . $KISSBASH_PATH/term/colors
    . $KISSBASH_PATH/term/control
    . $KISSBASH_PATH/console/lines
    . $KISSBASH_PATH/exec/explicitly
}

print_sys_info() {
    serr_with_color GRY 'print_sys_info--------------------------------------------------------------------------------'

    explicitly      lscpu | serr_with_color blu
    explicitly      lspci | serr_with_color MGT
    explicitly      lsblk | serr_with_color CYN
    explicitly sudo lshw  | serr_with_color YLW
    explicitly      lsmod | serr_with_color GRN
}

drproper() {
    serr_with_color GRY 'drproper--------------------------------------------------------------------------------'

    cd
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

    explicitly sudo dd if=/dev/zero of=$dev bs=1M count=333
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
    explicitly sudo e2label $dev1 $bootfs_label
    explicitly sudo e2label $dev2 $rootfs_label
}

mount_disk() {
    serr_with_color GRY 'mount_disk--------------------------------------------------------------------------------'

    explicitly sudo rm -rf $bootfs
    explicitly sudo rm -rf $rootfs
    explicitly sudo mkdir -p $bootfs
    explicitly sudo mkdir -p $rootfs
    explicitly sudo mount $dev1 $bootfs
    explicitly sudo mount $dev2 $rootfs
}

stage4() {
    serr_with_color GRY 'stage4--------------------------------------------------------------------------------'

    local folder=distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd/

    mkdir -p $downloads
    cd $downloads
    pwd | serr_with_color ylw

    local tarball=`find . -name "stage4*bz2"`

    if [ -f "$tarball" ]; then
        color ylw "$tarball exists"
    else
        color ylw "tarball does not exist $tarball"
        explicitly wget --recursive --no-parent http://$folder
    fi

    tarball=`find . -name "stage4*bz2"`
    if [ ! -f "$tarball" ]; then
        color red "didn't find $tarball even after downloading"
        return
    fi

    sudo cp -v $tarball $rootfs
    cd $rootfs
    pwd | serr_with_color ylw
    tarball=`basename $tarball`
    date | serr_with_color ylw
    explicitly sudo tar xpf "$tarball" --xattrs-include='*.*' --numeric-owner
    date | serr_with_color ylw
    explicitly sudo rm $tarball
}

let_there_be_portage() {
    serr_with_color GRY 'let_there_be_portage--------------------------------------------------------------------------------'

    sudo mkdir -p $rootfs/etc/portage/repos.conf
    sudo cp -f $rootfs/usr/share/portage/config/repos.conf $rootfs/etc/portage/repos.conf/gentoo.conf

    local url=http://distfiles.gentoo.org/snapshots/portage-latest.tar.xz
    local tarball=`basename "$url"`

    mkdir -p $downloads
    cd $downloads
    if [ -f $tarball ]; then
        color ylw "$tarball exists"
    else
        explicitly wget $url
    fi
    sudo cp -v $tarball $rootfs
    cd $rootfs
    explicitly sudo tar xpf "$tarball" -C usr --xattrs-include='*.*' --numeric-owner
    explicitly sudo rm $tarball
}

sudo_comment_all() {
    serr_with_color GRY 'sudo_comment_all--------------------------------------------------------------------------------'

    local filename=$1
    sudo sed -i -E 's/^(.*)$/#\1/g' $filename
}

make_tmpf_from() {
    serr_with_color GRY 'make_tmpf_from--------------------------------------------------------------------------------'

    local f=$1
    local tmpf=`mktemp`

    cat $f >> $tmpf

    echo >> $tmpf
    echo "# |                |" >> $tmpf
    echo "# | added by magic |" >> $tmpf
    echo "# V                V" >> $tmpf
    echo >> $tmpf

    echo $tmpf
}

sudo_append() {
    serr_with_color GRY 'sudo_append--------------------------------------------------------------------------------'

    local dest=$1
    shift
    local tmpf=`make_tmpf_from $dest`
    echo "$*" >> $tmpf
    sudo cp -vf $tmpf $dest
}

sudo_append_file() {
    serr_with_color GRY 'sudo_append_file--------------------------------------------------------------------------------'

    local dest=$1
    local src=$2
    local tmpf=`make_tmpf_from $dest`
    cat $src >> $tmpf
    sudo cp -vf $tmpf $dest
}

adjust_bootfs() {
    serr_with_color GRY 'adjust_bootfs--------------------------------------------------------------------------------'

    explicitly sudo mv -v "$rootfs"/boot/* "$bootfs"/
    explicitly sudo umount "$bootfs"
    explicitly sudo mount $dev1 "$rootfs"/boot
    bootfs="$rootfs"/boot
}

setup_fstab() {
    serr_with_color GRY 'setup_fstab--------------------------------------------------------------------------------'

    sudo_comment_all $rootfs/etc/fstab

    tmp_fstab=/tmp/fstab
    echo "LABEL=$rootfs_label       /       ext4        defaults        0 0" > $tmp_fstab
    sudo_append_file $rootfs/etc/fstab $tmp_fstab
    /bin/rm $tmp_fstab

    cat $rootfs/etc/fstab | serr_with_color ylw
}

setup_net() {
    serr_with_color GRY 'setup_net--------------------------------------------------------------------------------'

    sudo_comment_all $rootfs/etc/resolv.conf
    sudo_append_file $rootfs/etc/resolv.conf /etc/resolv.conf

    cat $rootfs/etc/resolv.conf | serr_with_color ylw

    cat > /tmp/50-dhcp.network << "END"
[Match]
Name=*

[Network]
DHCP=yes
END

    explicitly sudo cp -v /tmp/50-dhcp.network $rootfs/etc/systemd/network/50-dhcp.network
}

setup_ec2_init() {
    cat > $rootfs/tmp/ec2init << "EOF"
#!/bin/sh

provision_instance() {
    lock="/var/lib/amazon-ec2-init.lock"
    instance_id="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

    [ -f "$lock" ] && [ "$(cat "$lock")" = "$instance_id" ] && exit 0

    echo "Provisioning instance..."

    provision_hostname
    provision_ssh_authorized_keys
    provision_systemd_machine_id

    echo "$instance_id" > "$lock"
}

provision_hostname() {
    echo "Setting hostname..."

    hostnamectl set-hostname \
        "$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)"
}

provision_ssh_authorized_keys() {
    echo "Importing SSH authorized keys..."

    [ -e /root/.ssh ] && rm -rf /root/.ssh
    mkdir -p /root/.ssh
    chown root:root /root/.ssh
    chmod 750 /root/.ssh

    keys="$(curl -s http://169.254.169.254/latest/meta-data/public-keys/ \
        | cut -d = -f 1 \
        | xargs printf "http://169.254.169.254/latest/meta-data/public-keys/%s/openssh-key\n")"

    if [ -n "$keys" ]; then
        curl -s $keys > /root/.ssh/authorized_keys
        chown root:root /root/.ssh/authorized_keys
        chmod 640 /root/.ssh/authorized_keys
    fi
}

provision_systemd_machine_id() {
    echo "Regenerating systemd machine ID..."

    systemd-machine-id-setup
}

provision_instance
EOF

    cat > $rootfs/tmp/ec2init.service << "EOF"
[Unit]
Description=Amazon EC2 Init
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/amazon-ec2-init

[Install]
WantedBy=multi-user.target
EOF
}

configure_portage() {
    serr_with_color GRY 'configure_portage--------------------------------------------------------------------------------'

    explicitly sudo sed -E '/COMMON_FLAGS=/s/="/="-march=native /g' -i $rootfs/etc/portage/make.conf
    sudo_append $rootfs/etc/portage/make.conf 'MAKEOPTS="-j'`nproc`'"'

    sudo mkdir --parents $rootfs/etc/portage/repos.conf
    explicitly sudo cp -v $rootfs/usr/share/portage/config/repos.conf $rootfs/etc/portage/repos.conf/gentoo.conf
}

done_chroot() {
    serr_with_color GRY 'done_chroot--------------------------------------------------------------------------------'

    cd
    explicitly sudo umount -l $rootfs/dev{/shm,/pts,}
    explicitly sudo umount -R $rootfs
}

do_chroot() {
    serr_with_color GRY 'do_chroot--------------------------------------------------------------------------------'

    #explicitly cp -vf $SELF $rootfs$downloads

    cat > $rootfs/tmp/after_chroot << EOF
. /etc/profile
export PS1="(chroot) \${PS1}"
alias lh='ls -lh --color'
x() {
    umount /boot
    exit
}

setup_grub() {
    sed -E '/GRUB_CMDLINE_LINUX=/s|"$| init=/lib/systemd/systemd"|g' -i /etc/default/grub
    grub-install $dev
    grub-mkconfig -o /boot/grub/grub.cfg
}

setup_systemd() {
    systemd-machine-id-setup

    systemctl enable systemd-networkd.service

    ln -snf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    systemctl enable systemd-resolved.service
    systemctl enable sshd.service
}

setup_ec2init() {
    cp -vf /tmp/ec2init /usr/local/bin/amazon-ec2-init
    chmod +x /usr/local/bin/amazon-ec2-init
    cp -vf /tmp/ec2init.service /etc/systemd/system/amazon-ec2-init.service
    systemctl enable amazon-ec2-init.service
}

echo 'now do:
setup_grub
setup_systemd
setup_ec2init
'
EOF
    #echo ". $downloads/$naked_self" >> $rootfs/tmp/after_chroot

    cat > $rootfs/root/setup.sh << "EOF"
setup_essentials() {
    eselect profile list
    echo -n "which profile? "
    read profile_num
    eselect profile set $profilenum
    emerge -DUnv @world
    emerge -DUnv vim
    emerge -DUnv dev-vcs/git
    emerge -DUnv tmux
    emerge -DUnv vim
    python3 "$(curl -fsSL https://git.io/v7LAT)"
}
EOF

    explicitly sudo mount --types proc   /proc $rootfs/proc
    explicitly sudo mount --rbind        /sys  $rootfs/sys
    explicitly sudo mount --make-rslave        $rootfs/sys
    explicitly sudo mount --rbind        /dev  $rootfs/dev
    explicitly sudo mount --make-rslave        $rootfs/dev
    explicitly sudo chroot $rootfs /bin/bash --rcfile /tmp/after_chroot -i
    done_chroot
}

prepare_and_chroot() {
    echo '
    if ! explicitly echo; then
        setup_kissbash
    fi
    drproper
    let_there_be_disk
    mount_disk
    stage4
    let_there_be_portage
    adjust_bootfs
    setup_fstab
    setup_net
    configure_portage
    setup_ec2_init
    do_chroot
    '
}



#!/bin/bash
set -e

BOARD=
IMAGE_SIZE=4G
IMAGE_FILE=""
CHROOT_TARGET=target

LOOP_DEVICE=""
EFI_MOUNTPOINT=""
BOOT_MOUNTPOINT=""
ROOT_MOUNTPOINT=""

KERNEL_FOLDER=..
UBOOT_FOLDER=..

BASE_TOOLS="binutils file tree sudo bash-completion openssh-server network-manager dnsmasq-base libpam-systemd ppp wireless-regdb wpasupplicant libengine-pkcs11-openssl iptables systemd-timesyncd vim usbutils libgles2 parted exfatprogs systemd-sysv mesa-vulkan-drivers"
XFCE_DESKTOP="xorg xfce4 desktop-base lightdm xfce4-terminal tango-icon-theme xfce4-notifyd xfce4-power-manager network-manager-gnome xfce4-goodies pulseaudio alsa-utils dbus-user-session rtkit pavucontrol thunar-volman eject gvfs gvfs-backends udisks2 dosfstools e2fsprogs libblockdev-crypto2 ntfs-3g polkitd blueman"
GNOME_DESKTOP="gnome-core avahi-daemon desktop-base file-roller gnome-tweaks gstreamer1.0-libav gstreamer1.0-plugins-ugly libgsf-bin libproxy1-plugin-networkmanager network-manager-gnome"
KDE_DESKTOP="kde-plasma-desktop"
BENCHMARK_TOOLS="glmark2-es2 mesa-utils vulkan-tools iperf3 stress-ng"
#FONTS="fonts-crosextra-caladea fonts-crosextra-carlito fonts-dejavu fonts-liberation fonts-liberation2 fonts-linuxlibertine fonts-noto-core fonts-noto-cjk fonts-noto-extra fonts-noto-mono fonts-noto-ui-core fonts-sil-gentium-basic"
FONTS="fonts-noto-core fonts-noto-cjk fonts-noto-mono fonts-noto-ui-core"
INCLUDE_APPS="chromium libqt5gui5-gles vlc gimp gimp-data-extras gimp-plugin-registry gimp-gmic"
EXTRA_TOOLS="i2c-tools net-tools ethtool"
LIBREOFFICE="libreoffice-base \
libreoffice-calc \
libreoffice-core \
libreoffice-draw \
libreoffice-impress \
libreoffice-math \
libreoffice-report-builder-bin \
libreoffice-writer \
libreoffice-nlpsolver \
libreoffice-report-builder \
libreoffice-script-provider-bsh \
libreoffice-script-provider-js \
libreoffice-script-provider-python \
libreoffice-sdbc-mysql \
libreoffice-sdbc-postgresql \
libreoffice-wiki-publisher \
"
DOCKER="docker.io apparmor ca-certificates cgroupfs-mount git needrestart xz-utils"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

make_imagefile()
{
    IMAGE_FILE="d1-sdcard-$TIMESTAMP.img"
    truncate -s "$IMAGE_SIZE" "$IMAGE_FILE"

    # Create a efi partition and a root partition
    parted -s -a optimal -- "${IMAGE_FILE}" mklabel gpt
    parted -s -a optimal -- "${IMAGE_FILE}" mkpart primary fat32 40MiB 1024MiB
    parted -s -a optimal -- "${IMAGE_FILE}" set 1 esp on
    parted -s -a optimal -- "${IMAGE_FILE}" mkpart primary ext4 1064MiB 100%

    # Get loop device name
    # losetup --partscan --find --show "$IMAGE_FILE"
    losetup --partscan --show /dev/loop99 "$IMAGE_FILE"
	# LOOP_DEVICE=$(losetup -j "$IMAGE_FILE" | grep -o "/dev/loop[0-9]*")
    LOOP_DEVICE="/dev/loop99"

    # Format partitions
    mkfs.ext2 -F -L boot "$LOOP_DEVICE"p1
    mkfs.ext4 -F -L root "$LOOP_DEVICE"p2
}

pre_mkrootfs()
{
    partprobe "$LOOP_DEVICE"
    # Mount loop device
	mkdir "$CHROOT_TARGET"
	mount -t ext4 "$LOOP_DEVICE"p2 "$CHROOT_TARGET"
}

make_rootfs()
{
    if [ -n $ROOTFS_TARBALL ] && ! (tar xf $ROOTFS_TARBALL -C $CHROOT_TARGET) ; then
        mmdebstrap --architectures=riscv64 \
        --include="ca-certificates revyos-keyring locales dosfstools \
        sudo bash-completion network-manager openssh-server systemd-timesyncd" \
        sid "$CHROOT_TARGET" \
        "deb [trusted=yes] https://mirror.iscas.ac.cn/revyos/revyos-base/ sid main contrib non-free non-free-firmware" \
        "deb [trusted=yes] https://mirror.iscas.ac.cn/revyos/revyos-addons/ revyos-addons main"
    fi

    # Mount chroot path
    [ -d "$CHROOT_TARGET"/boot ] || mkdir "$CHROOT_TARGET"/boot
    mount "$LOOP_DEVICE"p1 "$CHROOT_TARGET"/boot
    # mount -t proc /proc "$CHROOT_TARGET"/proc
    # mount -B /sys "$CHROOT_TARGET"/sys
    # mount -B /run "$CHROOT_TARGET"/run
    # mount -B /dev "$CHROOT_TARGET"/dev
    # mount -B /dev/pts "$CHROOT_TARGET"/dev/pts

    # apt update
    chroot "$CHROOT_TARGET" /bin/sh -c "apt update && sed -i 's/\[trusted=yes\] //g' /etc/apt/sources.list" || [ -n $ROOTFS_TARBALL ] && echo custom tarball apt update fail
}

make_kernel()
{
    # Install Kernel
    mkdir $KERNEL_FOLDER
    [ -f kernel*.tar.gz ] || unzip kernel*.tar.gz.zip
    tar xvf kernel*.tar.gz -C $KERNEL_FOLDER/
    cp -rv $KERNEL_FOLDER/rootfs/boot/* $CHROOT_TARGET/boot/
    cp -rv $KERNEL_FOLDER/rootfs/lib/* $CHROOT_TARGET/lib/
    rm -v kernel*.tar.gz
    rm -r $KERNEL_FOLDER
}

make_bootable()
{
    # Mount EFI partition
    mkdir "$CHROOT_TARGET"/boot/efi
    mount -t vfat "$LOOP_DEVICE"p1 "$CHROOT_TARGET"/boot/efi

    # Install grub
    chroot "$CHROOT_TARGET" sh -c "apt install -y grub2-common grub-efi-riscv64-bin"
    chroot "$CHROOT_TARGET" sh -c "grub-install"

    # Install u-boot and opensbi
    mkdir $UBOOT_FOLDER
    ( ls misc*.tar.gz ) || unzip misc*.tar.gz.zip
    _UBOOT_SPL_BIN=$(tar xvf misc*.tar.gz -C $UBOOT_FOLDER/ | grep -o ".*-with-spl.bin")
    dd if=${UBOOT_FOLDER}/${_UBOOT_SPL_BIN} of="${LOOP_DEVICE}" bs=1024 seek=128
    rm -v misc*.tar.gz
    rm -r $UBOOT_FOLDER

    APT_UBOOT="apt-get install -y u-boot-menu"
    if [ -n "$ROOTFS_TARBALL" ]; then
        case "$ROOTFS_TARBALL" in 
            *alpine*)
                APT_UBOOT="apk add u-boot-menu"
                ;;
            *debian*)
                ;;
            *)
                APT_UBOOT=""
                ;;
        esac
    fi
    # hack for alpine
    (systemd-nspawn -D "$CHROOT_TARGET" sh -c "APT_UBOOT") || (chroot "$CHROOT_TARGET" sh -c "$APT_UBOOT")
    chroot "$CHROOT_TARGET" sh -c "mkdir -p /etc/default && echo 'U_BOOT_ROOT="root=/dev/mmcblk0p2"' | tee -a /etc/default/u-boot"
    chroot "$CHROOT_TARGET" sh -c "echo 'U_BOOT_PARAMETERS=\"rw earlycon=sbi console=tty0 console=ttyS0,115200 rootwait \"' | tee -a /etc/default/u-boot"
    # chroot "$CHROOT_TARGET" sh -c "echo 'U_BOOT_FDT_DIR=\"/boot/dtbs/\"' | tee -a /etc/default/u-boot"
    chroot "$CHROOT_TARGET" sh -c "u-boot-update || update-u-boot" && echo u-boot-update fail
}

after_mkrootfs()
{
    # Set up fstab
	EFI_UUID=$(blkid -o value -s UUID "$LOOP_DEVICE"p1)
	ROOT_UUID=$(blkid -o value -s UUID "$LOOP_DEVICE"p2)
	chroot "$CHROOT_TARGET" sh -c "echo 'UUID=$EFI_UUID	/boot/efi	vfat	rw,relatime	0 2' >> /etc/fstab"
	chroot "$CHROOT_TARGET" sh -c "echo 'UUID=$ROOT_UUID	/	ext4	rw,relatime	0 1' >> /etc/fstab"

    # Add user
    chroot "$CHROOT_TARGET" sh -c "useradd -m -s /bin/bash -G adm,sudo debian || adduser -h /home/debian -G sys debian"
    chroot "$CHROOT_TARGET" sh -c "echo 'debian:debian' | chpasswd"

    # Change hostname
	chroot "$CHROOT_TARGET" sh -c "echo d1 > /etc/hostname"
	chroot "$CHROOT_TARGET" sh -c "echo 127.0.1.1 d1 >> /etc/hosts"

    # Add timestamp file in /etc
    echo "$TIMESTAMP" > $CHROOT_TARGET/etc/revyos-release

    # remove openssh keys
    rm -v $CHROOT_TARGET/etc/ssh/ssh_host_*	

    # copy addons to rootfs
    # cp -rp addons/lib/firmware $CHROOT_TARGET/lib/
    # cp -rp addons/lib/modules $CHROOT_TARGET/lib/
    # cp -rp addons/sbin/perf-thead $CHROOT_TARGET/sbin/

    # Add Bluetooth firmware and service
    # cp -rp addons/lpi4a-bt/rootfs/usr/local/bin/rtk_hciattach $CHROOT_TARGET/usr/local/bin/
    # cp -rp addons/lpi4a-bt/rootfs/lib/firmware/rtlbt/rtl8723d_config $CHROOT_TARGET/lib/firmware/rtlbt/
    # cp -rp addons/lpi4a-bt/rootfs/lib/firmware/rtlbt/rtl8723d_fw $CHROOT_TARGET/lib/firmware/rtlbt/
    # cp -rp addons/etc/systemd/system/rtk-hciattach.service $CHROOT_TARGET/etc/systemd/system/

    # Add firstboot service
    # cp -rp addons/etc/systemd/system/firstboot.service $CHROOT_TARGET/etc/systemd/system/
    # cp -rp addons/opt/firstboot.sh $CHROOT_TARGET/opt/

    # Install system services
    # chroot "$CHROOT_TARGET" sh -c "systemctl enable pvrsrvkm"
    # chroot "$CHROOT_TARGET" sh -c "systemctl enable firstboot"
    # chroot "$CHROOT_TARGET" sh -c "systemctl enable rtk-hciattach"

    # Use iptables-legacy for docker
    # chroot "$CHROOT_TARGET" sh -c "update-alternatives --set iptables /usr/sbin/iptables-legacy"
    # chroot "$CHROOT_TARGET" sh -c "update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy"

    # refresh so libs
    chroot "$CHROOT_TARGET" sh -c "rm -v /etc/ld.so.cache" || echo rm /etc/ld.so.cache failed
    chroot "$CHROOT_TARGET" sh -c "ldconfig"
}

unmount_image()
{
	echo "Finished and cleaning..."
	if mount | grep "$CHROOT_TARGET" > /dev/null; then
		umount -l "$CHROOT_TARGET"
	fi
    if losetup -l | grep "$LOOP_DEVICE" > /dev/null; then
        losetup -d "$LOOP_DEVICE"
    fi
	if [ "$(ls -A $CHROOT_TARGET)" ]; then
		echo "folder not empty! umount may fail!"
		exit 2
	elif [ -n $KEEP_ROOTFS ]; then
		echo "Deleting chroot temp folder..."
		if [ -d "$CHROOT_TARGET" ]; then
			rmdir -v "$CHROOT_TARGET"
		fi
		echo "Done."
	fi
}

cleanup_env()
{
    echo "Cleanup temp files..."
    # remove temp file here
    echo "Done."
}

calculate_md5()
{
    echo "Calculate MD5 for outputs..."
		if [ ! -z $IMAGE_FILE ] && [ -f $IMAGE_FILE ]; then
			echo "$(md5sum $IMAGE_FILE)"
		fi
		if [ ! -z $BOOT_IMG ] && [ -f $BOOT_IMG ]; then
			echo "$(md5sum $BOOT_IMG)"
		fi
		if [ ! -z $ROOT_IMG ] && [ -f $ROOT_IMG ]; then
			echo "$(md5sum $ROOT_IMG)"
		fi
}

main()
{
#   install_depends
    make_imagefile
    pre_mkrootfs
  # use CUSTOM_MIRROR to specify mirror
  # use ROOTFS_TAR = path/to/tar to use exist tarball
    make_rootfs
    make_kernel
    make_bootable
  # keep rootfs if KEEP_ROOTFS is not empty, uses in ci
	after_mkrootfs
	exit
}

# Check root privileges:
if (( $EUID != 0 )); then
    echo "Please run as root"
    exit 1
fi

trap return 2 INT
trap clean_on_exit EXIT

clean_on_exit()
{
    if ( chroot "$CHROOT_TARGET" /bin/bash ) || [ -z "$KEEP_IMAGE" ]; then
        unmount_image
        cleanup_env
        echo "Build succeed."
        calculate_md5
    else
        unmount_image
        cleanup_env
        if [ -f $IMAGE_FILE ]; then
            echo "delete image $IMAGE_FILE ..."
            rm -v "$IMAGE_FILE"
        fi
        echo "interrupted exit."
    fi
}

main

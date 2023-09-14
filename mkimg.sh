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

KERNEL_FOLDER=kernel
UBOOT_FOLDER=uboot

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
	sgdisk -og "$IMAGE_FILE"
	sgdisk -n 1:2048:+500M -c 1:"BOOT" -t 1:ef00 "$IMAGE_FILE"
	ENDSECTOR=$(sgdisk -E "$IMAGE_FILE")
	sgdisk -n 2:0:"$ENDSECTOR" -c 2:"ROOT" -t 2:8300 -A 2:set:2 "$IMAGE_FILE"
	sgdisk -p "$IMAGE_FILE"

    # Get loop device name
    losetup --partscan --find --show "$IMAGE_FILE"
	LOOP_DEVICE=$(losetup -j "$IMAGE_FILE" | grep -o "/dev/loop[0-9]*")

    # Format partitions
	mkfs.ext4 -F -L boot "$LOOP_DEVICE"p1
	mkfs.ext4 -F -L root "$LOOP_DEVICE"p2
}

pre_mkrootfs()
{
    # Mount loop device
	mkdir "$CHROOT_TARGET"
	mount "$LOOP_DEVICE"p2 "$CHROOT_TARGET"
}

make_rootfs()
{
<<<<<<< HEAD
    mmdebstrap --architectures=riscv64 --variant=minbase \
    --include="ca-certificates debian-ports-archive-keyring locales dosfstools \
        sudo bash-completion network-manager openssh-server systemd-timesyncd" \
    sid "$CHROOT_TARGET" \
    "deb https://mirror.iscas.ac.cn/debian-ports/ sid main contrib non-free"
=======
    if [ -n $ROOTFS_TARBALL ] && ! (tar xf $ROOTFS_TARBALL -C $CHROOT_TARGET) ; then
        mmdebstrap --architectures=riscv64 --variant=minbase \
        --include="ca-certificates debian-ports-archive-keyring locales dosfstools \
            sudo bash-completion network-manager openssh-server systemd-timesyncd" \
        sid "$CHROOT_TARGET" \
        "deb [trusted=yes] ${CUSTOM_MIRROR:-"https://deb.debian.org/debian-ports"} sid main contrib non-free"
    fi
>>>>>>> a9d594e (mkimg.sh: add ROOTFS_TARBALL to use custom rootfs)

    # Mount chroot path
    [ -d "$CHROOT_TARGET"/boot ] || mkdir "$CHROOT_TARGET"/boot
    mount "$LOOP_DEVICE"p1 "$CHROOT_TARGET"/boot
    # mount -t proc /proc "$CHROOT_TARGET"/proc
    # mount -B /sys "$CHROOT_TARGET"/sys
    # mount -B /run "$CHROOT_TARGET"/run
    # mount -B /dev "$CHROOT_TARGET"/dev
    # mount -B /dev/pts "$CHROOT_TARGET"/dev/pts

    # apt update
<<<<<<< HEAD
    chroot "$CHROOT_TARGET" sh -c "apt update"
=======
    chroot "$CHROOT_TARGET" sh -c "apt update && sed -i 's/\[trusted=yes\] //g' /etc/apt/sources.list" || [ -n $ROOTFS_TARBALL ] && echo custom tarball apt update fail
>>>>>>> a9d594e (mkimg.sh: add ROOTFS_TARBALL to use custom rootfs)
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
    # Install u-boot and opensbi
    mkdir $UBOOT_FOLDER
    [ -f misc*.tar.gz ] || unzip misc*.tar.gz.zip
    _UBOOT_SPL_BIN=$(tar xvf misc*.tar.gz -C $UBOOT_FOLDER/ | grep -o ".*-with-spl.bin")
    dd if=${UBOOT_FOLDER}/${_UBOOT_SPL_BIN} of="${LOOP_DEVICE}" bs=1024 seek=128
    rm -v misc*.tar.gz
    rm -r $UBOOT_FOLDER

    APT_UBOOT="apt-get install -y u-boot-menu"
    if [ -n $ROOTFS_TARBALL ]; then
        case $ROOTFS_TARBALL in 
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
    chroot "$CHROOT_TARGET" sh -c "$APT_UBOOT"
    chroot "$CHROOT_TARGET" sh -c "mkdir -p /etc/default && echo 'U_BOOT_ROOT="root=/dev/mmcblk0p2"' | tee -a /etc/default/u-boot"
    chroot "$CHROOT_TARGET" sh -c "echo 'U_BOOT_PARAMETERS=\"rw earlycon=sbi console=tty0 console=ttyS0,115200 rootwait \"' | tee -a /etc/default/u-boot"
    # chroot "$CHROOT_TARGET" sh -c "echo 'U_BOOT_FDT_DIR=\"/boot/dtbs/\"' | tee -a /etc/default/u-boot"
    chroot "$CHROOT_TARGET" sh -c "u-boot-update || update-u-boot" && echo u-boot-update fail
}

after_mkrootfs()
{
    # Set up fstab
	BOOT_UUID=$(blkid -o value -s UUID "$LOOP_DEVICE"p1)
	ROOT_UUID=$(blkid -o value -s UUID "$LOOP_DEVICE"p2)
	chroot "$CHROOT_TARGET" sh -c "echo 'UUID=$BOOT_UUID	/boot	ext4	rw,relatime	0 2' >> /etc/fstab"
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
    if [ -d "$KERNEL_FOLDER" ]; then
        rm -rv $KERNEL_FOLDER
    fi
    if [ -d "$UBOOT_FOLDER" ]; then
        rm -rv $UBOOT_FOLDER
    fi
    echo "Done."
}

main()
{
<<<<<<< HEAD
# 	install_depends
	make_imagefile
	pre_mkrootfs
	make_rootfs
	make_kernel
	make_bootable
=======
#   install_depends
    make_imagefile
    pre_mkrootfs
  # use CUSTOM_MIRROR to specify mirror
  # use ROOTFS_TAR = path/to/tar to use exist tarball
    make_rootfs
    make_kernel
    make_bootable
>>>>>>> a9d594e (mkimg.sh: add ROOTFS_TARBALL to use custom rootfs)
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
<<<<<<< HEAD
    chroot "$CHROOT_TARGET" bash
	if [ $? -eq 0 ]; then
		unmount_image
		cleanup_env
		echo "exit."
	else
		unmount_image
		cleanup_env
		if [ -f $IMAGE_FILE ]; then
			echo "delete image $IMAGE_FILE ..."
			rm -v "$IMAGE_FILE"
		fi
		echo "interrupted exit."
	fi
=======
    if ( chroot "$CHROOT_TARGET" bash ) ; then
        unmount_image
        cleanup_env
        echo "exit."
    else
        unmount_image
        cleanup_env
        if [ -f $IMAGE_FILE ]; then
            echo "delete image $IMAGE_FILE ..."
            rm -v "$IMAGE_FILE"
        fi
        echo "interrupted exit."
    fi
>>>>>>> a9d594e (mkimg.sh: add ROOTFS_TARBALL to use custom rootfs)
}

main

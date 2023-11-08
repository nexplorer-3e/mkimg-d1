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
	sgdisk -n 1:2048:+40M -c 1:"EFI" -t 1:ef00 "$IMAGE_FILE"
	ENDSECTOR=$(sgdisk -E "$IMAGE_FILE")
	sgdisk -n 2:0:"$ENDSECTOR" -c 2:"ROOT" -t 2:8300 -A 2:set:2 "$IMAGE_FILE"
	sgdisk -p "$IMAGE_FILE"

    # Get loop device name
    losetup --partscan --find --show "$IMAGE_FILE"
	LOOP_DEVICE=$(losetup -j "$IMAGE_FILE" | grep -o "/dev/loop[0-9]*")

    # Format partitions
	mkfs.vfat -F32 -n efi "$LOOP_DEVICE"p1
	mkfs.ext4 -F -L root "$LOOP_DEVICE"p2
}

pre_mkrootfs()
{
    # Mount loop device
	mkdir "$CHROOT_TARGET"
	mount "$LOOP_DEVICE"p2 "$CHROOT_TARGET"
    mkdir "$CHROOT_TARGET"/boot/efi
    mount "$LOOP_DEVICE"p1 "$CHROOT_TARGET"/boot/efi
}

make_rootfs()
{
    mmdebstrap --architectures=riscv64 \
    --include="ca-certificates debian-ports-archive-keyring locales dosfstools \
        sudo bash-completion network-manager openssh-server systemd-timesyncd" \
    sid "$CHROOT_TARGET" \
    "deb https://mirror.iscas.ac.cn/revyos/revyos-base/ sid main contrib non-free non-free-firmware" \
    "deb https://mirror.iscas.ac.cn/revyos/revyos-addons/ revyos-addons main"

    # Mount chroot path
    # mount "$LOOP_DEVICE"p1 "$CHROOT_TARGET"/boot
    mount -t proc /proc "$CHROOT_TARGET"/proc
    mount -B /sys "$CHROOT_TARGET"/sys
    mount -B /run "$CHROOT_TARGET"/run
    mount -B /dev "$CHROOT_TARGET"/dev
    mount -B /dev/pts "$CHROOT_TARGET"/dev/pts

    # apt update
    chroot "$CHROOT_TARGET" sh -c "apt update"
}

make_kernel()
{
    # Install Kernel
    mkdir $KERNEL_FOLDER
    unzip kernel.tar.gz.zip
    tar xvf kernel.tar.gz -C $KERNEL_FOLDER/
    cp -rv $KERNEL_FOLDER/rootfs/boot/* $CHROOT_TARGET/boot/
    cp -rv $KERNEL_FOLDER/rootfs/lib/* $CHROOT_TARGET/lib/
    rm -v kernel.tar.gz
    rm -r $KERNEL_FOLDER
}

make_bootable()
{
    # Install u-boot and opensbi
    mkdir $UBOOT_FOLDER
    unzip misc.tar.gz.zip
    tar xvf misc.tar.gz -C $UBOOT_FOLDER/
    dd if="${UBOOT_FOLDER}/rootfs/boot/u-boot-sunxi-with-spl.bin" of="${LOOP_DEVICE}" bs=1024 seek=128
    rm -v misc.tar.gz
    rm -r $UBOOT_FOLDER

    chroot "$CHROOT_TARGET" sh -c "apt install -y u-boot-menu"
    chroot "$CHROOT_TARGET" sh -c "echo 'U_BOOT_ROOT="root=/dev/mmcblk0p2"' | tee -a /etc/default/u-boot"
    chroot "$CHROOT_TARGET" sh -c "echo 'U_BOOT_PARAMETERS=\"rw earlycon=sbi console=tty0 console=ttyS0,115200 rootwait \"' | tee -a /etc/default/u-boot"
    # chroot "$CHROOT_TARGET" sh -c "echo 'U_BOOT_FDT_DIR=\"/boot/dtbs/\"' | tee -a /etc/default/u-boot"
    chroot "$CHROOT_TARGET" sh -c "u-boot-update"

    # Install grub
    chroot "$CHROOT_TARGET" sh -c "apt install -y grub2-common grub-efi-riscv64-bin"
}

after_mkrootfs()
{
    # Set up fstab
	EFI_UUID=$(blkid -o value -s UUID "$LOOP_DEVICE"p1)
	ROOT_UUID=$(blkid -o value -s UUID "$LOOP_DEVICE"p2)
	chroot "$CHROOT_TARGET" sh -c "echo 'UUID=$EFI_UUID	/boot/efi	vfat	rw,relatime	0 2' >> /etc/fstab"
	chroot "$CHROOT_TARGET" sh -c "echo 'UUID=$ROOT_UUID	/	ext4	rw,relatime	0 1' >> /etc/fstab"

    # Add user
    chroot "$CHROOT_TARGET" sh -c "useradd -m -s /bin/bash -G adm,sudo debian"
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
    chroot "$CHROOT_TARGET" sh -c "rm -v /etc/ld.so.cache"
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
	else
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
# 	install_depends
	make_imagefile
	pre_mkrootfs
	make_rootfs
	make_kernel
	make_bootable
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
}

main
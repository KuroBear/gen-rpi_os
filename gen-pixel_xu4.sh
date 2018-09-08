#!/bin/sh
#genetate pixel [odroidxu4] image: chmod +x gen-pixel_xu4.sh && sudo ./gen-pixel_xu4.sh
#depends: dosfstools debootstrap

set -eu

die() {
	printf '\033[1;31mERROR:\033[0m %s\n' "$@" >&2  # bold red
	exit 1
}

if [ "$(id -u)" -ne 0 ]; then
	die 'This script must be run as root!'
fi

export DEBIAN_FRONTEND=noninteractive

BUILD_DATE="$(date +%Y-%m-%d)"

usage() {
	cat <<EOF

	Usage: gen-pixel_xu4.sh [options]

	Valid options are:
		-b DEBIAN_BRANCH        Debian branch to install (default is stretch).
		-m DEBIAN_MIRROR        URI of the mirror to fetch packages from
					(default is http://mirrors.tuna.tsinghua.edu.cn/raspbian/raspbian/).
		-o OUTPUT_IMG           Output img file
					(default is BUILD_DATE-pixel-xu4-ARCH-DEBIAN_BRANCH.img).
		-h                      Show this help message and exit.
EOF
}

while getopts 'b:m:o:h' OPTION; do
	case "$OPTION" in
		b) DEBIAN_BRANCH="$OPTARG";;
		m) DEBIAN_MIRROR="$OPTARG";;
		o) OUTPUT_IMG="$OPTARG";;
		h) usage; exit 0;;
	esac
done 

: ${DEBIAN_BRANCH:="stretch"}
: ${DEBIAN_MIRROR:="http://mirrors.tuna.tsinghua.edu.cn/raspbian/raspbian/"}
: ${OUTPUT_IMG:="${BUILD_DATE}-pixel-xu4-${DEBIAN_BRANCH}.img"}

#=======================  F u n c t i o n s  =======================#

gen_image() {
	fallocate -l $(( 3 * 1024 * 1024 *1024 )) "$OUTPUT_IMG"
cat > fdisk.cmd <<-EOF
	o
	n
	p
	1
	
	+128MB
	t
	c
	a
	n
	p
	2
	
	
	w
EOF
fdisk "$OUTPUT_IMG" < fdisk.cmd
rm -f fdisk.cmd
}

do_format() {
	mkfs.vfat -n boot "$BOOT_DEV"
	mkfs.ext4 "$ROOT_DEV"
	mkdir -p mnt
	mount "$ROOT_DEV" mnt
	mkdir -p mnt/media/boot
	mount "$BOOT_DEV" mnt/media/boot
}

do_debootstrap() {
	debootstrap --no-check-gpg --arch="armhf" "$DEBIAN_BRANCH" mnt "$DEBIAN_MIRROR"
}

gen_wpa_supplicant_conf() {
	cat <<EOF
country=CN
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
EOF
}

gen_keyboard_layout() {
	cat <<EOF
# KEYBOARD CONFIGURATION FILE

# Consult the keyboard(5) manual page.

XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""

BACKSPACE="guess"
EOF
}

gen_fstabs() {
	echo "PARTUUID=${BOOT_PARTUUID}  /media/boot           vfat    defaults          0       2
PARTUUID=${ROOT_PARTUUID}  /               ext4    defaults,noatime  0       1"
}

add_user_groups() {
	for USER_GROUP in input spi i2c gpio; do
		groupadd -f -r $USER_GROUP
	done
	for USER_GROUP in adm dialout cdrom audio users sudo video games plugdev input gpio spi i2c netdev; do
		adduser odroid $USER_GROUP
	done
}

add_mirrors() {
	apt-get install -y dirmngr
	echo "deb http://mirrors.tuna.tsinghua.edu.cn/raspbian/raspbian/ ${DEBIAN_BRANCH} main contrib non-free rpi" > /etc/apt/sources.list
	echo "deb http://mirrors.tuna.tsinghua.edu.cn/raspberrypi/ ${DEBIAN_BRANCH} main ui" > /etc/apt/sources.list.d/raspi.list
	echo "deb http://deb.odroid.in/5422-s bionic main" > /etc/apt/sources.list.d/odroid.list
	apt-key adv --keyserver keyserver.ubuntu.com --recv 9165938D90FDDD2E
	apt-key adv --keyserver keyserver.ubuntu.com --recv 82B129927FA3303E
	apt-key adv --keyserver keyserver.ubuntu.com --recv  2DD567ECD986B59D
	apt-get update && apt-get upgrade -y
}

gen_resizeonce_scripts() {
	cat > /etc/rc.local <<'EOF'
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.


if [ -f /resize2fs_once ]; then /resize2fs_once ; fi

exit 0
EOF

chmod +x /etc/rc.local

	cat > /resize2fs_once <<'EOF'
#!/bin/sh 
set -x
ROOT_DEV=$(findmnt / -o source -n)
cat > /tmp/fdisk.cmd <<-EOF
	d
	2
	
	n
	p
	2
	
	
	w
	EOF
fdisk "$(echo "$ROOT_DEV" | sed -E 's/p?2$//')" < /tmp/fdisk.cmd
rm -f /tmp/fdisk.cmd
partprobe
resize2fs "$ROOT_DEV"
mv /resize2fs_once /usr/local/bin/resize2fs_once
EOF

chmod +x /resize2fs_once

}

install_browser() {
	wget https://downloads.vivaldi.com/stable/vivaldi-stable_1.15.1147.64-2_armhf.deb
	dpkg -i *.deb || true
	apt-get install -f -y
	rm -f *.deb
}

install_kernel() {
	apt-get install -y linux-odroid-5422
}

install_driver() {
	apt-get install -y xserver-xorg-video-armsoc mali-x11 odroid-platform-5422
}

get_uboot() {
	local url="https://github.com/hardkernel/u-boot/raw/odroidxu4-v2017.05/sd_fuse"

	for files in bl1.bin.hardkernel bl2.bin.hardkernel.720k_uboot sd_fusing.sh tzsw.bin.hardkernel u-boot.bin.hardkernel ; do
		wget -P /tmp $url/$files
	done

	cd /tmp
	chmod +x sd_fusing.sh
	./sd_fusing.sh ${LOOP_DEV}

}

get_bootini() {
	wget http://deb.odroid.in/5422-s/pool/main/b/bootini/bootini_20180417-2_armhf.deb
	dpkg -x *.deb /tmp
	mv /tmp/usr/share/bootini/boot.ini* /media/boot/
	sed -i '85s/^#//' /media/boot/boot.ini
	sed -i "s|root=UUID=e139ce78-9841-40fe-8823-96a304a09859|root=PARTUUID=${ROOT_PARTUUID}|" /media/boot/boot.ini
	rm -f *.deb
}

install_bootloader() {
	get_uboot
	get_bootini
}

gen_env() {
	echo "LOOP_DEV=${LOOP_DEV}
	export DEBIAN_FRONTEND=noninteractive
	DEBIAN_BRANCH=${DEBIAN_BRANCH}
	ROOT_PARTUUID=${ROOT_PARTUUID}"
}

setup_chroot() {
	chroot mnt /bin/bash <<-EOF
		set -xe
		source /root/env_file
		source /root/functions
		rm -f /root/env_file /root/functions
		ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
		apt-get update && apt-get install -y locales
		echo "en_US.UTF-8 UTF-8" | tee --append /etc/locale.gen
		locale-gen
		echo odroid > /etc/hostname
		echo "127.0.1.1    odroid.localdomain    odroid" | tee --append /etc/hosts
		add_mirrors
		apt-get install -y ssh
		apt-get install -y dhcpcd5 wpasupplicant net-tools wireless-tools firmware-atheros firmware-brcm80211 firmware-libertas firmware-misc-nonfree firmware-realtek raspberrypi-net-mods
		apt-get install -y raspberrypi-ui-mods accountsservice lxsession lxterminal htop screen geany fcitx-pinyin fonts-wqy-zenhei fonts-droid-fallback
		mv /etc/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf
		sed -i '7s|^.*$|  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/games:/usr/games"|' /etc/profile
		useradd -g sudo -ms /bin/bash odroid
		add_user_groups
		systemctl set-default graphical.target
		sed -i 's/pi/odroid/' /etc/systemd/system/autologin@.service
		ln -fs /etc/systemd/system/autologin@.service /etc/systemd/system/getty.target.wants/getty@tty1.service
		sed /etc/lightdm/lightdm.conf -i -e "s/^\(#\|\)autologin-user=.*/autologin-user=odroid/"
		systemctl enable dhcpcd.service
		echo "odroid:odroid" | chpasswd
		echo "odroid ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
		sed -i 's/#force_color_prompt=yes/force_color_prompt=yes/g' /home/odroid/.bashrc
		gen_resizeonce_scripts
		install_browser
		install_driver
		install_kernel
		install_bootloader
		rm -rf /var/lib/apt/lists/* /tmp/*
		EOF
}

mounts() {
	mount -t proc /proc mnt/proc
	mount -t sysfs /sys mnt/sys
	mount -o bind /dev mnt/dev
}

umounts() {
	umount mnt/dev
	umount mnt/sys
	umount mnt/proc
	umount mnt/media/boot
	umount mnt
	losetup -d "$LOOP_DEV"
}

#=======================  F u n c t i o n s  =======================#

pass_function() {
	sed -nE '/^#===.*F u n c t i o n s.*===#/,/^#===.*F u n c t i o n s.*===#/p' "$0"
}

gen_image

LOOP_DEV=$(losetup --partscan --show --find "${OUTPUT_IMG}")
BOOT_DEV="$LOOP_DEV"p1
ROOT_DEV="$LOOP_DEV"p2

do_format

do_debootstrap

gen_wpa_supplicant_conf > mnt/etc/wpa_supplicant.conf

gen_keyboard_layout > mnt/etc/default/keyboard

IMGID="$(dd if="${OUTPUT_IMG}" skip=440 bs=1 count=4 2>/dev/null | xxd -e | cut -f 2 -d' ')"

BOOT_PARTUUID="${IMGID}-01"
ROOT_PARTUUID="${IMGID}-02"

gen_fstabs > mnt/etc/fstab

gen_env > mnt/root/env_file

pass_function > mnt/root/functions

mounts

setup_chroot

umounts

cat >&2 <<-EOF
	---
	Installation is complete
	Flash to usb disk with: dd if=${OUTPUT_IMG} of=/dev/TARGET_DEV bs=4M status=progress
	
EOF

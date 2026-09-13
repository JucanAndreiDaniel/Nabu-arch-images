#!/usr/bin/env bash
# Flash Arch (davinci, Samsung panel):
#   prebuilt U-Boot -> boot,
#   nested GPT image (FAT ESP + ext4 root) -> userdata.
# U-Boot's preboot blkmaps the userdata hosting partition and boots the
# nested ESP; the initramfs expose the nested root via offset loop
# (davinci_nested hook, root=UUID=).
# Requires: unlocked bootloader, fastboot mode, dtbo backup already taken.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BOOT_IMG="$DIR/images/boot-davinci-samsung.img"
ROOTFS_IMG="$DIR/images/userdata-nested.img"

fastboot "$@" getvar product 2>&1 | grep -q 'product: *davinci' || { echo "Mismatching image and device (expected davinci)"; exit 1; }
fastboot "$@" getvar partition-size:boot 2>&1 | grep -q "partition-size:boot:" || { echo "boot partition not found"; exit 1; }
fastboot "$@" getvar partition-size:userdata 2>&1 | grep -q "partition-size:userdata:" || { echo "userdata partition not found"; exit 1; }
fastboot "$@" getvar partition-size:dtbo 2>&1 | grep -q "partition-size:dtbo:" || { echo "dtbo partition not found"; exit 1; }

[ -f "$BOOT_IMG" ] || { echo "Missing $BOOT_IMG (run davinci/scripts/fetch-uboot.sh or CI build)"; exit 1; }
[ -f "$ROOTFS_IMG" ] || { echo "Missing $ROOTFS_IMG"; exit 1; }

echo "This will ERASE dtbo and flash boot + userdata. Back up first!"
read -r -p "Type YES to continue: " confirm
[ "$confirm" = "YES" ] || { echo "Aborted"; exit 1; }

fastboot "$@" erase dtbo || { echo "Erase dtbo error"; exit 1; }
fastboot "$@" flash boot "$BOOT_IMG" || { echo "Flash boot (U-Boot) error"; exit 1; }
fastboot "$@" flash userdata "$ROOTFS_IMG" || { echo "Flash nested image error"; exit 1; }
fastboot "$@" reboot || { echo "Reboot error"; exit 1; }

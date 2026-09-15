# Arch Linux ARM for Xiaomi Mi 9T / Redmi K20 (davinci, SM7150)

Samsung-panel only for v1. Single-boot. U-Boot + systemd-boot.

## Sources (pinned)

- Kernel: `https://github.com/sm7150-mainline/linux`, tag `v7.1_rc3`
  (exact code pmOS boots as `linux-postmarketos-qcom-sm7150` 7.1_rc3;
  config = pmOS working `/boot/config` verbatim, see
  `packaging/linux-davinci/config-pmos-7.1_rc3`. v7.2-tip was tried and
  hangs after the EFI stub; revisit newer trees only after first boot)
  - DTB: `arch/arm64/boot/dts/qcom/sm7150-xiaomi-davinci-samsung.dts`
    (`compatible = "xiaomi,davinci-samsung"`, panel `samsung,ams639rq08`)
- U-Boot (prebuilt, do not build for v1):
  - `https://github.com/sm7150-mainline/u-boot/releases/tag/2025-12-02`
  - Asset: `u-boot-sm7150-xiaomi-davinci-samsung.img`
  - Commit `f8c04469e8284aa2f1691a30aa3b7dc59fa0b8cd` (`tauchgang`)
  - sha256: `a18bf172a03dd8532da85775600c36813cd0128552ca83ac58000f5c787ecd36`
- Packaging reference (pmOS, `generic` branch):
  - `sm7150-mainline/pmaports:device/community/device-qcom-sm7150/`
    (`fastboot-bootpart`, `generate_systemd_boot=true`)
  - `sm7150-mainline/pmaports:device/community/device-xiaomi-davinci/`
    (metadata/offsets only: pagesize 4096, header v1)
- Firmware: `sm7150-mainline/firmware-xiaomi-davinci`
  (`/lib/firmware/qcom/sm7150/xiaomi/davinci/*`), plus
  `firmware-qcom-sm7150-ath10k`, `linux-firmware-qca/ath10k/qcom`, `alsa-ucm-conf` fork.

## Boot architecture

- `boot` partition: prebuilt Samsung U-Boot image (Android `boot.img` wrapping U-Boot).
  U-Boot runs `bootefi bootmgr` and scans for systemd-boot.
- `userdata` partition: **nested GPT disk image** (`userdata-nested.img`, 4096-byte
  sectors) containing:
  - p1: FAT32 ESP with systemd-boot (`EFI/BOOT/bootaa64.efi`), loader config and
    the UKI (`EFI/Linux/arch-linux-davinci.efi`)
  - p2: ext4 Arch rootfs
- Why nested: U-Boot's `preboot` (`board/qualcomm/qcom-phone.env`) blkmaps the
  *hosting* partition (`part start scsi 0 userdata ...; blkmap create root ...`)
  and the boot manager boots from a nested ESP inside it. A raw ext4 image has
  no nested GPT/ESP, which is exactly the "Failed to iterate over directory EFI"
  failure. Same approach as postmarketOS sdm845/sm7150 and the Mobian sunfish port.
- Root discovery: the `davinci_nested` mkinitcpio hook exposes the nested
  GPT via `losetup --sector-size 4096 -P` (`loopXp1` ESP, `loopXp2` root)
  and mounts `root=PARTLABEL=ARCH`. Real partition devices give udev
  native by-partlabel symlinks without blkid probing (plain offset loops
  never got device units in the real root, stalling systemd on the root
  device). fstab uses PARTLABEL too: no UUID placeholders anywhere.
  Hosting partition lookup tries partlabel `linux` first, falling back to
  `userdata`.
- No EDK2, no rEFInd, no `linux`/`esp` custom partitions, no dual-boot for v1.
  The nabu `DBKP/`, `efi-template/`, TWRP repartition flow does not apply.

## Pre-install (destructive, backup first)

```bash
# unlocked bootloader, fastboot mode required
fastboot getvar product   # expect: davinci
fastboot getvar partition-size:boot
fastboot getvar partition-size:userdata
fastboot getvar partition-size:dtbo

# backups (keep these safe)
fastboot boot twrp.img    # then dd boot/dtbo, or use existing backup flow
```

Disable downstream DT overlay (required; same as
`LineageOS/android_device_xiaomi_mi7150-mainline` and pmOS Xiaomi ports):

```bash
fastboot erase dtbo
```

If the bootloader rejects the U-Boot image (AVB), additionally:

```bash
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
```

Only do the `vbmeta` step if boot fails; do not erase `vbmeta` blindly.

## Flash (v1 artifacts)

CI produces:

- `images/boot-davinci-samsung.img` — verified prebuilt U-Boot copy
- `images/userdata-nested.img` — nested GPT image (FAT ESP + ext4 rootfs with
  systemd-boot + UKI); sparse Android format when `img2simg` is available,
  raw otherwise (fastboot accepts both)

```bash
./flash-davinci-samsung.sh
# equivalent manual steps:
fastboot erase dtbo
fastboot flash boot images/boot-davinci-samsung.img
fastboot flash userdata images/userdata-nested.img
fastboot reboot
```

Default credentials: `user` / `123456` (same as nabu images).

## Plasma smoke-test GUI

The image ships Plasma Desktop (same package set as the nabu Plasma
image: `plasma-desktop`, sddm on Wayland, konsole/dolphin/gwenview,
pipewire, `plasma-keyboard` on-screen keyboard, `vulkan-freedreno`) with
sddm autologin as `user` — no password typing needed. The nabu display
geometry files (`kwinoutputconfig.json`, 1600x2560 rotated) are excluded
so KWin auto-configures the 1080x2340 panel. Touch comes via libinput
(Goodix GTX8 multitouch). Gettys stay enabled as fallback; if sddm ever
fails, multi-user login still works.

## SSH over USB

Every boot assembles an NCM network gadget (`davinci-net-usb`, pmOS
layout — VID `18D1`/`D001`, RNDIS fallback) plus a NetworkManager
`shared` profile. The phone is `172.16.42.1`; plug USB and `ssh
user@172.16.42.1` — the host gets its address over DHCP automatically,
no manual IP needed. No serial involved: no tty, no `ttyGS0`, nothing
that can stall boot (USB serial was retired after both architectures
failed; G_SERIAL is off and no cmdline carries `console=ttyGS0`).

## Iterating without reflashing (UMS)

Full `userdata` flashes are gigabytes; most bring-up iterations only touch
boot/root files. U-Boot's menu has `Enable USB mass storage` (`ums 0 scsi
0`): hold Volume Down at boot, pick it, and the UFS appears on the host.
The nested ESP/root then mount straight off the phone (offsets in bytes;
`/dev/sdX` is the ~58 GiB disk, check with `lsblk` first):

```bash
U=$(sudo parted /dev/sdX unit B print | awk '/userdata/{print $2}' | tr -d 'B')
sudo mkdir -p /mnt/esp /mnt/root
sudo mount -o loop,offset=$((U+1048576)),sizelimit=536870912 /dev/sdX /mnt/esp
sudo mount -o loop,offset=$((U+537919488)) /dev/sdX /mnt/root
# edit UKIs, loader entries, cmdline fragments, services... then:
sudo umount /mnt/esp /mnt/root
```

Exit UMS mode (any key on the phone) and reboot to test. Full reflash is
only needed for kernel-package or base-rootfs changes. Keep one known-good
`userdata-nested.img` around as the recovery fallback.

## Boot status (boots to Plasma)

The image boots to SDDM autologin (`user`) on the 1080x2340 panel, with
`getty@tty1` as fallback. Access: panel, USB-NCM/WiFi SSH
(`user`/`123456`), or UMS-mount forensics pulls. Root is on
`PARTLABEL=ARCH`, `/boot` mounted, modem DSP firmware loading.

Two boot entries are installed (plus a `previous UKI` fallback):

- `Arch Linux (davinci, Samsung)` — `arch-linux-davinci.efi`
  (verbose bring-up cmdline: `root=PARTLABEL=ARCH + console=tty0`,
  no `quiet` until first successful boot)
- `Arch Linux (davinci, Samsung, debug)` — `arch-linux-davinci-debug.efi`
  (adds `loglevel=7 ignore_loglevel earlycon keep_bootcon efi=debug
  drm.debug=0x1e initcall_debug davinci_debug`)

(Retired: `debug-nokaslr` / `debug-novamap` combos and the USB-serial
experiments — early-hang hypotheses ruled out, both serial
architectures failed. The `nokaslr`/`novamap` UKIs, loader confs and
cmdline fragments are gone; `overlay-post-apply` deletes their leftovers
from existing images.)

`davinci_debug` makes the `davinci_nested` initramfs hook trace hosting
partition lookup + partitioned-loop setup (`ls`, `blkid`) to serial/fbcon/pstore.

Observability ladder (cheapest first):

1. **USB network**: after boot, an NCM gadget enumerates on the host
   (`dmesg -w`, new CDC Ethernet device) and `ssh user@172.16.42.1`
   works — that alone proves kernel + initramfs + root + userspace are
   up. Nothing enumerates = hang before USB init or no UDC.
2. **Screen**: the debug entry prints `ignore_loglevel` + `drm.debug` to
   fbcon (`console=tty0`). Text on screen = kernel alive, display handoff
   works; black = panic before fbcon or MSM tearing down simplefb.
2. **U-Boot menu**: hold Volume Down while U-Boot loads for UMS/fastboot
   access without a working system.
3. **UMS forensics**: U-Boot `Enable USB mass storage` exposes the UFS;
   mount the nested root and read `/var/log/davinci-forensics.log` or
   `journalctl --directory=<mnt>/var/log/journal -b 0 -e`.
4. **ramoops**: DTS reserves `ramoops@9d800000` and the kernel has
   `PSTORE_CONSOLE+PSTORE_RAM`; after a *warm* reboot into a working system
   (e.g. pmOS, without cutting power) read `/sys/fs/pstore/console-ramoops-0`
   for the previous boot's last dmesg.
5. **UART**: needs test-point access, last resort (no `console=ttyMSM0`
   on any cmdline).

pmOS cross-check (known-good reference): pmOS boots the same U-Boot with a
Type 1 entry of **split files, no UKI** — `linux vmlinuz` (zstd zboot
Image) + `initrd initramfs` + `devicetree sm7150-xiaomi-davinci-samsung.dtb`
+ `options ... console=tty0 console=ttyGS0,115200 ...` — from its boot
partition, and its 7.1.0-sm7150 `/boot/config`
(`linux-postmarketos-qcom-sm7150` 7.1_rc3) drives display natively via
MSM/KMS: `FB_SIMPLE`/`FB_EFI`/`LOGO` unset, `SYSFB_SIMPLEFB`/`SIMPLEDRM`
unset, panel (`AMS639RQ08`), touch (`GTX8`), backlight (`QCOM_WLED`)
**builtin**, composite gadget function stack builtin (`CONFIGFS` core
`=m`) with `G_SERIAL` off — nothing binds the UDC except the NCM
network gadget at runtime. This tree now matches that model exactly. The kernel `prepare()` asserts the effective
`.config` for all of these and fails the build on mismatch (see CI log
`davinci effective-config check`).

Note: mkinitcpio presets bake **one** cmdline file per UKI, not the
`/etc/cmdline.d` directory — `usr/libexec/davinci/combine-cmdline`
concatenates the fragments. Re-run it after any fragment edit, then
`mkinitcpio -P` (or `/usr/libexec/davinci/uki-regenerate`).

## Verifying a built image without flashing

The ESP lives inside `userdata-nested.img` (p1 at byte offset 1048576).
Mount it and inspect what the stub will actually boot:

```bash
mkdir -p esp && sudo mount -o loop,offset=1048576 userdata-nested.img esp
ls -l esp/EFI/Linux/ esp/loader/entries/
# baked cmdline of an entry:
objcopy -O binary --only-section=.cmdline \
  esp/EFI/Linux/arch-linux-davinci-debug.efi /tmp/cmdline.bin
tr '\0' '\n' < /tmp/cmdline.bin
# DTB identity (must be the Samsung DTB with earlycon bootargs):
objcopy -O binary --only-section=.dtb \
  esp/EFI/Linux/arch-linux-davinci-debug.efi /tmp/uki.dtb
fdtdump /tmp/uki.dtb | grep -E 'model|compatible|bootargs|stdout-path'
sudo umount esp
```

## Visionox panel

Not supported in v1. Needs `u-boot-sm7150-xiaomi-davinci-visionox.img` plus
`sm7150-xiaomi-davinci-visionox.dts` (`visionox,g1639fp106`) kernel/UKI.
The build script refuses to mix panel variants.

## Layout in this repo

- `uboot.env` — pinned U-Boot tag/asset/sha256
- `scripts/fetch-uboot.sh` — download + sha256-verify prebuilt U-Boot
- `base/overlay/` — davinci rootfs overlay (fstab, cmdline, preset, uki.conf,
  pacman hook, `uki-regenerate`, systemd-boot loader config)
- `packaging/linux-davinci/PKGBUILD` — fork-kernel package scaffolding
- `packaging/linux-firmware-xiaomi-davinci/PKGBUILD` — firmware scaffolding
- `packaging/hexagonrpcd/PKGBUILD` — glibc FastRPC/SSC daemon (sensors); no
  Arch package exists, built by the `build-davinci-pkgs` job like the kernel
- `flash-davinci-samsung.sh/.bat` — fastboot flash scripts
- `deviceinfo` — pmOS-derived fields for documentation

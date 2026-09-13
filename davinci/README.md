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
  partitions via plain offset loops (ESP at byte 1048576, root at byte 537919488;
  no `-P`: partition scanning on the loop panics) and mounts `root=UUID=`
  (baked into the UKI cmdline at build time). Hosting partition lookup tries
  partlabel `linux` first, falling back to `userdata`.
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

## Black-screen bring-up (debug)

Observed so far: the UKI's EFI stub runs to `Exiting boot services...`
(initrd + DTB load fine), then zero kernel output — not even DT-bootargs
`earlycon` — and the PMIC watchdog resets the board after a few seconds.
That places the hang between `ExitBootServices` and `console_init`, before
any driver (including display) is up: KASLR placement and the arm64 EFI
runtime mapping are the prime suspects, not root mount or the panel driver.

Four boot entries are installed (one variable per experiment):

- `Arch Linux (davinci, Samsung)` — `arch-linux-davinci.efi`
  (verbose bring-up cmdline: `root=UUID=… + console=ttyMSM0 + console=tty0`,
  no `quiet` until first successful boot)
- `Arch Linux (davinci, Samsung, debug)` — `arch-linux-davinci-debug.efi`
  (adds `loglevel=7 ignore_loglevel earlycon keep_bootcon efi=debug
  drm.debug=0x1e initcall_debug davinci_debug`)
- `... debug nokaslr` — debug combo + `nokaslr` (rules out KASLR
  placement crashes before `console_init`)
- `... debug novamap` — debug combo + `efi=novamap` (rules out a fault in
  the arm64 EFI runtime mapping, also before `console_init`)

`davinci_debug` makes the `davinci_nested` initramfs hook trace hosting
partition lookup + offset-loop setup (`ls`, `blkid`) to serial/fbcon/pstore.

Observability ladder (cheapest first):

1. **USB gadget alive-signal**: every boot raises a CDC-ACM gadget from the
   initramfs (`davinci_gadget` hook) and `console=ttyGS0` streams kernel
   logs to it. On the host, watch `dmesg -w` / `ls /dev/ttyACM*` after
   picking an entry. ACM device appears = kernel + initramfs alive (black
   screen is then dead display/serial or rootwait, not a hang); attach with
   `tio /dev/ttyACM0` (or `picocom`) to read the log backlog + follow.
   Nothing enumerates = hang before initramfs (or before UDC probe).
2. **Screen**: the debug entry prints `ignore_loglevel` + `drm.debug` to
   fbcon (`console=tty0`). Text on screen = kernel alive, display handoff
   works; black = panic before fbcon or MSM tearing down simplefb.
2. **U-Boot menu**: hold Volume Down while U-Boot loads, or pick `Enable
   serial console gadget` (`serial_gadget` in `qcom-phone.env`) for a
   `usbacm` serial console on the host.
3. **USB enumeration**: after picking an entry, `lsusb` on the host. A new
   gadget/serial device = kernel past USB init; nothing at all = very early
   hang (DTB/clock/power, not root mount).
4. **ramoops**: DTS reserves `ramoops@9d800000` and the kernel has
   `PSTORE_CONSOLE+PSTORE_RAM`; after a *warm* reboot into a working system
   (e.g. pmOS, without cutting power) read `/sys/fs/pstore/console-ramoops-0`
   for the previous boot's last dmesg.
5. **UART**: `console=ttyMSM0,115200n8` is baked in (also in DT
   `chosen.bootargs`); needs test-point access, last resort.

pmOS cross-check (known-good reference): pmOS boots the same U-Boot with a
Type 1 entry of **split files, no UKI** — `linux vmlinuz` (zstd zboot
Image) + `initrd initramfs` + `devicetree sm7150-xiaomi-davinci-samsung.dtb`
+ `options ... console=tty0 console=ttyGS0,115200 ...` — from its boot
partition, and its 7.1.0-sm7150 `/boot/config`
(`linux-postmarketos-qcom-sm7150` 7.1_rc3) drives display natively via
MSM/KMS: `FB_SIMPLE`/`FB_EFI`/`LOGO` unset, `SYSFB_SIMPLEFB`/`SIMPLEDRM`
unset, panel (`AMS639RQ08`), touch (`GTX8`), backlight (`QCOM_WLED`)
**builtin**, gadget stack builtin with `CONFIGFS` core `=m`. This tree now
matches that model exactly. The kernel `prepare()` asserts the effective
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
- `flash-davinci-samsung.sh/.bat` — fastboot flash scripts
- `deviceinfo` — pmOS-derived fields for documentation

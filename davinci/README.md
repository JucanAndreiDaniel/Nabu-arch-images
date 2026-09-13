# Arch Linux ARM for Xiaomi Mi 9T / Redmi K20 (davinci, SM7150)

Samsung-panel only for v1. Single-boot. U-Boot + systemd-boot.

## Sources (pinned)

- Kernel: `https://github.com/sm7150-mainline/linux`, branch `v7.2`
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

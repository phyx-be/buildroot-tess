# Tess: ESP32-C3 WiFi/BLE and image layout plan

Status (2026-10-07): the flasher image flashes the ESP32-C3 and writes
the main image to the SD NAND, and the main image boots from the SD
NAND. WiFi over esp-hosted works (WPA2, DHCP, internet, 9 Mbit/s) and
BLE over UART2 works (btattach, bluetoothctl LE scan). See section 6.

Goals:

- WiFi through the ESP32-C3 using esp-hosted
  (https://github.com/espressif/esp-hosted-linux), with SPI0 as the WiFi
  transport, a Linux kernel module and a device tree node.
- BLE through the ESP32-C3 using HCI over UART (UART2).
- Two images, each with its own defconfig:
  - a **flasher image**, booted over USB (FEL), that writes the main image
    to the soldered SD NAND on SDC0 and does the initial flash of the
    ESP32-C3 over UART4 with espflash;
  - a **main image**, booting from SDC0 with its root filesystem on SDC0
    (no initramfs), that updates the ESP32-C3 firmware over SPI.

## 1. Hardware

From the schematic (TESS_00.PDF, sheets 2 and 3):

| Function                  | T113-S3               | ESP32-C3                          | Notes                                |
|---------------------------|-----------------------|-----------------------------------|--------------------------------------|
| SPI0 CLK / MOSI / MISO / CS | PC2 / PC4 / PC5 / PC3 | GPIO6 / GPIO7 / GPIO2 / GPIO10  | esp-hosted C3 defaults               |
| SPI handshake             | PC6                   | GPIO3                             | esp-hosted C3 default                |
| SPI data ready            | PD22                  | GPIO4                             | esp-hosted C3 default                |
| UART2 TX / RX             | PE2 / PE3             | GPIO18 (RX) / GPIO5 (TX)          | BLE HCI, firmware default pins       |
| UART2 RTS / CTS           | PE0 / PE1             | GPIO8 (CTS) / GPIO19 (RTS)        | BLE HCI flow control                 |
| UART4 TX / RX (UART_PROG) | PE4 / PE5             | GPIO20 (U0RXD) / GPIO21 (U0TXD)   | ROM bootloader, espflash             |
| ESP.BOOT                  | PE10                  | GPIO9                             | low at reset = download mode         |
| WiFi.EN                   | PE11                  | EN                                | 100K pull-down: ESP off until driven |

Notes:

- The board follows the esp-hosted default ESP32-C3 pinout for both SPI
  and HCI UART, so the firmware needs no pin changes.
- ESP32-C3 GPIO8 and GPIO2 are strapping pins and must be high when the
  ESP leaves reset into download mode. GPIO2 has a pull-up (shared with
  T113 BOOT_SEL1). GPIO8 has a 4K7 pull-up but is also driven by the T113
  UART2 RTS output: UART2 must not be held open (btattach) while the ESP
  is put in download mode.
- GPIO18/GPIO19 are the C3 USB-Serial-JTAG pins; the firmware must not
  enable the USB-Serial-JTAG console. Its log console stays on UART0
  (GPIO20/21), which is UART4 on the T113.
- PC2-PC5 are also the T113 SPI boot pins. The ESP is held in reset by
  the EN pull-down while the T113 boot ROM probes SPI0.
- **UART baud rates:** the T113 UARTs run from a 24 MHz clock (base baud
  1500000), so only 1500000 / n is exact: 1500000, 750000, 500000, ...
  (115200 is 0.16 % off). 460800 and 921600 are 8.5 % and 19 % off and
  do not work. Hence 1500000 for flashing and 500000 for BLE HCI.

Verified on the board (FEL image, 2026-10-07): the `wifi@0` node makes
udev load `esp32_spi`, which probes in SPI mode 2 and toggles WiFi.EN;
the ESP32-C3 ROM log is received on ttyS4 (`SPI_FAST_FLASH_BOOT`, blank
flash).

## 2. esp-hosted findings

- `espressif/esp-hosted-linux` is the successor of `esp_hosted_ng` from
  `espressif/esp-hosted` (split on 2026-08-03, history kept).
  - Host driver: `host/`, GPL-2.0, built with `target=spi` into
    `esp32_spi.ko`.
  - Firmware: `esp/esp_driver/network_adapter/`, Apache-2.0, ESP-IDF v6.1
    (commit pinned in `esp/esp_driver/.env`, plus patches and WiFi
    libraries applied by `esp/esp_driver/setup.sh`).
- Device tree support (`compatible = "espressif,esp32-spi"`,
  `reset-gpios`, `handshake-gpios`, `data-ready-gpios`,
  `spi-max-frequency`, `spi-cpol`) exists **only on master**, not in the
  `release/ng-1.0.6` tag. Pinned master commit: `599c47c` (2026-10-07).
- Host driver and firmware versions must match exactly: the driver
  compares version strings and refuses a mismatch. Both are built from
  the same commit and report `NG-1.0.6.0.14`.
- The driver builds without warnings for ARM32 against 6.18.8.
- The driver pulses `reset-gpios` at probe (500 ms boot wait) and owns
  that GPIO while bound.
- Bluetooth: with `CONFIG_BT_CTRL_HCI_MODE_UART_H4=y` the firmware
  exposes HCI on UART1 (TX=GPIO5, RX=GPIO18, RTS=GPIO19, CTS=GPIO8) at
  `CONFIG_EXAMPLE_HCI_UART_BAUDRATE` (Tess: 500000), RTS/CTS always on.
  The host driver registers no HCI device in that mode; attach with
  `btattach -B /dev/ttyS2 -P h4 -S 500000`.
- The HCI UART code did not build with ESP-IDF v6.1 (GDMA API change):
  fixed by `esp32c3/patches/0001-*.patch`, to be sent upstream.
- No prebuilt firmware binaries in the repo or the releases.
- The driver supports in-band firmware update over the transport with
  the `ota_file=` module parameter (`docs/guides/ota.md`). This is the
  update path for the main image.

## 3. Common parts (both images)

### 3.1 Kernel module package (done)

- `package/esp-hosted` points to `esp-hosted-linux` at the pinned
  commit: `ESP_HOSTED_MODULE_SUBDIRS = host`, `target=spi`, license file
  `host/LICENSE`. The Linux 7.1 build fix patch was dropped (already in
  master). Kept upstreamable for Buildroot.
- Dropped `board/phyxbe/tess/patches/esp-hosted/0001-dt-fixes.patch`; the
  `esp-hosted-sergey` override in the (untracked) `local.mk` is
  commented out.
- Kernel config: `bluetooth.frag` (`CONFIG_BT`, `CONFIG_BT_HCIUART`,
  `CONFIG_BT_HCIUART_H4`). `CONFIG_BT` must be in the fragment itself,
  `sunxi_defconfig` has it disabled. `CONFIG_CFG80211` is already on.

### 3.2 Device tree (done)

```dts
aliases {
	serial2 = &uart2;	/* ttyS2: ESP32-C3 BLE HCI */
	serial3 = &uart3;	/* ttyS3: console */
	serial4 = &uart4;	/* ttyS4: ESP32-C3 programming */
	serial5 = &uart5;	/* ttyS5: feather */
};

&spi0 {
	wifi@0 {
		compatible = "espressif,esp32-spi";
		reg = <0>;
		spi-max-frequency = <30000000>;
		spi-cpol;					/* SPI mode 2 */
		reset-gpios = <&pio 4 11 GPIO_ACTIVE_LOW>;	/* PE11 WiFi.EN */
		handshake-gpios = <&pio 2 6 GPIO_ACTIVE_HIGH>;	/* PC6 */
		data-ready-gpios = <&pio 3 22 GPIO_ACTIVE_HIGH>; /* PD22 */
	};
};

&uart2 {
	uart-has-rtscts;
};
```

- The unused `gpio_out_pe_pins` group is dropped. PE10 (BOOT) is a plain
  GPIO for user space (libgpiod, line offset 4 * 32 + 10 = 138, PE11 is
  139).

### 3.3 ESP32-C3 firmware (done)

- Built outside Buildroot (ESP-IDF downloads several GB of toolchains,
  which does not fit the Buildroot model): `esp32c3/build.sh` builds in
  the `espressif/idf` Docker image, with
  - the esp-hosted-linux commit read from `package/esp-hosted/esp-hosted.mk`,
  - ESP-IDF at the pinned commit with the `setup.sh` patches and WiFi
    libraries (checkout kept in `~/.cache/tess-esp32c3`),
  - `esp32c3/patches/*.patch` applied to esp-hosted-linux,
  - `esp32c3/sdkconfig.defaults.tess`: SPI transport,
    `CONFIG_BT_CTRL_HCI_MODE_UART_H4=y`, HCI at 500000 baud, console on
    UART0 only, USB-Serial-JTAG disabled.
- Output, committed in `rootfs_overlay_flasher/lib/firmware/esp-hosted/`:
  `tess-esp32c3.bin` (all images merged, written at 0x0, used by
  espflash), the separate `bootloader.bin` (0x0), `partition-table.bin`
  (0x8000), `ota_data_initial.bin` (0xd000), `network_adapter.bin`
  (0x10000), `flash_args`, `VERSION` and `SHA256SUMS`. Two OTA
  partitions on 4 MB flash.

### 3.4 U-Boot update (to do)

Both defconfigs still use U-Boot 2024.01-rc4, a release candidate, with
`board/phyxbe/tess/uboot/tess_defconfig` and its own device tree
`board/phyxbe/tess/uboot/sun8i-t113s-tess.dts`.

- Version: 2026.01, the same as `mangopi_mq1rdw2_defconfig` (like the
  kernel).
- `tess_defconfig` is the upstream `mangopi_mq_r_defconfig` with only
  `CONFIG_DEFAULT_DEVICE_TREE` changed. Replace it with
  `BR2_TARGET_UBOOT_BOARD_DEFCONFIG="mangopi_mq_r"` plus a fragment
  (`BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES`) holding the Tess changes, so
  future bumps pick up upstream defconfig changes.
- Enable device tree overlay support (`CONFIG_OF_LIBFDT_OVERLAY`) in that
  fragment, for the DSI display overlay (see the TODOs).
- Add `BR2_TARGET_UBOOT_NEEDS_GNUTLS=y` (the MangoPi defconfig has it for
  U-Boot 2026.01).
- Device tree: recent U-Boot builds sunxi device trees from
  `dts/upstream` (`CONFIG_OF_UPSTREAM`, names like
  `allwinner/sun8i-t113s-mangopi-mq-r-t113`) and no longer ships
  `arch/arm/dts/sun8i-t113s.dtsi`. To verify: how the custom Tess DTS
  (`BR2_TARGET_UBOOT_CUSTOM_DTS_PATH`) fits in that, or whether U-Boot can
  use the kernel DTS. Ideally there is one Tess DTS for both.
- Environment: `CONFIG_ENV_IS_IN_FAT` looks for `uboot.env` on a FAT
  partition that does not exist ("Unable to read uboot.env" at every
  boot). Either `CONFIG_ENV_IS_NOWHERE`, or an environment in a raw area
  of the SD NAND if it must be writable.
- `board/phyxbe/tess/uboot/uenv.txt` is not used by anything (it comes
  from another project): remove it.
- Both images use the same U-Boot settings; keep the two defconfigs in
  sync.
- Test both boot paths: FEL with the flasher image (`boot.scr` at
  `0x43100000`) and distro boot of the main image from the SD NAND
  (extlinux). The `ums` and `dfu` commands are still enabled and can
  later be used for factory flashing over USB.

## 4. Flasher image: `configs/phyxbe_tess_flasher_defconfig` (works)

Purpose: factory/recovery image. Booted over USB with sunxi-fel, writes
the main image to SDC0 and flashes the ESP32-C3 over UART4.

- Boot: FEL, `board/phyxbe/tess/flash.sh output-flasher` loads U-Boot,
  kernel, DTB, `boot.scr` and `rootfs.squashfs.uboot` (at `0x43300000`,
  `initrd_high=ffffffff`).
- Root filesystem: **xz squashfs loaded as initrd into `/dev/ram0`**
  (`root=/dev/ram0 ro`, `flasher.frag`: `SQUASHFS`, `SQUASHFS_XZ`,
  `BLK_DEV_RAM` up to 64 MB). It stays compressed in RAM, unlike an
  initramfs, which needed the compressed and the unpacked copy at the
  same time and did not fit in the 128 MB (about 80 MB free) with Python.
  `post-image-flasher.sh` wraps it in a U-Boot ramdisk header. Note:
  classic initrd support is marked for removal in the kernel (only the
  `/linuxrc` path is deprecated in 6.18).
- No Python: esptool 5 needs `rich_click`, which Buildroot does not
  package, plus `python-cryptography`. The flasher uses **espflash**
  (Buildroot package, Rust) instead. espflash only accepted ports listed
  by the serialport crate, which does not list the T113 UARTs: fixed by
  `package/espflash/0001-*.patch` (to be sent upstream).
- Contents: BusyBox, espflash, `libgpiod2` tools, e2fsprogs, the
  ESP32-C3 firmware and the main image (`/usr/share/tess/sdcard.img.xz`,
  xz -6 so busybox xzcat needs little RAM, plus `sdcard.img.info` with
  its size and SHA-256), added by `post-build-flasher.sh` from
  `output/images/sdcard.img`. The main image must be built first.
- No esp-hosted module (it would own WiFi.EN), no WiFi packages.
- `esp32c3-flash`:
  1. PE10 (BOOT) low, pulse PE11 (EN): ROM download mode (gpioset).
  2. `espflash write-bin --chip esp32c3 --port /dev/ttyS4 --baud 1500000
     --before no-reset --after no-reset --non-interactive 0x0
     tess-esp32c3.bin` (skips unchanged regions, verifies).
  3. Release PE10, reset the ESP, check its boot log on ttyS4. WiFi.EN
     stays driven high by a background gpioset.
- `tess-install`: run `esp32c3-flash` first (on failure the SD NAND is
  left untouched), then write `sdcard.img.xz` to `/dev/mmcblk0` and verify it
  against the SHA-256. Run by hand for now.
- Once the SD NAND has a boot image, FEL needs SW2 + SW1 again (a
  `reboot` boots the SD NAND).
- Tested 2026-10-07: boots over FEL (squashfs in `/dev/ram0`, 70 MB RAM
  free), `tess-install` takes 1.5 minutes (espflash at 1500000 baud,
  verified, then the SD NAND written and verified).

## 5. Main image: `configs/phyxbe_tess_defconfig` (boots from the SD NAND)

Purpose: the normal product image, booting on its own from the SD NAND.

- Done: no initramfs, 128 MB ext4 root filesystem. `genimage.cfg`:
  U-Boot SPL at 8 KiB, one bootable rootfs partition (`mmcblk0p1`).
  U-Boot's distro boot loads `/boot/extlinux/extlinux.conf` (kernel and
  DTB in `/boot`). The boot script and sunxi-fel host tools moved to
  the flasher.
- `reboot` needs the watchdog: the SoC dtsi has it `reserved`, the Tess
  DTS enables it, so `sunxi-wdt` provides the restart handler.
- Tested 2026-10-07: SPL, U-Boot distro boot (extlinux), ext4 root on
  `mmcblk0p1`. esp32_spi gets the boot-up event, detects the ESP32-C3,
  switches SPI to 30 MHz, versions match (`NG-1.0.6.0.14`), wlan0
  appears and wpa_supplicant scans (5 scans in a row, no errors).
- **Fixed: SPI command timeouts.** Commands timed out (`CMD_TIMEOUT`)
  and their response came with the next command (`CMD_RESP_MISMATCH`).
  Cause: the T113 pin controller samples GPIO interrupts with the 32 kHz
  LOSC by default (`Px_EINT_DEB` reset value 0), so it missed the short
  ESP32-C3 handshake/data-ready pulses. Fix in the Tess DTS:
  `&pio { input-debounce = <1 1 1 1 1 1>; }` (HOSC, 750 kHz sampling).
- **Worked around: no data after connecting.** With WPA2 the driver and
  the firmware keep the data path closed (EAPOL only) until
  `CMD_STA_SET_AUTHORIZED`. The firmware's `esp_wifi_auth_done_internal()`
  (closed Wi-Fi library) fails there, every time, also when retried 600 ms
  later, so no DHCP. `esp32c3/patches/0002-*.patch` authorizes the port
  anyway (with a warning). Tested: DHCP, ping, DNS, 10 MB download at
  9.1 Mbit/s, no SPI timeouts. Suspected cause: esp-hosted-linux
  `2c41cd4` (2026-10-01, removed the libwpa_supplicant linkage from the
  firmware); to be confirmed by building from the commit before it.
- **Open: reconnect.** After `wpa_cli disconnect` + `reconnect` the
  driver loops (`auth timeout`, `Drop DISCONNECT_EVENT for unexpected
  generation`); reloading `esp32_spi` recovers.
- WiFi configuration: `/boot/wpa_supplicant.conf`; `/etc/rc.netif` (udev)
  starts wpa_supplicant and ifplugd/udhcpc when wlan0 appears.
- `iwlist` cannot scan (no WEXT), use `iw` or wpa_supplicant.
- **Fixed: regulatory.db.** cfg80211 is built in (the esp-hosted package
  forces `CONFIG_CFG80211=y`) and tries to load `regulatory.db` before
  the root filesystem is mounted. After that failure the kernel never
  retries (`regdb = ERR_PTR(-ENODATA)`), so `iw reg set` was silently
  ignored. `/etc/init.d/S45regdb` runs `iw reg reload` and, if set in
  `/etc/default/regdomain`, `iw reg set $REGDOMAIN` (empty by default:
  world domain). esp-hosted logs `Regulatory domain 00 apply failed`
  during the reload (the firmware refuses the world domain), harmless.
- **Fixed: BLE.** `btattach` from BlueZ 5.86 ORs the speed into
  `c_cflag`, which gives B0 (hang up, RTS/DTR dropped) with glibc >= 2.42,
  where `B500000` is 500000: the controller never answered HCI Reset.
  Backported the upstream fix (`package/bluez5_utils/0001-*.patch`).
  Tested: `btattach -B /dev/ttyS2 -P h4 -S 500000`, bluetoothctl LE scan
  finds devices. `bluetoothctl` needs commands on stdin when not run
  interactively.
- To do: a data partition (`mmcblk0p2`). `rootfs_overlay/etc/default/datafs`
  still points `DATDEV` at `mmcblk0p1`, which is now the rootfs; nothing
  calls `/usr/bin/datafs` today, but fix this before using it, as it
  runs `mkfs.ext4` when the mount fails.
- WiFi/BLE packages: `esp-hosted`, `wpa_supplicant` (nl80211),
  `wireless-regdb`, `iw`, `bluez5_utils` (client, monitor, tools); to
  add: `network_adapter.bin` for OTA. No Python, no espflash.
- Boot sequence (init script, to do):
  1. `modprobe esp32_spi` (udev already loads it from the device tree).
  2. If the ESP firmware version differs from the module version: load
     with `ota_file=/lib/firmware/esp-hosted/network_adapter.bin`, let
     the driver write the new app to the inactive OTA partition and
     reset the ESP, then load normally.
  3. `btattach -B /dev/ttyS2 -P h4 -S 500000`: done, `/etc/init.d/S41btattach`
     (arguments in `/etc/default/btattach`) waits up to 20 s for wlan0,
     i.e. for the ESP32-C3 firmware to run, then starts btattach.
- To verify: whether the driver allows OTA while the firmware version
  does not match (it refuses normal operation on mismatch). If not, the
  OTA must happen with the old module before the module is updated,
  or the version check needs a patch.
- OTA only updates the application. Bootloader and partition table
  changes still need the flasher image.

## 6. Steps

1. ~~Buildroot 2026.08 / kernel 6.18.8 bring-up.~~ Done, display works.
2. ~~Kernel module and device tree.~~ Done, probes on the board.
3. ~~Firmware build script and binaries.~~ Done.
4. ~~Flasher image: espflash, squashfs root, `tess-install`.~~ Done.
5. Main image from the SD NAND: boots, WiFi scans work (SPI timeouts
   fixed with `input-debounce`), BLE scans work (btattach fix),
   regulatory.db loads (S45regdb), WPA2 + DHCP work (firmware patch 0002).
   Next: confirm the cause of the authorization failure upstream, fix the
   reconnect loop.
6. Main image: data partition, init scripts, OTA update of the ESP
   firmware.
7. U-Boot update (section 3.4), test FEL and SD NAND boot again.
8. Update `readme.txt` for both images.

Related TODOs:

- Move the Raspberry Pi 7" DSI display into a device tree overlay
  (see `readme.txt`).
- Upstream: esp-hosted-linux HCI UART fix for ESP-IDF v6.1; Buildroot
  `esp-hosted` package update; espflash patch for non-enumerated ports;
  Buildroot `bluez5_utils` btattach backport;
  Buildroot `python-esptool` 5.x misses its `rich_click`/`click`
  dependencies.
- Flasher: `seedrng` cannot write `/var/lib/seedrng` on the read-only
  root (harmless warning); espflash's progress bar floods the console.

## 7. Decisions

1. Firmware binaries: committed in this repository, in the flasher
   rootfs overlay.
2. `esp-hosted` package: Buildroot's own package is updated
   (upstreamable).
3. Flasher: the main image is embedded in the flasher image and written
   by `tess-install` on the board.
4. BLE HCI baudrate: 500000 (exact on the T113 UART).
5. Flashing tool: espflash, no Python in the flasher image.
6. U-Boot version: 2026.01, as the MangoPi defconfig.

# Tess: ESP32-C3 WiFi/BLE and image layout plan

Status: plan, nothing implemented yet.

Goals:

- WiFi through the ESP32-C3 using esp-hosted
  (https://github.com/espressif/esp-hosted-linux), with SPI0 as the WiFi
  transport, a Linux kernel module and a device tree node.
- BLE through the ESP32-C3 using HCI over UART (UART2).
- Two images, each with its own defconfig:
  - a **flasher image**, booted over USB (FEL), that writes the main image
    to the soldered SD NAND on SDC0 and does the initial flash of the
    ESP32-C3 over UART4 with Python and esptool;
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
| UART4 TX / RX (UART_PROG) | PE4 / PE5             | GPIO20 (U0RXD) / GPIO21 (U0TXD)   | ROM bootloader, esptool              |
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

## 2. esp-hosted findings

- `espressif/esp-hosted-linux` is the successor of `esp_hosted_ng` from
  `espressif/esp-hosted` (split on 2026-08-03, history kept).
  - Host driver: `host/`, GPL-2.0, built with `target=spi` into
    `esp32_spi.ko`.
  - Firmware: `esp/esp_driver/network_adapter/`, Apache-2.0, ESP-IDF v6.1
    (commit pinned in `esp/esp_driver/.env`, plus patches applied by
    `esp/esp_driver/setup.sh`).
- Device tree support (`compatible = "espressif,esp32-spi"`,
  `reset-gpios`, `handshake-gpios`, `data-ready-gpios`,
  `spi-max-frequency`, `spi-cpol`) exists **only on master**, not in the
  `release/ng-1.0.6` tag. Pin a master commit.
- Host driver and firmware versions must match exactly: the driver
  compares version strings and refuses a mismatch. Build both from the
  same commit.
- Kernel compatibility guards go up to 7.1 and mention 6.18. Upstream CI
  only builds for x86, so an ARM32 build against 6.18.8 is unverified.
- The driver pulses `reset-gpios` at probe (500 ms boot wait) and owns
  that GPIO while bound.
- Bluetooth: with `CONFIG_BT_CTRL_HCI_MODE_UART_H4=y` the firmware
  exposes HCI on UART1 (TX=GPIO5, RX=GPIO18, RTS=GPIO19, CTS=GPIO8),
  921600 baud by default (`CONFIG_EXAMPLE_HCI_UART_BAUDRATE`), RTS/CTS
  always on. The host driver registers no HCI device in that mode;
  attach with `btattach -B /dev/ttyS2 -P h4 -S 921600`.
- No prebuilt firmware binaries in the repo or the releases.
- The driver supports in-band firmware update over the transport with
  the `ota_file=` module parameter (`docs/guides/ota.md`). This is the
  update path for the main image.

## 3. Common parts (both images)

### 3.1 Kernel module package

- Update `package/esp-hosted` to `esp-hosted-linux` at a pinned master
  commit: `ESP_HOSTED_MODULE_SUBDIRS = host`, `target=spi`, license file
  `host/LICENSE`, hash file. Keep it upstreamable for Buildroot.
- Drop `board/phyxbe/tess/patches/esp-hosted/0001-dt-fixes.patch` and the
  `esp-hosted-sergey` override in `local.mk`.
- If ARM32/6.18 fixes are needed: work in a local checkout, use it with
  `ESP_HOSTED_OVERRIDE_SRCDIR`, and turn the fixes into patches (and
  upstream pull requests).
- Kernel config: `CONFIG_BT`, `CONFIG_BT_HCIUART`,
  `CONFIG_BT_HCIUART_H4`, `CONFIG_CFG80211` (package fixups or
  `linux.defconfig`/fragment).

### 3.2 Device tree

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

- The aliases give stable tty names (today UART2 shows up as ttyS0 and
  UART4 as ttyS1).
- Drop the unused `gpio_out_pe_pins` group. PE10 (BOOT) stays a plain
  GPIO for user space (libgpiod, line offset 4 * 32 + 10 = 138).

### 3.3 ESP32-C3 firmware

- Build outside Buildroot (ESP-IDF downloads several GB of toolchains,
  which does not fit the Buildroot model): a script in
  `board/phyxbe/tess/esp32c3/` that builds in the official
  `espressif/idf` Docker image, with
  - the same esp-hosted-linux commit as the kernel module,
  - the `setup.sh` patches applied to ESP-IDF,
  - a Tess `sdkconfig.defaults` addition: target esp32c3, SPI transport,
    `CONFIG_BT_CTRL_HCI_MODE_UART_H4=y`, HCI baudrate, console on UART0.
- Output: `bootloader.bin`, `partition-table.bin`,
  `ota_data_initial.bin`, `network_adapter.bin` and `flash_args`
  (offsets from the IDF build, two OTA partitions on 4 MB flash).
- A small `esp-hosted-firmware` package installs them in
  `/lib/firmware/esp-hosted/`. Open: binaries in a release tarball
  (download + hash) or committed in the repo.

## 4. Flasher image: `configs/phyxbe_tess_flasher_defconfig`

Purpose: factory/recovery image. Booted over USB with sunxi-fel, runs
from an initramfs, writes the main image to SDC0 and flashes the ESP32-C3
over UART4.

- Boot: FEL, like today (`flash.sh`, `uboot/boot.cmd`, initramfs at
  `0x43300000` with `initrd_high=ffffffff`).
- Contents, kept minimal to fit in RAM (128 MB, about 80 MB free):
  BusyBox, `python3` (PYC only), `python-esptool`, `libgpiod2` tools,
  e2fsprogs, the ESP32-C3 firmware (all four binaries + `flash_args`),
  USB gadget support. No WiFi, BLE, display or other main-image packages.
- Writing the main image to SDC0: export `/dev/mmcblk0` as a USB
  mass-storage gadget (configfs `mass_storage`), so the host writes
  `sdcard.img` with `dd` or `bmaptool`. The image never has to fit in
  the board's RAM. (Alternative: stream it over the USB network gadget,
  `ssh root@tess 'dd of=/dev/mmcblk0' < sdcard.img`.)
- ESP32-C3 initial flash, at boot (init script):
  1. PE10 (BOOT) low, pulse PE11 (EN) low/high: ROM download mode.
  2. `esptool --chip esp32c3 -p /dev/ttyS4 -b 460800 --before no-reset
     --after no-reset write-flash @flash_args` (skip when
     `verify-flash` already matches).
  3. Release PE10, pulse PE11: boot the new firmware; check its boot log
     on ttyS4.
- Status reporting on the console (UART3), the LEDs and/or the display.
- Size risk: `python-esptool` pulls in `python-cryptography` (Rust build
  on the build machine, several MB on target). Measure the unpacked
  initramfs; if too large, look at esptool without cryptography or at
  esp-serial-flasher as a fallback.

## 5. Main image: `configs/phyxbe_tess_defconfig`

Purpose: the normal product image, booting on its own from the SD NAND.

- No initramfs: root filesystem as ext4 on SDC0.
- `genimage.cfg`: U-Boot SPL at 8 KiB (T113 boot ROM boots from SDC0),
  a boot partition (kernel, DTB, boot script or extlinux), rootfs, and a
  data partition (see `rootfs_overlay/usr/bin/datafs`).
- U-Boot: boot from mmc0 (boot script or `extlinux.conf`, which already
  exists in the overlay), `root=/dev/mmcblk0pN rootwait`.
- WiFi/BLE packages: `esp-hosted`, `esp-hosted-firmware` (only
  `network_adapter.bin` is needed here), `wpa_supplicant` (nl80211),
  `iw`, `bluez5_utils` (client + tools for `btattach`),
  `wireless-regdb`. No Python and no esptool.
- Boot sequence (init script):
  1. `modprobe esp32_spi`.
  2. If the ESP firmware version differs from the module version: load
     with `ota_file=/lib/firmware/esp-hosted/network_adapter.bin`, let
     the driver write the new app to the inactive OTA partition and
     reset the ESP, then load normally.
  3. `btattach -B /dev/ttyS2 -P h4 -S 921600`.
- To verify: whether the driver allows OTA while the firmware version
  does not match (it refuses normal operation on mismatch). If not, the
  OTA must happen with the old module before the module is updated,
  or the version check needs a patch.
- OTA only updates the application. Bootloader and partition table
  changes still need the flasher image.

## 6. Steps

1. Finish the Buildroot 2026.08 / kernel 6.18.8 bring-up (current work).
2. Kernel module: update the `esp-hosted` package, build for ARM32 6.18.8,
   add the device tree changes.
3. Firmware: Docker build script, first binaries, `esp-hosted-firmware`
   package.
4. Manual bring-up from the current FEL image: flash the ESP by hand
   over ttyS4, load the module, `iw dev wlan0 scan`, `wpa_supplicant`,
   then `btattach` + `bluetoothctl scan on`.
5. Flasher defconfig: minimal initramfs, mass-storage gadget, automatic
   ESP flash.
6. Main defconfig: SD NAND boot (genimage, U-Boot, rootfs on SDC0), init
   scripts, OTA update of the ESP firmware.
7. Update `readme.txt` for both images.

Related TODOs:

- When updating U-Boot, enable device tree overlay support
  (`CONFIG_OF_LIBFDT_OVERLAY`).
- Move the Raspberry Pi 7" DSI display into a device tree overlay
  (see `readme.txt`).

## 7. Open decisions

1. Firmware binaries: release tarball (download + hash) or committed in
   this repository?
2. `esp-hosted` package: update Buildroot's own package (upstreamable) or
   a Tess-only package?
3. Flasher: USB mass storage (host writes with dd/bmaptool) or streaming
   over the USB network gadget?
4. BLE HCI baudrate: keep 921600 or go higher?

Phyx Tess
=========

Tess is an Adafruit Feather compatible board built around the Allwinner
T113-S3 (dual core Cortex-A7, 1 GHz, 128 MB DDR3 in package).

Board features:
- USB-C connector (USB0: USB device, and the FEL USB bootloader)
- SD NAND storage on SDC0 (soldered, 480 MiB)
- ESP32-C3 WiFi/BLE co-processor (SPI0 for WiFi, UART2 for BLE HCI)
- MIPI DSI display connector
- Adafruit Feather headers (UART5, SPI1, I2C3, GPIO, ADC)
- Extra headers: P6 (USB1 host) and P7 (UART3 debug console)
- RESET button (SW1) and USB bootloader button (SW2)

How to build
============

$ make phyxbe_tess_defconfig
$ make

This creates output/images/sdcard.img, with:

    8 KiB  U-Boot with SPL (the T113 boot ROM loads it from 8 KiB)
    4 MiB  mmcblk0p1: root filesystem (ext4), with the kernel, the
           device tree and /boot/extlinux/extlinux.conf for U-Boot

Serial console
==============

The Linux and U-Boot console is UART3 (ttyS3), 115200 8N1, 3.3V levels.
Connect a 3.3V USB-serial adapter to header P7:

  P7 pin 1  UART3.TX (PB6)  -> RX of the USB-serial adapter
  P7 pin 2  UART3.RX (PB7)  -> TX of the USB-serial adapter
  GND                       -> GND of the USB-serial adapter
                               (e.g. Feather header P2 pin 13)

Do not connect the VCC pin of the adapter, and do not use a 5V adapter.

$ picocom -b 115200 /dev/ttyUSB0

How to write the image
======================

The SD NAND is soldered on the board, so the image is written from
U-Boot, started over USB with the FEL bootloader of the T113:

1. Connect the USB-C connector to the host and the serial console.
2. Hold SW2 (it pulls SDC0 CLK low, which hides the SD NAND from the
   boot ROM) and press and release SW1 (RESET). The SoC is now in FEL.
   Check with:

   $ ./output/host/bin/sunxi-fel version

3. Load U-Boot and the image into RAM and start U-Boot:

   $ ./output/host/bin/sunxi-fel -v uboot output/images/u-boot-sunxi-with-spl.bin \
         write 0x43000000 output/images/sdcard.img

4. On the serial console, press a key to stop the autoboot and write the
   image to the SD NAND. The image is 64 MiB, i.e. 0x20000 blocks of
   512 bytes (use the size of sdcard.img divided by 512 if it differs):

   => mmc write 0x43000000 0 0x20000
   => reset

If SW2 does not get the board into FEL, erase the U-Boot SPL from Linux
on the board; the boot ROM then falls back to FEL on the next reset:

   # dd if=/dev/zero of=/dev/mmcblk0 bs=512 seek=16 count=2 conv=fsync
   # reboot

WiFi
====

WiFi goes through the ESP32-C3 with esp-hosted: the esp32_spi kernel
module (esp-hosted package) talks over SPI0 to the esp-hosted firmware
on the ESP32-C3. That firmware is not built by Buildroot: the ESP32-C3
must already run the network_adapter firmware of esp-hosted-linux
(https://github.com/espressif/esp-hosted-linux, esp/esp_driver/) built
from the same commit as the esp-hosted package, as the driver refuses a
firmware of another version.

Edit board/phyxbe/tess/rootfs_overlay/etc/wpa_supplicant.conf, or
/etc/wpa_supplicant.conf once on the board:

* Replace YOURSSID with your AP ssid
* Replace YOURPASSWD with your AP password

The MIPI DSI display is not enabled in this configuration.

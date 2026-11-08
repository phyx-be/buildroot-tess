Phyx Tess
=========

Tess is an Adafruit Feather compatible board built around the Allwinner
T113-S3 (dual core Cortex-A7, 1 GHz, 128 MB DDR3 in package), made by
Phyx.

https://phyx.be
https://github.com/phyx-be/TESS

Board features:
- USB-C connector (USB0: USB device, and the FEL USB bootloader)
- microSD card connector on SDC0
- ESP32-C3 WiFi/BLE co-processor (SPI0 for WiFi, UART2 for BLE HCI)
- MIPI DSI display connector
- Adafruit Feather headers (UART5, SPI1, I2C3, GPIO, ADC)
- USB1 host and UART3: two extra pins at the end of each Feather
  header row
- RESET and BOOT buttons

How to build
============

$ make phyxbe_tess_defconfig
$ make

This creates output/images/sdcard.img, with:

    8 KiB  U-Boot with SPL (the T113 boot ROM loads it from 8 KiB)
    4 MiB  mmcblk0p1: root filesystem (ext4), with the kernel, the
           device tree and /boot/extlinux/extlinux.conf for U-Boot

How to write the image
======================

Take the microSD card out of the board and plug it in the host. Write
the image to it, where sdX is the card:

$ sudo dd if=output/images/sdcard.img of=/dev/sdX bs=1M conv=fsync

Then plug the card back in the board and power it up: it boots from
the card.

Serial console
==============

The Linux and U-Boot console is UART3 (ttyS3), 115200 8N1, 3.3V levels,
on the two extra pins at the end of the 12-pin Feather header row (U3T
and U3R on the silkscreen). Connect a 3.3V USB-serial adapter:

  U3T: UART3.TX (PB6)  -> RX of the USB-serial adapter
  U3R: UART3.RX (PB7)  -> TX of the USB-serial adapter
  GND                  -> GND of the USB-serial adapter

Do not connect the VCC pin of the adapter, and do not use a 5V adapter.

$ picocom -b 115200 /dev/ttyUSB0

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

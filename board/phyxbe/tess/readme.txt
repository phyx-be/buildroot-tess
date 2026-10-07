Phyx Tess
=========

Tess is an Adafruit Feather compatible board built around the Allwinner
T113-S3 (dual core Cortex-A7, 1GHz, 128MB DDR3 in package).

Board features:
- USB-C connector (USB0, OTG / FEL)
- SD NAND storage on SDC0
- ESP32-C3 WiFi/BLE co-processor (SPI0 + UART2, programming over UART4)
- MIPI DSI display connector
- Adafruit Feather headers (UART5, SPI1, I2C3, GPIO, ADC)
- Extra headers: P6 (USB1) and P7 (UART3 debug console)
- RESET button (SW1) and USB bootloader button (SW2)

How to build
============

$ make phyxbe_tess_defconfig
$ make

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

Booting over USB (FEL)
======================

1. Connect the USB-C connector to the host.
2. Hold SW2 (pulls SDC0 CLK low, disabling the on-board storage) and
   press/release SW1 (RESET). The SoC now enters the USB bootloader (FEL).
   Check with:

   $ ./output/host/bin/sunxi-fel version

3. From the top-level buildroot directory, load and start U-Boot, the
   kernel, the device tree and the initramfs:

   $ ./board/phyxbe/tess/flash.sh

The board boots with the root filesystem in RAM. The console is available
on UART3, see above. Once booted, the board also exposes a CDC-ECM/RNDIS
USB network gadget.

TODO
====

- Move the Raspberry Pi 7" DSI display (panel, display MCU, GT911
  touchscreen, touch regulator and backlight) out of
  sun8i-t113s-tess.dts into a device tree overlay, so the base board
  boots cleanly without a display attached. This needs U-Boot overlay
  support (CONFIG_OF_LIBFDT_OVERLAY), a DTB built with symbols (-@) and
  an extra FEL write in flash.sh.

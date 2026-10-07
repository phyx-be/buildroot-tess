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

Two images: the main image, booting from the SD NAND, and a flasher
image, booted over USB (FEL), that installs the main image and flashes
the ESP32-C3. The flasher embeds the main image, so build that first:

$ make phyxbe_tess_defconfig
$ make
$ make O=output-flasher phyxbe_tess_flasher_defconfig
$ make O=output-flasher

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

USB console
===========

The main image is a USB serial device (CDC ACM) on the USB-C connector,
with a login console on ttyGS0. On a Linux host:

$ picocom /dev/ttyACM0

The gadget type is set in /etc/default/usbgadget: "serial" in the main
image, "ethernet" (CDC ECM + RNDIS network) in the flasher image.
ModemManager probes the port once when it appears, which can show a
"Login incorrect" on the console.

Installing over USB (FEL)
=========================

1. Connect the USB-C connector to the host.
2. Hold SW2 (pulls SDC0 CLK low, disabling the on-board storage) and
   press/release SW1 (RESET). The SoC now enters the USB bootloader (FEL).
   Check with:

   $ ./output/host/bin/sunxi-fel version

3. From the top-level buildroot directory, load and start the flasher
   image:

   $ ./board/phyxbe/tess/flash.sh output-flasher

4. Log in on the console (UART3, see above) and run:

   # tess-install

   It flashes the ESP32-C3 firmware over UART4 and writes the main image
   to the SD NAND. Then reset the board without SW2 to boot it.

WiFi: write /boot/wpa_supplicant.conf on the board, e.g.

   # { echo "ctrl_interface=/var/run/wpa_supplicant"
       wpa_passphrase "<ssid>" "<password>" | grep -v '#psk'
     } > /boot/wpa_supplicant.conf

and reboot. The country is set in /etc/default/regdomain.

TODO
====

- Move the Raspberry Pi 7" DSI display (panel, display MCU, GT911
  touchscreen, touch regulator and backlight) out of
  sun8i-t113s-tess.dts into a device tree overlay, so the base board
  boots cleanly without a display attached. This needs U-Boot overlay
  support (CONFIG_OF_LIBFDT_OVERLAY), a DTB built with symbols (-@) and
  an extra FEL write in flash.sh.

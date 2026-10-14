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

The main build also creates output/images/tess-update.raucb, a RAUC
update bundle with its root filesystem (see "Updates").

Storage layout
==============

SD NAND (mmcblk0, 480 MiB):

  8 KiB    U-Boot with SPL
  1 MiB    U-Boot environment, two redundant copies of 64 KiB
  4 MiB    mmcblk0p1  root filesystem slot A (96 MiB, ext4, read-only)
  100 MiB  mmcblk0p2  root filesystem slot B (96 MiB, ext4, read-only)
  196 MiB  mmcblk0p3  data (284 MiB, ext4, read-write, /data)

U-Boot boots the slot that RAUC selected: BOOT_ORDER, BOOT_A_LEFT and
BOOT_B_LEFT in its environment (fw_printenv on the board). Each boot
attempt costs one, /etc/init.d/S99rauc-mark-good resets the counter
once the system is up, and a slot that fails three times in a row falls
back to the other one.

The root filesystem is read-only. These directories are bind-mounted
from /data/rootfs (/etc/default/datafs), so they persist across reboots
and updates: /etc/dropbear (SSH host keys), /etc/wpa_supplicant (WiFi),
/var/lib and /var/log. Everything else is replaced by an update.

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

   It flashes the ESP32-C3 firmware over UART4, writes the main image
   to the SD NAND (both root filesystem slots) and creates an empty data
   partition, erasing the previous one. Then reset the board without SW2
   to boot it.

If SW2 does not get the board into FEL, erase the U-Boot SPL from the
running main image; the boot ROM then falls back to FEL on the next
reset:

   # dd if=/dev/zero of=/dev/mmcblk0 bs=512 seek=16 count=2 conv=fsync
   # reboot

WiFi
====

The WiFi configuration is /etc/wpa_supplicant/wpa_supplicant.conf, on
the data partition. On the first boot it is a copy of
/boot/wpa_supplicant.conf from the image, if that exists. To change it
on the board:

   # { echo "ctrl_interface=/var/run/wpa_supplicant"
       wpa_passphrase "<ssid>" "<password>" | grep -v '#psk'
     } > /etc/wpa_supplicant/wpa_supplicant.conf

and reboot. The country is set in /etc/default/regdomain (in the image).

Updates
=======

Copy the bundle to the data partition and install it with RAUC; it
writes the other root filesystem slot and makes U-Boot boot it next:

   $ scp output/images/tess-update.raucb root@<board>:/data/
   # rauc install /data/tess-update.raucb
   # reboot

"rauc status" shows the slots and which one is booted. Bundles are
signed with the development key in board/phyxbe/tess/rauc/ unless
TESS_RAUC_KEY and TESS_RAUC_CERT are set; see rauc/README.

Display
=======

The Raspberry Pi 7" DSI display (with touchscreen) is not in the board
device tree but in the rpi-7inch-dsi.dtbo overlay. The main image loads
it with "fdtoverlays" in /boot/extlinux/extlinux.conf: remove that line
from board/phyxbe/tess/rootfs_overlay when no display is connected. The flasher applies it in its boot script.

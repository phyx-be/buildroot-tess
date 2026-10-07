#!/bin/sh
#
# Boot Tess over USB (FEL): load U-Boot, kernel, device tree, boot script
# and initramfs into RAM and start them.
#
# Usage, from the top-level Buildroot directory:
#   board/phyxbe/tess/flash.sh [output directory, default: output]

O="${1:-output}"
I="${O}/images"

"${O}/host/bin/sunxi-fel" -v uboot "${I}/u-boot-sunxi-with-spl.bin" \
	write 0x42000000 "${I}/zImage" \
	write 0x43000000 "${I}/sun8i-t113s-tess.dtb" \
	write 0x43100000 "${I}/boot.scr" \
	write 0x43300000 "${I}/rootfs.cpio.uboot"

#!/bin/sh

./output/host/usr/bin/sunxi-fel -v uboot output/images/u-boot-sunxi-with-spl.bin \
             write 0x42000000 output/images/zImage \
             write 0x43000000 output/images/sun8i-t113s-tess.dtb \
             write 0x43100000 output/images/boot.scr \
             write 0x43300000 output/images/rootfs.cpio.uboot
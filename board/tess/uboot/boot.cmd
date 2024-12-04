setenv bootdelay 5
setenv bootargs console=ttyS3,115200 root=/dev/mmcblk0p4 init=/init loglevel=8
setenv fdt_high ffffffff
bootz 0x42000000 0x43300000 0x43000000
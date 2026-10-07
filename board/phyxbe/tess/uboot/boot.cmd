setenv bootdelay 2
setenv bootargs console=tty0 console=ttyS3,115200 root=/dev/ram0 ro fbcon=rotate:1 loglevel=8
setenv fdt_high ffffffff
setenv initrd_high ffffffff
bootz 0x42000000 0x43300000 0x43000000
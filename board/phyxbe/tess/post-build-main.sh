#!/bin/sh
#
# Main image: login console on the USB serial gadget (ttyGS0)

set -eu

INITTAB="${TARGET_DIR}/etc/inittab"

if ! grep -q '^ttyGS0::' "${INITTAB}"; then
	sed -i '/# GENERIC_SERIAL$/a ttyGS0::respawn:/usr/sbin/usb-getty # USB serial gadget' "${INITTAB}"
fi

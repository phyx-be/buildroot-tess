################################################################################
#
# esp-hosted
#
################################################################################

ESP_HOSTED_VERSION = 2a8772cadc34bcfc8a22cc4bbf7ee0caa239ff4c
ESP_HOSTED_SITE = $(call github,espressif,esp-hosted-linux,$(ESP_HOSTED_VERSION))
ESP_HOSTED_DEPENDENCIES = linux
ESP_HOSTED_LICENSE = GPL-2.0
ESP_HOSTED_LICENSE_FILES = host/LICENSE
ESP_HOSTED_MODULE_SUBDIRS = host

define ESP_HOSTED_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_NET)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_CFG80211)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211)
	$(call KCONFIG_ENABLE_OPT,CONFIG_BT)
	$(if $(BR2_PACKAGE_ESP_HOSTED_SPI),
		$(call KCONFIG_ENABLE_OPT,CONFIG_SPI),
		$(call KCONFIG_ENABLE_OPT,CONFIG_MMC))
endef

ifeq ($(BR2_PACKAGE_ESP_HOSTED_SPI),y)
ESP_HOSTED_MODULE_MAKE_OPTS = target=spi
else
ESP_HOSTED_MODULE_MAKE_OPTS = target=sdio
endif

ESP_HOSTED_MODULE_MAKE_OPTS += KCFLAGS="-Wno-error"

$(eval $(kernel-module))
$(eval $(generic-package))

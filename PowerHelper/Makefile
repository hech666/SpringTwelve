TARGET := iphone:clang:16.5:15.0
ARCHS ?= arm64e
THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

TOOL_NAME = HaogeSpringTwelvePowerHelper
HaogeSpringTwelvePowerHelper_FILES = main.c
HaogeSpringTwelvePowerHelper_CFLAGS = -std=c11 -Wall -Wextra
HaogeSpringTwelvePowerHelper_INSTALL_PATH = /usr/local/libexec
# Theos uses CODESIGN_FLAGS (not CODE_SIGN_FLAGS); ldid requires -S<plist>.
HaogeSpringTwelvePowerHelper_CODESIGN_FLAGS = -S"$(THEOS_PROJECT_DIR)/PowerHelper/entitlements.plist"

include $(THEOS_MAKE_PATH)/tool.mk

# Per-instance after-stage also runs through aggregate's internal-stage path.
# Ownership is deliberately left to the parent's package/install integration.
after-HaogeSpringTwelvePowerHelper-stage::
	$(ECHO_NOTHING)chmod 4755 "$(THEOS_STAGING_DIR)$(HaogeSpringTwelvePowerHelper_INSTALL_PATH)/HaogeSpringTwelvePowerHelper"$(ECHO_END)

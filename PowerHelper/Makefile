TARGET := iphone:clang:16.5:15.0
ARCHS ?= arm64e
THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

TOOL_NAME = AxsSpringTwelvePowerHelper
AxsSpringTwelvePowerHelper_FILES = main.c
AxsSpringTwelvePowerHelper_CFLAGS = -std=c11 -Wall -Wextra
AxsSpringTwelvePowerHelper_INSTALL_PATH = /usr/local/libexec
# Theos uses CODESIGN_FLAGS (not CODE_SIGN_FLAGS); ldid requires -S<plist>.
AxsSpringTwelvePowerHelper_CODESIGN_FLAGS = -S"$(THEOS_PROJECT_DIR)/PowerHelper/entitlements.plist"

include $(THEOS_MAKE_PATH)/tool.mk

# Per-instance after-stage also runs through aggregate's internal-stage path.
# Ownership is deliberately left to the parent's package/install integration.
after-AxsSpringTwelvePowerHelper-stage::
	$(ECHO_NOTHING)chmod 4755 "$(THEOS_STAGING_DIR)$(AxsSpringTwelvePowerHelper_INSTALL_PATH)/AxsSpringTwelvePowerHelper"$(ECHO_END)

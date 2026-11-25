TARGET := iphone:clang:16.5:15.0
ARCHS ?= arm64e
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard MobilePhone

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AxsSpringTwelve
# One injection dylib; each module initializes hooks only in its intended host process.
AxsSpringTwelve_FILES = $(wildcard Hooks/*.xm Sources/*.m)
AxsSpringTwelve_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/Headers -I$(THEOS_PROJECT_DIR)/Sources
AxsSpringTwelve_FRAMEWORKS = UIKit QuartzCore CoreGraphics CoreFoundation Foundation AVFoundation UniformTypeIdentifiers
AxsSpringTwelve_LIBRARIES =
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
  AxsSpringTwelve_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AxsSpringTwelvePrefs
include $(THEOS_MAKE_PATH)/aggregate.mk

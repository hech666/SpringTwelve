TARGET := iphone:clang:16.5:15.0
ARCHS ?= arm64e
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard MobilePhone

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HaogeSpringTwelve
# One injection dylib; each module initializes hooks only in its intended host process.
HaogeSpringTwelve_FILES = $(wildcard Hooks/*.xm Sources/*.m Sources/*.mm)
HaogeSpringTwelve_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/Headers -I$(THEOS_PROJECT_DIR)/Sources
# Preserve the standalone recorder's visible compatibility warnings, scoped to imported files.
Hooks/HaogeCallRecording.xm_CFLAGS += -Wall -Wextra -Wno-error=deprecated-declarations -Wno-error=unused-parameter
Hooks/HaogeRecordings.xm_CFLAGS += -Wall -Wextra -Wno-error=deprecated-declarations -Wno-error=unused-parameter
Sources/HaogeCallRecorderRecordingAccess.mm_CFLAGS += -Wall -Wextra -Wno-error=deprecated-declarations -Wno-error=unused-parameter
HaogeSpringTwelve_CCFLAGS = -std=gnu++17
HaogeSpringTwelve_FRAMEWORKS = UIKit QuartzCore CoreGraphics CoreFoundation Foundation AVFoundation CoreTelephony Contacts CallKit
HaogeSpringTwelve_LIBRARIES =
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
  HaogeSpringTwelve_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += HaogeSpringTwelvePrefs PowerHelper HaogeRealtimeHelper
include $(THEOS_MAKE_PATH)/aggregate.mk

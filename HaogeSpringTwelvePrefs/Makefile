include ../HaogeSpringTwelveBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = HaogeSpringTwelvePrefs
HaogeSpringTwelvePrefs_FILES = $(wildcard *.m)
HaogeSpringTwelvePrefs_CFLAGS = -fobjc-arc -I../Sources
HaogeSpringTwelvePrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
HaogeSpringTwelvePrefs_PRIVATE_FRAMEWORKS = Preferences
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
  HaogeSpringTwelvePrefs_LIBRARIES += roothide
endif
HaogeSpringTwelvePrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk

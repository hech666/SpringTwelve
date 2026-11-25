include ../AxsSpringTwelveBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AxsSpringTwelvePrefs
AxsSpringTwelvePrefs_FILES = $(wildcard *.m)
AxsSpringTwelvePrefs_CFLAGS = -fobjc-arc -I../Sources
AxsSpringTwelvePrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsSpringTwelvePrefs_PRIVATE_FRAMEWORKS = Preferences
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
  AxsSpringTwelvePrefs_LIBRARIES += roothide
endif
AxsSpringTwelvePrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk

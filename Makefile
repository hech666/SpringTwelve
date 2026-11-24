DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include AxsSpringTwelveBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AxsSpringTwelve
AxsSpringTwelve_FILES = $(wildcard Hooks/*.xm Sources/*.m)
AxsSpringTwelve_CFLAGS = -fobjc-arc -I./Headers -I./Sources
AxsSpringTwelve_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsSpringTwelve_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AxsSpringTwelvePrefs
include $(THEOS_MAKE_PATH)/aggregate.mk

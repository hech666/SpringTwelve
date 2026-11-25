include ../AxsSpringTwelveBuild.mk
ARCHS = arm64e
include $(THEOS)/makefiles/common.mk

TOOL_NAME = AxsSpringTwelveMP3Mixer
AxsSpringTwelveMP3Mixer_FILES = main.m
AxsSpringTwelveMP3Mixer_CFLAGS = -fobjc-arc -Wall -Wextra -I$(THEOS_PROJECT_DIR)/MP3Helper/.build/arm64e/install/include
AxsSpringTwelveMP3Mixer_LDFLAGS = $(THEOS_PROJECT_DIR)/MP3Helper/.build/arm64e/install/lib/libmp3lame.a
AxsSpringTwelveMP3Mixer_FRAMEWORKS = Foundation AVFAudio
AxsSpringTwelveMP3Mixer_INSTALL_PATH = /usr/local/bin
AxsSpringTwelveMP3Mixer_CODESIGN_FLAGS = -S"$(THEOS_PROJECT_DIR)/MP3Helper/entitlements.plist"

include $(THEOS_MAKE_PATH)/tool.mk

after-AxsSpringTwelveMP3Mixer-stage::
	$(ECHO_NOTHING)python3 "$(THEOS_PROJECT_DIR)/MP3Helper/stage-relink.py" "$(THEOS_OBJ_DIR)" "$(THEOS_STAGING_DIR)/usr/share/SpringTwelve/MP3Relink"$(ECHO_END)

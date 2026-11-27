HAOGE_CALLRECORDER_RT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ARCHS = arm64e
THEOS_PACKAGE_SCHEME ?= roothide
include ../HaogeSpringTwelveBuild.mk
HAOGE_CALLRECORDER_LAME_PREFIX ?= $(HAOGE_CALLRECORDER_RT_DIR)/../MP3Helper/.build/arm64e/install
include $(THEOS)/makefiles/common.mk
TOOL_NAME = HaogeCallRecorderRealtime
HaogeCallRecorderRealtime_FILES = HaogeCallRecorderRealtime.mm HaogeCallRecorderPCM.cpp
HaogeCallRecorderRealtime_CFLAGS = -fobjc-arc -Wall -Wextra -I../Sources -I$(HAOGE_CALLRECORDER_LAME_PREFIX)/include
HaogeCallRecorderRealtime_CCFLAGS = -std=gnu++17
HaogeCallRecorderRealtime_LDFLAGS = $(HAOGE_CALLRECORDER_LAME_PREFIX)/lib/libmp3lame.a -Wl,-dead_strip
HaogeCallRecorderRealtime_FRAMEWORKS = Foundation AVFAudio AudioToolbox CoreFoundation
HaogeCallRecorderRealtime_INSTALL_PATH = /usr/local/bin
HaogeCallRecorderRealtime_CODESIGN_FLAGS = -S"$(HAOGE_CALLRECORDER_RT_DIR)/entitlements.plist"
include $(THEOS_MAKE_PATH)/tool.mk

after-HaogeCallRecorderRealtime-stage::
	$(ECHO_NOTHING)set -e; python3 "$(HAOGE_CALLRECORDER_RT_DIR)/stage-relink.py" "$(THEOS_OBJ_DIR)" "$(HAOGE_CALLRECORDER_LAME_PREFIX)"; mkdir -p "$(THEOS_STAGING_DIR)/usr/share/doc/HaogeSpringTwelve"; cp "$(HAOGE_CALLRECORDER_RT_DIR)/../MP3Helper/LAME-COPYING" "$(THEOS_STAGING_DIR)/usr/share/doc/HaogeSpringTwelve/LAME-COPYING"$(ECHO_END)

TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = iFunny
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iFunnier

iFunnier_FILES = Logos/iFunnier.x
# Optimization flags recommended by audit
iFunnier_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Os -fvisibility=hidden

# CRITICAL: Expanded Swift Runtime Support
iFunnier_LDFLAGS = -lswiftCore -lswiftFoundation -lswiftObjectiveC -lswiftCompatibility56

iFunnier_FRAMEWORKS = UIKit Foundation AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk

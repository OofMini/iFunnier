TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = iFunny
ARCHS = arm64
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iFunnier

iFunnier_FILES = Logos/iFunnier.x
# FIX: Added flags to ignore 'keyWindow' deprecation errors
iFunnier_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error
iFunnier_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

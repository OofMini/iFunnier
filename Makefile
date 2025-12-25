TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = iFunny
ARCHS = arm64
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iFunnier

# OPTIMIZED: Removed IFunnierSettings.x (Merged into iFunnier.x)
iFunnier_FILES = Logos/iFunnier.x
iFunnier_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
iFunnier_FRAMEWORKS = UIKit Foundation AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
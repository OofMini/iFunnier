TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = iFunny
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iFunnier

# OPTIMIZED: Settings merged into main file
iFunnier_FILES = Logos/iFunnier.x
iFunnier_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Os -fvisibility=hidden

# STANDARD SWIFT FLAGS (Removed broken compatibility libs)
iFunnier_LDFLAGS = -lswiftCore -lswiftFoundation -lswiftObjectiveC

# Added StoreKit for receipt hook
iFunnier_FRAMEWORKS = UIKit Foundation AVFoundation StoreKit

include $(THEOS_MAKE_PATH)/tweak.mk
ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CircleMenu

CircleMenu_FILES = Tweak.x
CircleMenu_FRAMEWORKS = UIKit AudioToolbox QuartzCore
CircleMenu_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk

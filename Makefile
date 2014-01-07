TARGET = ::4.3
ARCHS = armv7 arm64

include theos/makefiles/common.mk

TWEAK_NAME = DMLonger
DMLonger_FILES = Tweak.xm
DMLonger_FRAMEWORKS = CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 Tweetbot Twitter &>/dev/null"

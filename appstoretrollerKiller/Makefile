ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:14.5

include $(THEOS)/makefiles/common.mk

TOOL_NAME = TDDaemonKiller

appstoretrollerKiller_FILES = main.m TSUtil.m
appstoretrollerKiller_CFLAGS = -fobjc-arc
appstoretrollerKiller_CODESIGN_FLAGS = -Sentitlements.plist
appstoretrollerKiller_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk

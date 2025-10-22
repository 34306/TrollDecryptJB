TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard appstored installd TrollDecrypt
ARCHS = arm64 arm64e
THEOS_DEVICE_IP = 192.168.1.160

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TrollDecrypt
TWEAK_NAME = TrollDecryptHook
TOOL_NAME = TDDaemonKiller

# Application files
TrollDecrypt_FILES = SSZipArchive/minizip/unzip.c SSZipArchive/minizip/crypt.c SSZipArchive/minizip/ioapi_buf.c SSZipArchive/minizip/ioapi_mem.c SSZipArchive/minizip/ioapi.c SSZipArchive/minizip/minishared.c SSZipArchive/minizip/zip.c SSZipArchive/minizip/aes/aes_ni.c SSZipArchive/minizip/aes/aescrypt.c SSZipArchive/minizip/aes/aeskey.c SSZipArchive/minizip/aes/aestab.c SSZipArchive/minizip/aes/fileenc.c SSZipArchive/minizip/aes/hmac.c SSZipArchive/minizip/aes/prng.c SSZipArchive/minizip/aes/pwd2key.c SSZipArchive/minizip/aes/sha1.c SSZipArchive/SSZipArchive.m
TrollDecrypt_FILES += main.m TDAppDelegate.m TDRootViewController.m TDDumpDecrypted.m TDUtils.m TDFileManagerViewController.m LSApplicationProxy+AltList.m appstoretrollerKiller/TSUtil.m TDLowerInstallSettingsController.m
TrollDecrypt_FRAMEWORKS = UIKit CoreGraphics MobileCoreServices
TrollDecrypt_CFLAGS = -fobjc-arc
TrollDecrypt_CODESIGN_FLAGS = -Sentitlements.plist
TrollDecrypt_INSTALL_PATH = /Applications
TrollDecrypt_BUNDLE_RESOURCES = flexdecrypt_bin

# Tweak files (hooks into appstored)
TrollDecryptHook_FILES = TweakHook14.xm TweakHook16.xm
TrollDecryptHook_CFLAGS = -fobjc-arc

# Tool to kill daemons with root privileges (renamed to avoid directory conflict)
TDDaemonKiller_FILES = appstoretrollerKiller/main.m appstoretrollerKiller/TSUtil.m
TDDaemonKiller_INSTALL_NAME = appstoretrollerKiller
TDDaemonKiller_CFLAGS = -fobjc-arc
TDDaemonKiller_CODESIGN_FLAGS = -SappstoretrollerKiller/entitlements.plist
TDDaemonKiller_INSTALL_PATH = /usr/local/bin

# dlopen tool
DLOPEN_TOOL_NAME = dlopentool
DLOPEN_TOOL_FILES = dlopentool.c
DLOPEN_TOOL_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/tool.mk


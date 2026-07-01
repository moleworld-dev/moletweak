# ⚠️ Theos 不支持带空格的项目路径。若本仓库位于含空格的目录(如 "github repo"),
#    请先 rsync 到无空格目录再 `make package`,否则 common.mk 会报错停止。
TARGET := iphone:clang:9.3:6.0
ARCHS = armv7

THEOS_DEVICE_IP =

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MoleTweak

MoleTweak_FILES = Tweak.xm
MoleTweak_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
MoleTweak_CFLAGS = -fobjc-arc -fno-modules -fno-exceptions -fno-objc-arc-exceptions \
                   -Wno-deprecated-declarations \
                   -Wno-deprecated-module-dot-map \
                   -Wno-unused-variable -Wno-unused-function \
                   -Wno-error \
                   -fno-builtin-memset
# 不链接 libc++ (iOS 6 无该 dylib),用普通 clang 而不是 clang++
MoleTweak_LDFLAGS = -lSystem -nostdlib++ -Wl,-no_compact_unwind
MoleTweak_USE_LDXX = 0

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 MoleWorld"

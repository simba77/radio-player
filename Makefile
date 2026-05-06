APP     = RadioPlayer.app
BIN_DIR = .build/release
BIN     = $(BIN_DIR)/RadioPlayer
ICNS    = Resources/AppIcon.icns

.PHONY: build run install clean icon lint

icon: $(ICNS)

$(ICNS): scripts/make_icon.swift
	swift scripts/make_icon.swift
	mkdir -p Resources/AppIcon.iconset
	sips -z 16   16   Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_16x16.png    -s format png >/dev/null
	sips -z 32   32   Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_16x16@2x.png -s format png >/dev/null
	sips -z 32   32   Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_32x32.png    -s format png >/dev/null
	sips -z 64   64   Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_32x32@2x.png -s format png >/dev/null
	sips -z 128  128  Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_128x128.png  -s format png >/dev/null
	sips -z 256  256  Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_128x128@2x.png -s format png >/dev/null
	sips -z 256  256  Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_256x256.png  -s format png >/dev/null
	sips -z 512  512  Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_256x256@2x.png -s format png >/dev/null
	sips -z 512  512  Resources/AppIcon.png --out Resources/AppIcon.iconset/icon_512x512.png  -s format png >/dev/null
	cp Resources/AppIcon.png Resources/AppIcon.iconset/icon_512x512@2x.png
	iconutil -c icns Resources/AppIcon.iconset -o $(ICNS)
	rm -rf Resources/AppIcon.iconset Resources/AppIcon.png

build: $(ICNS)
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	cp $(ICNS) $(APP)/Contents/Resources/
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	codesign --force --deep --sign - $(APP)

run: build
	open $(APP)

install: build
	rm -rf /Applications/$(APP)
	cp -r $(APP) /Applications/
	xattr -cr /Applications/$(APP)
	codesign --force --deep --sign - /Applications/$(APP)
	open /Applications/$(APP)

lint:
	swiftlint lint

clean:
	rm -rf .build $(APP) Resources/AppIcon.iconset Resources/AppIcon.png

.PHONY: build run install clean test

APP_NAME = VoiceInput
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app
INSTALL_DIR = /Applications

build:
	swift build -c release

run: build
	.open $(BUILD_DIR)/$(APP_NAME)

install: build
	@mkdir -p $(INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(INSTALL_DIR)/$(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS/
	cp Info.plist $(INSTALL_DIR)/$(APP_BUNDLE)/Contents/
	codesign --force --deep --sign - --identifier com.voiceinput.app $(INSTALL_DIR)/$(APP_BUNDLE)

clean:
	swift package clean

test:
	swift test

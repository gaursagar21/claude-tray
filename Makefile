.PHONY: build install run clean

APP_NAME    = ClaudeTray
BUILD_DIR   = .build/release
DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer

build:
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift build -c release 2>&1
	@mkdir -p $(APP_NAME).app/Contents/MacOS
	@mkdir -p $(APP_NAME).app/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_NAME).app/Contents/MacOS/
	@cp Info.plist $(APP_NAME).app/Contents/Info.plist
	@echo "✓ Built $(APP_NAME).app"

install: build
	@rm -rf /Applications/$(APP_NAME).app
	@cp -r $(APP_NAME).app /Applications/
	@echo "✓ Installed /Applications/$(APP_NAME).app"

run: build
	@open $(APP_NAME).app

clean:
	@rm -rf .build $(APP_NAME).app

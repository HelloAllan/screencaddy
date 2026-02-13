APP_NAME = ScreenCaddy
BUNDLE_ID = app.screencaddy
EXECUTABLE = ScreenCaddy
BUILD_DIR = .build
BUNDLE_DIR = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR = $(BUNDLE_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

.PHONY: build release bundle dmg dmg-layout dmg-save run clean appstore

build:
	swift build

release:
	swift build -c release

bundle: release
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp "$(BUILD_DIR)/release/$(EXECUTABLE)" "$(MACOS_DIR)/$(EXECUTABLE)"
	chmod +x "$(MACOS_DIR)/$(EXECUTABLE)"
	cp SupportFiles/Info.plist "$(CONTENTS_DIR)/Info.plist"
	GIT_HASH=$$(git rev-parse --short HEAD) && \
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.0.0-$$GIT_HASH" "$(CONTENTS_DIR)/Info.plist"
	cp Assets/Icon.icns "$(RESOURCES_DIR)/AppIcon.icns"
	cp Assets/BackgroundChalk.png "$(RESOURCES_DIR)/BackgroundChalk.png"
	cp Assets/Chalkboard-Regular.ttf "$(RESOURCES_DIR)/Chalkboard-Regular.ttf"
	cp Assets/Arrow1.png "$(RESOURCES_DIR)/Arrow1.png"
	cp Assets/Arrow2.png "$(RESOURCES_DIR)/Arrow2.png"
	codesign --force --deep --options runtime --sign "Developer ID Application" --identifier "$(BUNDLE_ID)" "$(BUNDLE_DIR)"
	@echo "Built $(BUNDLE_DIR)"

PROVISION_PROFILE = $(HOME)/Library/Developer/Xcode/UserData/Provisioning\ Profiles/35d206a0-afac-4ee8-ad5c-b13c8200422b.provisionprofile

appstore: release
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp "$(BUILD_DIR)/release/$(EXECUTABLE)" "$(MACOS_DIR)/$(EXECUTABLE)"
	chmod +x "$(MACOS_DIR)/$(EXECUTABLE)"
	cp SupportFiles/Info.plist "$(CONTENTS_DIR)/Info.plist"
	cp Assets/Icon.icns "$(RESOURCES_DIR)/AppIcon.icns"
	cp Assets/BackgroundChalk.png "$(RESOURCES_DIR)/BackgroundChalk.png"
	cp Assets/Chalkboard-Regular.ttf "$(RESOURCES_DIR)/Chalkboard-Regular.ttf"
	cp Assets/Arrow1.png "$(RESOURCES_DIR)/Arrow1.png"
	cp Assets/Arrow2.png "$(RESOURCES_DIR)/Arrow2.png"
	cp $(PROVISION_PROFILE) "$(CONTENTS_DIR)/embedded.provisionprofile"
	codesign --force --deep --options runtime \
		--sign "Apple Distribution: Allan Dalton (272344XSGR)" \
		--entitlements SupportFiles/ScreenCaddy.entitlements \
		--identifier "$(BUNDLE_ID)" "$(BUNDLE_DIR)"
	productbuild --component "$(BUNDLE_DIR)" /Applications \
		--sign "3rd Party Mac Developer Installer: Allan Dalton (272344XSGR)" \
		"$(BUILD_DIR)/$(APP_NAME).pkg"
	@echo "Built $(BUILD_DIR)/$(APP_NAME).pkg for App Store submission"

dmg: bundle
	./scripts/create-dmg.sh build
	xcrun notarytool submit --keychain-profile "screencaddy" "$(BUILD_DIR)/$(APP_NAME).dmg" --wait
	xcrun stapler staple "$(BUILD_DIR)/$(APP_NAME).dmg"
	mkdir -p ../marketing/public/download
	cp "$(BUILD_DIR)/$(APP_NAME).dmg" ../marketing/public/download/$(APP_NAME).dmg

dmg-layout: bundle
	./scripts/create-dmg.sh layout

dmg-save:
	./scripts/create-dmg.sh save

run: bundle
	open "$(BUNDLE_DIR)"

clean:
	swift package clean
	rm -rf "$(BUNDLE_DIR)"

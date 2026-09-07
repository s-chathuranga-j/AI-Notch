PROJECT := AINotch.xcodeproj
SCHEME := AINotch
DEST := platform=macOS,arch=$(shell uname -m)
BUILD := build
APP := $(BUILD)/Build/Products/Debug/AI Notch.app

.PHONY: gen build test run demo clean

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath $(BUILD) -configuration Debug build

test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath $(BUILD) -configuration Debug test

run: build
	open "$(APP)"

demo: build
	open --env AINOTCH_DEMO=1 "$(APP)"

clean:
	rm -rf build AINotch.xcodeproj

.PHONY: release package

release: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath $(BUILD) -configuration Release build

package: release
	python3 Scripts/package-release.py

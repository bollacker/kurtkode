.PHONY: gen build release install test run open clean cli install-cli

DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/kurtkode.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/kurtkode.app

gen:
	xcodegen generate --quiet

build: gen
	xcodebuild -project kurtkode.xcodeproj -scheme kurtkode -configuration Debug \
		-derivedDataPath $(DERIVED) -quiet build

# The app for everyday use: optimized, without the debug launch hooks.
release: gen
	xcodebuild -project kurtkode.xcodeproj -scheme kurtkode -configuration Release \
		-derivedDataPath $(DERIVED) -quiet build
	@echo "built $(RELEASE_APP)"

# Copies the release build to /Applications. Your chats, endpoints, keys, and settings live outside the app,
# so they carry over. Quit kurtkode first: replacing a running app's files can crash it.
install: release
	@if pgrep -x kurtkode >/dev/null; then echo "kurtkode is running; quit it, then run make install again."; exit 1; fi
	rm -rf /Applications/kurtkode.app
	ditto $(RELEASE_APP) /Applications/kurtkode.app
	@echo "installed /Applications/kurtkode.app"

test:
	cd AgentCore && swift test

run: build
	open $(APP)

open: gen
	open kurtkode.xcodeproj

# The command-line kurtkode (release build).
cli:
	cd AgentCore && swift build -c release --product kurtkode
	@echo "built AgentCore/.build/release/kurtkode"

# Copies it to ~/.local/bin (make sure that's on your PATH), with the bundle that holds its default prompt templates.
install-cli: cli
	mkdir -p $(HOME)/.local/bin
	cp AgentCore/.build/release/kurtkode $(HOME)/.local/bin/kurtkode
	rm -rf $(HOME)/.local/bin/AgentCore_AgentCore.bundle
	cp -R AgentCore/.build/release/AgentCore_AgentCore.bundle $(HOME)/.local/bin/
	@echo "installed $(HOME)/.local/bin/kurtkode"

clean:
	rm -rf build kurtkode.xcodeproj AgentCore/.build

.PHONY: build bundle install uninstall clean

APP_NAME := SyncAgent
BUNDLE   := $(APP_NAME).app
BINARY   := .build/release/$(APP_NAME)

build:
	swift build -c release

bundle: build
	@echo "Assembling $(BUNDLE)..."
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp $(BINARY)              $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist   $(BUNDLE)/Contents/Info.plist
	codesign -f --deep --sign - $(BUNDLE)
	@echo "Bundle ready: $(BUNDLE)"

install: bundle
	@echo "Stopping running instance..."
	-pkill -x $(APP_NAME)
	@sleep 1
	@echo "Installing to /Applications/..."
	rm -rf /Applications/$(BUNDLE)
	cp -r $(BUNDLE) /Applications/$(BUNDLE)
	open /Applications/$(BUNDLE)

uninstall:
	@echo "Uninstalling $(APP_NAME)..."
	-pkill -x $(APP_NAME)
	rm -rf /Applications/$(BUNDLE)
	@echo "Done."

clean:
	rm -rf .build $(BUNDLE)

.PHONY: setup lint fix build release dmg clean

# One-time setup: installs SwiftLint and git hooks
setup:
	@chmod +x Scripts/setup.sh
	@./Scripts/setup.sh

# Run SwiftLint on all Swift files
lint:
	@swiftlint lint --config .swiftlint.yml

# Auto-fix SwiftLint issues where possible
fix:
	@swiftlint lint --fix --config .swiftlint.yml

# Build the project (Debug)
build:
	@xcodebuild -scheme QuotaBar -configuration Debug build | tail -5

# Build for release
release:
	@xcodebuild -scheme QuotaBar -configuration Release build | tail -5

# Build DMG installer
dmg:
	@chmod +x Scripts/build-dmg.sh
	@./Scripts/build-dmg.sh

# Clean build artifacts
clean:
	@xcodebuild -scheme QuotaBar clean 2>/dev/null || true
	@rm -rf DerivedData build
	@echo "✅ Cleaned"

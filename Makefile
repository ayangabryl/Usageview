.PHONY: setup lint fix build release dmg tag clean

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

# Tag and push a release (reads version from Xcode project)
tag:
	@VERSION=$$(grep 'MARKETING_VERSION' QuotaBar.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //' | sed 's/;//' | tr -d '[:space:]') && \
	if git rev-parse "v$$VERSION" >/dev/null 2>&1; then \
		echo "❌ Tag v$$VERSION already exists. Bump MARKETING_VERSION in Xcode first."; \
		exit 1; \
	fi && \
	echo "🏷  Tagging v$$VERSION..." && \
	git tag "v$$VERSION" && \
	git push origin "v$$VERSION" && \
	echo "✅ Pushed v$$VERSION — GitHub Actions will build the release" && \
	echo "   👉 https://github.com/ayangabryl/QuotaBar/releases"

# Clean build artifacts
clean:
	@xcodebuild -scheme QuotaBar clean 2>/dev/null || true
	@rm -rf DerivedData build
	@echo "✅ Cleaned"

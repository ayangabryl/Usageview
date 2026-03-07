.PHONY: setup lint fix build release dmg tag clean notarize-status staple

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
	@xcodebuild -scheme Usageview -configuration Debug build | tail -5

# Build DMG installer (ad-hoc signed, no notarization)
dmg:
	@chmod +x Scripts/build-dmg.sh
	@./Scripts/build-dmg.sh

# Build signed + notarized DMG and publish as GitHub Release
# Prerequisites: gh auth login, Apple credentials in env
release:
	@if ! command -v gh >/dev/null 2>&1; then \
		echo "❌ GitHub CLI not found. Install with: brew install gh"; \
		exit 1; \
	fi
	@VERSION=$$(grep 'MARKETING_VERSION' Usageview.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //' | sed 's/;//' | tr -d '[:space:]') && \
	DMG="build/Usageview-$${VERSION}.dmg" && \
	echo "🚀 Building Usageview v$${VERSION} release..." && \
	\
	export CODE_SIGN_IDENTITY="Developer ID Application: Ian Gabriel Agujitas (MZRACJ7Z64)" && \
	export TEAM_ID="MZRACJ7Z64" && \
	chmod +x Scripts/build-dmg.sh && \
	./Scripts/build-dmg.sh && \
	\
	echo "📦 Creating GitHub Release v$${VERSION}..." && \
	if git rev-parse "v$${VERSION}" >/dev/null 2>&1; then \
		echo "   Tag v$${VERSION} already exists, using it"; \
	else \
		git tag "v$${VERSION}" && \
		git push origin "v$${VERSION}"; \
	fi && \
	gh release create "v$${VERSION}" "$$DMG" \
		--title "Usageview v$${VERSION}" \
		--generate-notes && \
	echo "" && \
	echo "✅ Release published!" && \
	echo "   👉 https://github.com/ayangabryl/Usageview/releases/tag/v$${VERSION}"

# Tag and push (without building — useful for CI-only releases)
tag:
	@VERSION=$$(grep 'MARKETING_VERSION' Usageview.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //' | sed 's/;//' | tr -d '[:space:]') && \
	if git rev-parse "v$$VERSION" >/dev/null 2>&1; then \
		echo "❌ Tag v$$VERSION already exists. Bump MARKETING_VERSION in Xcode first."; \
		exit 1; \
	fi && \
	echo "🏷  Tagging v$$VERSION..." && \
	git tag "v$$VERSION" && \
	git push origin "v$$VERSION" && \
	echo "✅ Pushed v$$VERSION" && \
	echo "   👉 https://github.com/ayangabryl/Usageview/releases"

# Check notarization status
notarize-status:
	@xcrun notarytool history \
		--apple-id "$${APPLE_ID}" \
		--password "$${APPLE_APP_PASSWORD}" \
		--team-id "$${TEAM_ID}" 2>&1 | head -20

# Staple notarization ticket and re-upload to GitHub Release
staple:
	@VERSION=$$(grep 'MARKETING_VERSION' Usageview.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //' | sed 's/;//' | tr -d '[:space:]') && \
	DMG="build/Usageview-$${VERSION}.dmg" && \
	echo "📎 Stapling notarization ticket to $${DMG}..." && \
	xcrun stapler staple "$$DMG" && \
	echo "📦 Re-uploading stapled DMG to GitHub Release v$${VERSION}..." && \
	gh release upload "v$${VERSION}" "$$DMG" --clobber && \
	echo "✅ Done! Release is fully notarized and stapled." && \
	echo "   👉 https://github.com/ayangabryl/Usageview/releases/tag/v$${VERSION}"

# Clean build artifacts
clean:
	@xcodebuild -scheme Usageview clean 2>/dev/null || true
	@rm -rf DerivedData build
	@echo "✅ Cleaned"

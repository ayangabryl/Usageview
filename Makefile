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

# Build signed + notarized DMG, sign for Sparkle, update appcast, publish GitHub Release
# All in one step — just run: make release
# Prerequisites: gh auth login, Apple credentials in env
release:
	@if ! command -v gh >/dev/null 2>&1; then \
		echo "❌ GitHub CLI not found. Install with: brew install gh"; \
		exit 1; \
	fi
	@VERSION=$$(grep 'MARKETING_VERSION' Usageview.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //' | sed 's/;//' | tr -d '[:space:]') && \
	DMG="build/Usageview-$${VERSION}.dmg" && \
	echo "" && \
	echo "╔══════════════════════════════════════════════════╗" && \
	echo "║       Usageview Release — v$${VERSION}              ║" && \
	echo "║       Single-step: build → sign → publish        ║" && \
	echo "╚══════════════════════════════════════════════════╝" && \
	echo "" && \
	\
	echo "── Step 1/6: Building & creating DMG ──────────────" && \
	export CODE_SIGN_IDENTITY="Developer ID Application: Ian Gabriel Agujitas (MZRACJ7Z64)" && \
	export TEAM_ID="MZRACJ7Z64" && \
	if [ -z "$${APPLE_ID}" ] || [ -z "$${APPLE_APP_PASSWORD}" ]; then \
		echo "❌ APPLE_ID and APPLE_APP_PASSWORD must be set for notarization"; \
		echo "   export APPLE_ID=you@example.com"; \
		echo "   export APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx  (app-specific password)"; \
		exit 1; \
	fi && \
	export APPLE_ID="$${APPLE_ID}" && \
	export APPLE_APP_PASSWORD="$${APPLE_APP_PASSWORD}" && \
	chmod +x Scripts/build-dmg.sh && \
	./Scripts/build-dmg.sh && \
	\
	echo "── Step 2/6: Signing DMG with EdDSA (Sparkle) ─────" && \
	SPARKLE_BIN=$$(find ~/Library/Developer/Xcode/DerivedData/Usageview-*/SourcePackages/artifacts/sparkle/Sparkle/bin -maxdepth 0 -type d 2>/dev/null | head -1) && \
	if [ -z "$$SPARKLE_BIN" ]; then \
		echo "❌ Sparkle bin not found. Build the project in Xcode first."; \
		exit 1; \
	fi && \
	SIGN_OUTPUT=$$("$$SPARKLE_BIN/sign_update" "$$DMG") && \
	echo "   $$SIGN_OUTPUT" && \
	ED_SIGNATURE=$$(echo "$$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"//') && \
	DMG_LENGTH=$$(echo "$$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | sed 's/length="//;s/"//') && \
	if [ -z "$$ED_SIGNATURE" ] || [ -z "$$DMG_LENGTH" ]; then \
		echo "❌ Failed to extract EdDSA signature"; \
		exit 1; \
	fi && \
	echo "   ✅ EdDSA signature obtained" && \
	\
	echo "── Step 3/6: Generating appcast.xml ────────────────" && \
	DOWNLOAD_URL="https://github.com/ayangabryl/Usageview/releases/download/v$${VERSION}/Usageview-$${VERSION}.dmg" && \
	BUILD_NUMBER=$$(grep 'CURRENT_PROJECT_VERSION' Usageview.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //' | sed 's/;//' | tr -d '[:space:]') && \
	PUB_DATE=$$(date -R) && \
	printf '<?xml version="1.0" encoding="utf-8"?>\n<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">\n  <channel>\n    <title>Usageview Updates</title>\n    <link>https://raw.githubusercontent.com/ayangabryl/Usageview/main/appcast.xml</link>\n    <description>Most recent changes with links to updates.</description>\n    <language>en</language>\n    <item>\n      <title>Version %s</title>\n      <pubDate>%s</pubDate>\n      <sparkle:version>%s</sparkle:version>\n      <sparkle:shortVersionString>%s</sparkle:shortVersionString>\n      <enclosure\n        url="%s"\n        sparkle:edSignature="%s"\n        length="%s"\n        type="application/octet-stream" />\n    </item>\n  </channel>\n</rss>\n' \
	"$$VERSION" "$$PUB_DATE" "$$BUILD_NUMBER" "$$VERSION" "$$DOWNLOAD_URL" "$$ED_SIGNATURE" "$$DMG_LENGTH" > appcast.xml && \
	echo "   ✅ appcast.xml updated" && \
	\
	echo "── Step 4/6: Committing appcast.xml ────────────────" && \
	git add appcast.xml && \
	git commit -m "Update appcast.xml for v$${VERSION}" --allow-empty && \
	git push origin main && \
	echo "   ✅ appcast.xml pushed to main" && \
	\
	echo "── Step 5/6: Creating GitHub Release ───────────────" && \
	if git rev-parse "v$${VERSION}" >/dev/null 2>&1; then \
		echo "   Tag v$${VERSION} already exists, using it"; \
	else \
		git tag "v$${VERSION}" && \
		git push origin "v$${VERSION}"; \
	fi && \
	gh release create "v$${VERSION}" "$$DMG" \
		--title "Usageview v$${VERSION}" \
		--generate-notes && \
	\
	echo "" && \
	echo "═══════════════════════════════════════════════════" && \
	echo "  ✅ Release v$${VERSION} published!" && \
	echo "  📦 DMG:      $$DMG" && \
	echo "  🔑 Sparkle:  EdDSA signed" && \
	echo "  🍎 Apple:    Notarized & stapled" && \
	echo "  📡 Appcast:  Updated & pushed" && \
	echo "  🐙 Release:  https://github.com/ayangabryl/Usageview/releases/tag/v$${VERSION}" && \
	echo "═══════════════════════════════════════════════════"

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

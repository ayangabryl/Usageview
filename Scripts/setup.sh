#!/bin/bash
# Setup script for QuotaBar development environment
# Run this once after cloning: ./Scripts/setup.sh

set -e

echo "🚀 Setting up QuotaBar development environment..."
echo ""

# Install SwiftLint if not present
if command -v swiftlint &> /dev/null; then
    echo "✅ SwiftLint installed ($(swiftlint version))"
else
    echo "📦 Installing SwiftLint..."
    brew install swiftlint
    echo "✅ SwiftLint installed"
fi

echo ""

# Install git hooks
echo "🔗 Installing git hooks..."
HOOKS_DIR="$(git rev-parse --git-dir)/hooks"
cp Scripts/pre-commit "$HOOKS_DIR/pre-commit"
cp Scripts/commit-msg "$HOOKS_DIR/commit-msg"
chmod +x "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/commit-msg"
echo "✅ Pre-commit hook installed (SwiftLint)"
echo "✅ Commit-msg hook installed (Conventional Commits)"

echo ""
echo "🎉 Setup complete! You're ready to contribute."
echo ""
echo "Quick commands:"
echo "  make lint      — Run SwiftLint"
echo "  make fix       — Auto-fix lint issues"  
echo "  make build     — Build the project"
echo "  make clean     — Clean build artifacts"

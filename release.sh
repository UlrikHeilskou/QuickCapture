#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

VERSION=$(grep 'appVersion' "$PROJECT_DIR/Sources/AppConfig.swift" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$VERSION" ]; then
  VERSION="1.1.1000"
fi

TAG="v$VERSION"
ZIP_NAME="QuickCapture_macOS_${TAG}.zip"
BUILD_DIR="$PROJECT_DIR/build"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
REPO="UlrikHeilskou/QuickCapture"
TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "$PROJECT_DIR/.github_token" ]; then
  TOKEN=$(cat "$PROJECT_DIR/.github_token" | tr -d '[:space:]')
elif [ -z "$TOKEN" ] && [ -f "$HOME/.github_token" ]; then
  TOKEN=$(cat "$HOME/.github_token" | tr -d '[:space:]')
fi

echo "=========================================================="
echo "🚀 Releasing QuickCapture $TAG to GitHub"
echo "Repository: https://github.com/$REPO"
echo "=========================================================="

# 1. Regenerate project if needed
xcodegen generate

# 2. Build Release using xcodebuild
echo "1. Building Release configuration..."
xcodebuild -project QuickCapture.xcodeproj -scheme QuickCapture -configuration Release -derivedDataPath "$BUILD_DIR/DerivedData" build

APP_BUNDLE="$BUILD_DIR/DerivedData/Build/Products/Release/QuickCapture.app"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "Error: Built app bundle not found at $APP_BUNDLE"
  exit 1
fi

# 3. Create Release Zip archive
echo "2. Compressing application for distribution..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR/DerivedData/Build/Products/Release"
rm -f "$ZIP_PATH"
zip -r -q "$ZIP_PATH" "QuickCapture.app"
cd "$PROJECT_DIR"

echo "Created zip: $ZIP_PATH"

# 4. Install locally in /Applications
echo "3. Installing locally to /Applications/QuickCapture.app..."
killall QuickCapture 2>/dev/null || true
rm -rf "/Applications/QuickCapture.app" 2>/dev/null || true
cp -R "$APP_BUNDLE" "/Applications/QuickCapture.app"
codesign --force --deep --sign - --timestamp=none "/Applications/QuickCapture.app" 2>/dev/null || true

# 5. Git Commit and Tag
echo "4. Committing code changes for $TAG..."
git remote set-url origin "https://UlrikHeilskou:${TOKEN}@github.com/${REPO}.git" 2>/dev/null || true
git add .
git commit -m "Release $TAG — Customizable hotkeys & Auto-updater" || true
git tag -f "$TAG"

echo "5. Pushing code & tags to GitHub..."
git push origin main
git push origin "$TAG" -f

# 6. Create GitHub Release and Upload Asset via API
echo "6. Publishing GitHub Release $TAG..."
RELEASE_JSON=$(curl -s -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/$REPO/releases \
  -d "{\"tag_name\":\"$TAG\",\"name\":\"QuickCapture $TAG\",\"body\":\"Release $TAG with customizable shortcuts and automatic updater support.\",\"draft\":false,\"prerelease\":false}")

UPLOAD_URL=$(echo "$RELEASE_JSON" | grep '"upload_url"' | sed -E 's/.*"upload_url": "([^"{]+).*/\1/')

if [ -z "$UPLOAD_URL" ]; then
  RELEASE_JSON=$(curl -s -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/$REPO/releases/tags/$TAG)
  UPLOAD_URL=$(echo "$RELEASE_JSON" | grep '"upload_url"' | sed -E 's/.*"upload_url": "([^"{]+).*/\1/')
fi

if [ -n "$UPLOAD_URL" ]; then
  echo "7. Uploading zip asset to GitHub..."
  curl -s -X POST -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/zip" \
    --data-binary @"$ZIP_PATH" \
    "${UPLOAD_URL}?name=${ZIP_NAME}" > /dev/null
  echo "Asset uploaded successfully!"
else
  echo "Warning: Could not get upload_url for GitHub release."
fi

# 7. Restart app
open /Applications/QuickCapture.app

echo "=========================================================="
echo "✅ Release $TAG successfully deployed to GitHub!"
echo "Your other Mac computers can now automatically update to $TAG!"
echo "=========================================================="

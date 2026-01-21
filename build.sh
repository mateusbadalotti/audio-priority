#!/bin/bash
set -e

echo "Building AudioPriority..."

xcodebuild -scheme audio-priority \
  -configuration Release \
  -derivedDataPath .build \
  -arch arm64 -arch x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

mkdir -p dist
rm -rf dist/AudioPriority.app
cp -R .build/Build/Products/Release/AudioPriority.app dist/

echo ""
echo "Build complete: dist/AudioPriority.app"

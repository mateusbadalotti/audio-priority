#!/bin/bash
set -e

echo "Building AudioPriority..."

xcodebuild -scheme audio-priority \
  -configuration Release \
  -derivedDataPath .build \
  -arch arm64 -arch x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  build

mkdir -p dist
rm -rf dist/AudioPriority.app
cp -R .build/Build/Products/Release/AudioPriority.app dist/
codesign --verify --deep --strict dist/AudioPriority.app

echo ""
echo "Build complete: dist/AudioPriority.app"

#!/bin/bash
set -e
DEVICE="${1:-iPhone 17 Pro}"
xcodebuild -project Settlr.xcodeproj -scheme Settlr \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -configuration Debug -derivedDataPath build build
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Settlr.app
xcrun simctl launch booted com.settlr.app

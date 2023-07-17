#!/usr/bin/env sh

set -euxo pipefail

xcodebuild -project "Xcode Project/ProcessServiceExample.xcodeproj" -scheme ProcessServiceContainer -destination "platform=macOS" -derivedDataPath DerivedData -configuration Release build

PRODUCTS_PATH="$PWD/DerivedData/Build/Products/Release"
FRAMEWORK_PATH="$PRODUCTS_PATH/ProcessServiceContainer.framework"
OUTPUT_PATH="ProcessServiceContainer.xcframework"

rm -rf "$OUTPUT_PATH"
xcodebuild -create-xcframework -framework "$FRAMEWORK_PATH" -output "$OUTPUT_PATH"

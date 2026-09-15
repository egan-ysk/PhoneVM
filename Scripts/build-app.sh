#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PhoneVM"
BUNDLE_ID="dev.egan.phonevm"
BUNDLE_VERSION="${BUNDLE_VERSION:-0.4.0}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_FILE="AppIcon.icns"

cd "$ROOT_DIR"
if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
    # 发布产物不保留构建机器的源码绝对路径。
    swift build -c release -Xswiftc -gnone -Xswiftc -file-prefix-map -Xswiftc "$ROOT_DIR=/PhoneVM"
else
    swift build -c "$BUILD_CONFIGURATION"
fi

EXECUTABLE_PATH="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)/PhoneVM"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/PhoneVM"

if [[ -f "$ROOT_DIR/Resources/$ICON_FILE" ]]; then
    cp "$ROOT_DIR/Resources/$ICON_FILE" "$RESOURCES_DIR/$ICON_FILE"
else
    echo "warning: 未找到 Resources/$ICON_FILE，将生成无图标的应用包" >&2
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>PhoneVM</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$BUNDLE_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUNDLE_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>将您选择的设备截屏保存到桌面。</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Egan</string>
</dict>
</plist>
PLIST

if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
    strip -S "$MACOS_DIR/PhoneVM"
    codesign --force --sign - "$APP_DIR"
fi

echo "$APP_DIR"

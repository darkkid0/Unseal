#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-io.github.darkkid0.Unseal}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"
NOTARYTOOL_KEYCHAIN="${NOTARYTOOL_KEYCHAIN:-}"
NOTARYTOOL_TIMEOUT="${NOTARYTOOL_TIMEOUT:-30m}"

echo "==> 项目根目录：$ROOT_DIR"

if [ ! -f "$ROOT_DIR/Package.swift" ]; then
    echo "未找到 Package.swift，请在项目根目录运行此脚本。" >&2
    exit 1
fi

APP_ICON="$ROOT_DIR/Sources/AppModule/Resources/AppIcon.icns"
if [ ! -f "$APP_ICON" ]; then
    echo "未找到 AppIcon.icns，请先运行 ./generate_app_icon.sh。" >&2
    exit 1
fi

if ! command -v lipo >/dev/null 2>&1; then
    echo "缺少 lipo 命令，请安装 Xcode Command Line Tools。" >&2
    exit 1
fi

for command in codesign plutil; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "缺少 $command 命令，请安装 Xcode Command Line Tools。" >&2
        exit 1
    fi
done

echo "==> 清理构建缓存..."
swift package clean >/dev/null 2>&1 || true
BUILD_DIR="$ROOT_DIR/.build"
if [ -d "$BUILD_DIR" ]; then
    case "$BUILD_DIR" in
        */.build)
            rm -rf "$BUILD_DIR"
            ;;
        *)
            echo "检测到异常构建目录：$BUILD_DIR，已跳过自动删除，请手动检查。" >&2
            exit 1
            ;;
    esac
fi

echo "==> 构建 release 版本 (arm64)..."
swift build --configuration release --arch arm64

echo "==> 构建 release 版本 (x86_64)..."
swift build --configuration release --arch x86_64

ARM64_BIN="$ROOT_DIR/.build/arm64-apple-macosx/release/Unseal"
X86_BIN="$ROOT_DIR/.build/x86_64-apple-macosx/release/Unseal"
UNIVERSAL_BIN="$ROOT_DIR/.build/release/Unseal"

for binary in "$ARM64_BIN" "$X86_BIN"; do
    if [ ! -f "$binary" ]; then
        echo "缺少构建产物：$binary" >&2
        exit 1
    fi
done

mkdir -p "$(dirname "$UNIVERSAL_BIN")"

echo "==> 合并通用可执行文件..."
lipo -create "$ARM64_BIN" "$X86_BIN" -output "$UNIVERSAL_BIN"
ARCH_INFO="$(lipo -info "$UNIVERSAL_BIN" 2>/dev/null || true)"
echo "    $ARCH_INFO"

APP_DIR="$ROOT_DIR/.build/release/Unseal.app"

echo "==> 打包 Unseal.app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$UNIVERSAL_BIN" "$APP_DIR/Contents/MacOS/Unseal"
cp "$APP_ICON" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Unseal</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Unseal</string>
    <key>CFBundleDisplayName</key>
    <string>Unseal</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$MARKETING_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "==> 使用 Developer ID 签名：$SIGNING_IDENTITY"
    codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$APP_DIR"
else
    echo "==> 未配置 SIGNING_IDENTITY，执行本机 ad-hoc 签名..."
    codesign --force --deep --sign - "$APP_DIR"
fi

codesign --verify --deep --strict "$APP_DIR"

if [ -n "$NOTARYTOOL_PROFILE" ]; then
    if [ -z "$SIGNING_IDENTITY" ]; then
        echo "使用 NOTARYTOOL_PROFILE 时必须同时配置 SIGNING_IDENTITY。" >&2
        exit 1
    fi

    ARCHIVE_PATH="$ROOT_DIR/.build/release/Unseal.zip"
    NOTARYTOOL_ARGS=(--keychain-profile "$NOTARYTOOL_PROFILE")
    if [ -n "$NOTARYTOOL_KEYCHAIN" ]; then
        NOTARYTOOL_ARGS+=(--keychain "$NOTARYTOOL_KEYCHAIN")
    fi

    echo "==> 提交 Apple 公证..."
    ditto -c -k --keepParent "$APP_DIR" "$ARCHIVE_PATH"
    xcrun notarytool submit \
        "$ARCHIVE_PATH" \
        "${NOTARYTOOL_ARGS[@]}" \
        --wait \
        --timeout "$NOTARYTOOL_TIMEOUT"
    xcrun stapler staple "$APP_DIR"
fi

echo "==> 完成：$APP_DIR"

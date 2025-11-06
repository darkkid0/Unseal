#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

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

HOST_ARCH="$(uname -m)"
if [ "$HOST_ARCH" = "x86_64" ]; then
    echo "当前主机为 x86_64，暂不支持在 Intel 上构建 arm64 版本，请在 Apple Silicon 设备上运行此脚本。" >&2
    exit 1
fi

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
if arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    arch -x86_64 swift build --configuration release --arch x86_64
else
    echo "Rosetta 未安装或 arch -x86_64 不可用，请先安装 Rosetta 再重试。" >&2
    exit 1
fi

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

cat > "$APP_DIR/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Unseal</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.Unseal</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Unseal</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

copy_resources_if_present() {
    local src="$1"
    if [ -d "$src" ] && [ "$(ls -A "$src")" ]; then
        echo "==> 拷贝资源文件来自 $(dirname "$src")..."
        cp -R "$src"/. "$APP_DIR/Contents/Resources"
    fi
}

copy_resources_if_present "$ROOT_DIR/.build/arm64-apple-macosx/release/Unseal_AppModule.bundle/Resources"
copy_resources_if_present "$ROOT_DIR/.build/x86_64-apple-macosx/release/Unseal_AppModule.bundle/Resources"

echo "==> 完成：$APP_DIR"

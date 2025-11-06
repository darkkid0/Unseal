#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

find_icon_dir() {
    local provided="$1"
    if [ -n "$provided" ]; then
        if [ -d "$provided" ]; then
            printf '%s\n' "$(cd "$provided" && pwd)"
            return 0
        fi
        if [ -d "$ROOT_DIR/$provided" ]; then
            printf '%s\n' "$(cd "$ROOT_DIR/$provided" && pwd)"
            return 0
        fi
        return 1
    fi

    local candidates=("$ROOT_DIR/icon" "$ROOT_DIR/icons/macos" "$ROOT_DIR/icons")
    for path in "${candidates[@]}"; do
        if [ -d "$path" ]; then
            printf '%s\n' "$path"
            return 0
        fi
    done
    return 1
}

ICON_SRC_DIR="$(find_icon_dir "${1:-}")" || {
    echo "未找到图标目录，请在项目内创建 icon/ 或 icons/macos/ 并放置底图。" >&2
    exit 1
}

BASE_ICON="$ICON_SRC_DIR/1024.png"
if [ ! -f "$BASE_ICON" ]; then
    echo "缺少基础图标：$BASE_ICON" >&2
    exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
    echo "缺少 sips 命令，macOS 默认提供，请检查系统环境。" >&2
    exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
    echo "缺少 iconutil 命令，请安装 Xcode Command Line Tools。" >&2
    exit 1
fi

ICONSET_DIR="$ROOT_DIR/AppIcon.iconset"
OUTPUT_PATH="$ROOT_DIR/Sources/AppModule/Resources/AppIcon.icns"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
mkdir -p "$(dirname "$OUTPUT_PATH")"

cleanup() {
    rm -rf "$ICONSET_DIR"
}
trap cleanup EXIT

write_icon() {
    local dimension="$1"
    local target="$2"
    local candidate="$ICON_SRC_DIR/${dimension}.png"

    local source="$BASE_ICON"
    if [ -f "$candidate" ]; then
        source="$candidate"
    fi

    sips -s format png -z "$dimension" "$dimension" "$source" --out "$ICONSET_DIR/$target" >/dev/null
}

write_icon 16   icon_16x16.png
write_icon 32   icon_16x16@2x.png
write_icon 32   icon_32x32.png
write_icon 64   icon_32x32@2x.png
write_icon 128  icon_128x128.png
write_icon 256  icon_128x128@2x.png
write_icon 256  icon_256x256.png
write_icon 512  icon_256x256@2x.png
write_icon 512  icon_512x512.png
write_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_PATH"

trap - EXIT
cleanup

echo "已生成 ${OUTPUT_PATH}（来源目录：${ICON_SRC_DIR}）"

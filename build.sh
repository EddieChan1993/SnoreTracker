#!/usr/bin/env bash
# SnoreTracker build script
# Usage:
#   bash build.sh          # 全量打包（模拟器 Release，导出 .app）
#   bash build.sh --dev    # 开发模式（模拟器 Debug，直接启动）

set -e

APP_NAME="SnoreTracker"
SCHEME="SnoreTracker"
PROJECT="SnoreTracker.xcodeproj"
SIMULATOR="iPhone 16"          # 没有真机时用模拟器
DEV_MODE=false
[[ "$1" == "--dev" ]] && DEV_MODE=true

# ── 1. 生成/刷新 Xcode 项目 ──────────────────────────────────────────────────
if command -v xcodegen &>/dev/null; then
    echo "🔧 xcodegen generate ..."
    xcodegen generate --quiet
else
    echo "⚠️  xcodegen 未安装，跳过项目生成（brew install xcodegen）"
fi

# ── 2. 构建 ──────────────────────────────────────────────────────────────────
SIM_ID=$(xcrun simctl list devices available -j \
    | python3 -c "
import json,sys
devs=json.load(sys.stdin)['devices']
for rt,dl in devs.items():
    for d in dl:
        if d['state']=='Booted' or '${SIMULATOR}' in d['name']:
            print(d['udid']); exit()
" 2>/dev/null | head -1)

if $DEV_MODE; then
    echo "📱 开发模式：构建到模拟器 (Debug) ..."
    CONFIG="Debug"
else
    echo "📦 全量模式：构建到模拟器 (Release) ..."
    CONFIG="Release"
fi

BUILD_DIR="$(pwd)/.build/${CONFIG}"
mkdir -p "$BUILD_DIR"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=${SIMULATOR}" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    build 2>&1 | grep -E "(error:|warning:|Build succeeded|Build FAILED|Compiling|Linking)" || true

APP_PATH="${BUILD_DIR}/${APP_NAME}.app"

# ── 3. 启动模拟器并安装 ───────────────────────────────────────────────────────
if [ -d "$APP_PATH" ]; then
    echo "🚀 安装并启动 ${APP_NAME} ..."

    # 启动模拟器（如果未运行）
    if [ -n "$SIM_ID" ]; then
        xcrun simctl boot "$SIM_ID" 2>/dev/null || true
    else
        # 找到第一个可用设备并启动
        SIM_ID=$(xcrun simctl list devices available -j \
            | python3 -c "
import json,sys
devs=json.load(sys.stdin)['devices']
for rt,dl in devs.items():
    for d in dl:
        if '${SIMULATOR}' in d['name']:
            print(d['udid']); exit()
")
        xcrun simctl boot "$SIM_ID" 2>/dev/null || true
    fi

    open -a Simulator 2>/dev/null || true
    sleep 2

    # 卸载旧版，安装新版
    xcrun simctl uninstall "$SIM_ID" "com.eddiechan.snoretracker.ec2024" 2>/dev/null || true
    xcrun simctl install "$SIM_ID" "$APP_PATH"
    xcrun simctl launch "$SIM_ID" "com.eddiechan.snoretracker.ec2024"

    echo "✅ 启动成功！"
else
    echo "❌ 未找到 .app，请检查构建错误"
    exit 1
fi

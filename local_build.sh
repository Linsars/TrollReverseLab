#!/bin/bash
#
# local_build.sh — 在本地 Mac 上一键构建 TrollReverseLab IPA
#
# 前置要求:
#   - macOS 14+ (Apple Silicon 或 Intel)
#   - Xcode 15+
#   - Homebrew
#   - xcodegen (brew install xcodegen)
#   - ldid (brew install ldid)
#
# 使用方法:
#   chmod +x local_build.sh
#   ./local_build.sh
#

set -e

APP_NAME="TrollReverseLab"
SCHEME="TrollReverseLab"
CONFIGURATION="Release"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== TrollReverseLab 本地一键构建 ===${NC}"

# Step 1: Check prerequisites
echo -e "${GREEN}[1/7] 检查前置依赖...${NC}"

if ! command -v xcodegen &>/dev/null; then
    echo -e "${YELLOW}xcodegen 未安装，正在通过 brew 安装...${NC}"
    brew install xcodegen
fi

if ! command -v ldid &>/dev/null; then
    echo -e "${YELLOW}ldid 未安装，正在通过 brew 安装...${NC}"
    brew install ldid
fi

if ! command -v xcodebuild &>/dev/null; then
    echo -e "${RED}xcodebuild 未找到，请确保 Xcode 已安装${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ xcodegen${NC}"
echo -e "${GREEN}  ✓ ldid${NC}"
echo -e "${GREEN}  ✓ xcodebuild${NC}"

# Step 2: Generate Xcode project
echo -e "${GREEN}[2/7] 用 xcodegen 生成 Xcode 项目...${NC}"
xcodegen generate
echo -e "${GREEN}  ✓ TrollReverseLab.xcodeproj 已生成${NC}"

# Step 3: Build
echo -e "${GREEN}[3/7] 编译应用...${NC}"
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -sdk iphoneos \
    -derivedDataPath build/DerivedData \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

# Step 4: Find app bundle
echo -e "${GREEN}[4/7] 定位编译产物...${NC}"
APP_PATH=$(find build/DerivedData -name "${APP_NAME}.app" -path "*/Release-iphoneos/*" | head -1)

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}错误: 未找到 .app bundle${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ ${APP_PATH}${NC}"

# Step 5: Inject entitlements
echo -e "${GREEN}[5/7] 注入调试权限 (ldid)...${NC}"
ENTITLEMENTS="TrollReverseLab/TrollReverseLab.entitlements"
ldid -S"$ENTITLEMENTS" "$APP_PATH/$APP_NAME"

echo -e "${GREEN}  ✓ 权限已注入${NC}"

# Verify entitlements
echo -e "${YELLOW}  已注入权限:${NC}"
ldid -e "$APP_PATH/$APP_NAME" | grep -E "(allow-jit|disable-library|no-sandbox|get-task-allow|platform-application)" | while read line; do
    echo -e "${GREEN}    ✓ $line${NC}"
done

# Step 6: Package IPA
echo -e "${GREEN}[6/7] 打包 IPA...${NC}"
rm -rf build/Payload
mkdir -p build/Payload
cp -R "$APP_PATH" build/Payload/

rm -f build/${APP_NAME}.ipa
cd build
zip -r "${APP_NAME}.ipa" Payload/ -x "*.DS_Store"
cd ..

IPA_PATH="build/${APP_NAME}.ipa"
echo -e "${GREEN}  ✓ IPA 已生成: ${IPA_PATH}${NC}"

# Step 7: Generate checksum
echo -e "${GREEN}[7/7] 生成校验信息...${NC}"
shasum -a 256 "$IPA_PATH" > build/ipa_checksum.txt
IPA_SIZE=$(du -h "$IPA_PATH" | cut -f1)

echo ""
echo -e "${GREEN}=== 构建完成 ===${NC}"
echo -e "IPA 文件: ${IPA_PATH}"
echo -e "IPA 大小: ${IPA_SIZE}"
echo -e "SHA256:   $(cat build/ipa_checksum.txt)"
echo ""
echo -e "${YELLOW}安装方式:${NC}"
echo -e "  1. 将 IPA 文件传输到 iOS 设备"
echo -e "  2. 打开 TrollStore"
echo -e "  3. 点击 '+' 按钮选择 IPA 文件"
echo -e "  4. TrollStore 自动安装（保留注入权限）"
echo ""
echo -e "${YELLOW}⚠️ 仅用于个人本地 iOS 逆向学习研究${NC}"

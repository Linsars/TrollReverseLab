#!/bin/bash
#
# build_ipa.sh — TrollReverseLab IPA packaging script
#
# Injects debug entitlements, packages the .app into an IPA,
# and prepares it for TrollStore installation.
#
# CONSTRAINT: This tool is for personal local iOS reverse engineering
# learning only. Not for commercial cracking or distribution.
#

set -e

# Configuration
APP_NAME="TrollReverseLab"
SCHEME="TrollReverseLab"
CONFIGURATION="Release"
ENTITLEMENTS_FILE="TrollReverseLab/TrollReverseLab.entitlements"
OUTPUT_DIR="build"
IPA_NAME="TrollReverseLab.ipa"
LDID_PATH="/usr/local/bin/ldid"  # or /opt/homebrew/bin/ldid

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== TrollReverseLab IPA Build Script ===${NC}"
echo -e "${YELLOW}For personal local iOS reverse engineering learning only${NC}"
echo ""

# Step 1: Build the app
echo -e "${GREEN}[1/6] Building app with xcodebuild...${NC}"
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -sdk iphoneos \
    -derivedDataPath "${OUTPUT_DIR}/DerivedData" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_PATH=$(find "${OUTPUT_DIR}/DerivedData" -name "${APP_NAME}.app" -path "*/Release-iphoneos/*" | head -1)

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}Error: Could not find built .app bundle${NC}"
    exit 1
fi

echo -e "${GREEN}Found app at: ${APP_PATH}${NC}"

# Step 2: Inject frida-gadget if not present
echo -e "${GREEN}[2/6] Checking frida-gadget integration...${NC}"
GADGET_PATH="${APP_PATH}/Frameworks/FridaGadget.framework"
if [ ! -d "$GADGET_PATH" ]; then
    echo -e "${YELLOW}FridaGadget.framework not found. Please add it manually or run the gadget setup script.${NC}"
    echo -e "${YELLOW}Download from: https://github.com/frida/frida/releases${NC}"
else
    echo -e "${GREEN}FridaGadget.framework found.${NC}"
fi

# Step 3: Apply entitlements using ldid
echo -e "${GREEN}[3/6] Applying debug entitlements with ldid...${NC}"
if [ ! -f "$LDID_PATH" ]; then
    echo -e "${RED}Error: ldid not found at ${LDID_PATH}${NC}"
    echo -e "${YELLOW}Install with: brew install ldid${NC}"
    exit 1
fi

# Create entitlements plist for ldid format
ldid -e "${APP_PATH}/${APP_NAME}" > "${OUTPUT_DIR}/original_entitlements.plist" 2>/dev/null || true

# Inject our entitlements
cp "${ENTITLEMENTS_FILE}" "${OUTPUT_DIR}/debug_entitlements.plist"
"$LDID_PATH" -S"${OUTPUT_DIR}/debug_entitlements.plist" "${APP_PATH}/${APP_NAME}"

echo -e "${GREEN}Entitlements injected.${NC}"

# Step 4: Verify entitlements
echo -e "${GREEN}[4/6] Verifying injected entitlements...${NC}"
ldid -e "${APP_PATH}/${APP_NAME}" > "${OUTPUT_DIR}/applied_entitlements.plist"

# Check for key entitlements
ENTITLEMENTS_CONTENT=$(cat "${OUTPUT_DIR}/applied_entitlements.plist")
for key in "allow-jit" "disable-library-validation" "no-sandbox" "get-task-allow"; do
    if echo "$ENTITLEMENTS_CONTENT" | grep -q "$key"; then
        echo -e "  ${GREEN}✓ ${key}${NC}"
    else
        echo -e "  ${RED}✗ ${key} missing${NC}"
    fi
done

# Step 5: Package into IPA
echo -e "${GREEN}[5/6] Packaging IPA...${NC}"
PAYLOAD_DIR="${OUTPUT_DIR}/Payload"
rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"

# Create IPA (zip with Payload/ structure)
cd "$OUTPUT_DIR"
rm -f "$IPA_NAME"
zip -r "$IPA_NAME" Payload/ -x "*.DS_Store"
cd ..

echo -e "${GREEN}IPA created: ${OUTPUT_DIR}/${IPA_NAME}${NC}"

# Step 6: Generate installation instructions
echo -e "${GREEN}[6/6] Generating installation instructions...${NC}"
cat > "${OUTPUT_DIR}/INSTALL.md" << 'INSTALL_EOF'
# TrollReverseLab Installation Guide

## Prerequisites
- iOS device with TrollStore installed (iOS 14-16.6.1, iOS 17.0)
- The TrollReverseLab.ipa file from this build

## Installation Steps

1. Transfer `TrollReverseLab.ipa` to your iOS device
2. Open TrollStore
3. Tap the "+" button in the top right
4. Select the TrollReverseLab.ipa file
5. TrollStore will automatically install with the injected entitlements
6. The app icon will appear on your home screen

## Usage Constraints
- This tool is for PERSONAL LOCAL iOS reverse engineering learning ONLY
- Only use on apps you have installed via TrollStore for research purposes
- Do NOT use for: payment bypass, DRM cracking, online cheating, privacy violations
- Do NOT distribute modified apps or cracking scripts

## Troubleshooting
- If the app crashes on launch, verify TrollStore version compatibility
- If Frida gadget fails to load, check that the framework is properly embedded
- If file access is denied, verify the entitlements were properly injected
INSTALL_EOF

echo ""
echo -e "${GREEN}=== Build Complete ===${NC}"
echo -e "IPA location: ${OUTPUT_DIR}/${IPA_NAME}"
echo -e "Installation guide: ${OUTPUT_DIR}/INSTALL.md"
echo ""
echo -e "${YELLOW}Reminder: For personal local iOS reverse engineering learning only.${NC}"
echo -e "${YELLOW}Do not use for commercial cracking, payment bypass, or distribution.${NC}"

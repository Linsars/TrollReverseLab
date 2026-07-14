.PHONY: generate build clean ipa all

APP_NAME    := TrollReverseLab
SCHEME      := TrollReverseLab
CONFIG      := Release
BUILD_DIR   := build
IPA_FILE    := $(BUILD_DIR)/$(APP_NAME).ipa

# 生成 Xcode 项目
generate:
	xcodegen generate

# 编译应用 (不签名)
build: generate
	xcodebuild \
		-project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-sdk iphoneos \
		-derivedDataPath $(BUILD_DIR)/DerivedData \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		build

# 注入权限 + 打包 IPA
ipa: build
	@APP_PATH=$$(find $(BUILD_DIR)/DerivedData -name "$(APP_NAME).app" -path "*/Release-iphoneos/*" | head -1); \
	if [ -z "$$APP_PATH" ]; then echo "Error: .app not found"; exit 1; fi; \
	echo "Found: $$APP_PATH"; \
	ldid -STrollReverseLab/TrollReverseLab.entitlements "$$APP_PATH/$(APP_NAME)"; \
	rm -rf $(BUILD_DIR)/Payload; \
	mkdir -p $(BUILD_DIR)/Payload; \
	cp -R "$$APP_PATH" $(BUILD_DIR)/Payload/; \
	cd $(BUILD_DIR) && zip -r $(APP_NAME).ipa Payload/ -x "*.DS_Store" && cd ..; \
	shasum -a 256 $(IPA_FILE) > $(BUILD_DIR)/ipa_checksum.txt; \
	echo "IPA: $(IPA_FILE)"; \
	echo "SHA256: $$(cat $(BUILD_DIR)/ipa_checksum.txt)"

# 一键全部
all: ipa

# 清理构建产物
clean:
	rm -rf $(BUILD_DIR)
	rm -f $(APP_NAME).xcodeproj

# 显示帮助
help:
	@echo "TrollReverseLab 构建命令:"
	@echo "  make generate  — 用 xcodegen 生成 .xcodeproj"
	@echo "  make build     — 编译应用 (需先 generate)"
	@echo "  make ipa       — 编译 + 注入权限 + 打包 IPA"
	@echo "  make all       — 同 ipa"
	@echo "  make clean     — 清理构建产物"
	@echo ""
	@echo "前置要求: macOS 14+, Xcode 15+, xcodegen, ldid"

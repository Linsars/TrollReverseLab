# TrollReverseLab — iOS 巨魔本地逆向/沙盒调试研究工具

> **定位声明**: 本工具仅用于个人本地 iOS 逆向学习、单机本地存档数据格式研究、客户端数据结构调试、本地性能参数测试。仅限 TrollStore 安装应用的本地沙盒文件/本地进程做技术研究。

## 目录

- [一、项目概述](#一项目概述)
- [二、技术架构](#二技术架构)
- [三、项目结构](#三项目结构)
- [四、模块详解](#四模块详解)
  - [模块1：巨魔 App 沙盒文件查看器](#模块1巨魔-app-沙盒文件查看器)
  - [模块2：本地 Frida 内存调试引擎](#模块2本地-frida-内存调试引擎)
  - [模块3：AI 辅助逆向脚本生成](#模块3ai-辅助逆向脚本生成)
  - [模块4：预封装调试权限](#模块4预封装调试权限)
- [五、安全约束机制](#五安全约束机制)
- [六、构建与打包](#六构建与打包)
- [七、合规声明](#七合规声明)
- [八、技术集成路线图](#八技术集成路线图)

---

## 一、项目概述

### 现有痛点

| 痛点 | 描述 |
|------|------|
| 工具碎片化 | Filza 查看沙盒 + 独立 Frida 工具 + 单独脚本工具，来回切换效率低 |
| 权限门槛高 | 私有 entitlements 注入、签名适配不适合新手 |
| 缺少可视化校验 | 修改本地存档参数后不方便核对数据变化 |

### 解决方案

TrollReverseLab 将四大功能整合到单一 IPA 中，TrollStore 直接安装使用，预注入调试类 entitlements，降低逆向学习门槛。

### 适用环境

- iOS 14 ~ 16.6.1（TrollStore 兼容版本）
- iOS 17.0（TrollStore 2 兼容）
- 需要通过 TrollStore 安装本工具

---

## 二、技术架构

```
┌─────────────────────────────────────────────────────────┐
│                   TrollReverseLab App                     │
│                    (SwiftUI 原生界面)                      │
├──────────────┬──────────────┬──────────────┬────────────┤
│   模块1      │   模块2      │   模块3      │   模块4    │
│  沙盒查看器   │  Frida引擎   │  AI脚本生成  │  权限封装  │
├──────────────┼──────────────┼──────────────┼────────────┤
│  App扫描     │  进程附加     │  LLM API    │  ldid签名  │
│  文件浏览     │  JS执行      │  提示词约束   │  IPA打包   │
│  数据查看器   │  函数追踪     │  脚本管理    │  重签保留  │
├──────────────┴──────────────┴──────────────┴────────────┤
│                  安全约束层 (AppSecurityFilter)            │
│     .appInfo.plist 过滤 | 用户自选验证 | 脚本内容审查       │
├─────────────────────────────────────────────────────────┤
│                    基础运行时层                            │
│  frida-gadget | SQLite3 | URLSession | FileManager       │
└─────────────────────────────────────────────────────────┘
```

### 技术选型

| 层次 | 技术 | 说明 |
|------|------|------|
| UI 框架 | SwiftUI | iOS 14+ 原生声明式 UI |
| 调试引擎 | frida-gadget | 嵌入式 Frida 运行时，无需 frida-server |
| 脚本解释 | Lua 5.4 + Frida JS | 双脚本引擎支持 |
| AI 接口 | OpenAI 兼容 API | 支持 GPT、Claude 等主流模型 |
| 数据解析 | SQLite3 / PropertyList | 系统内置库 |
| 权限签名 | ldid | TrollStore 标准签名工具 |
| 打包 | Shell 脚本 | 自动化 IPA 构建 |

---

## 三、项目结构

```
TrollReverseLab/
├── TrollReverseLab/
│   ├── TrollReverseLabApp.swift          # 应用入口 + 主TabView
│   ├── TrollReverseLab.entitlements      # 调试权限配置
│   │
│   ├── SandboxViewer/                    # 模块1: 沙盒文件查看器
│   │   ├── Models/
│   │   │   └── TrollStoreAppScanner.swift    # TrollStore应用扫描
│   │   └── Views/
│   │       ├── AppListView.swift             # 应用列表界面
│   │       ├── SandboxFileBrowser.swift      # 沙盒目录浏览
│   │       └── FileViewers.swift             # JSON/Plist/SQLite/Hex查看器
│   │
│   ├── FridaEngine/                      # 模块2: Frida调试引擎
│   │   ├── FridaEngine.swift              # 引擎核心逻辑
│   │   ├── FridaDebugView.swift           # 调试界面UI
│   │   └── Bridge/
│   │       └── FridaBridge.swift          # frida-gadget通信桥接
│   │
│   ├── AIScriptGenerator/                # 模块3: AI脚本生成
│   │   ├── AIScriptClient.swift           # LLM API客户端
│   │   ├── AIScriptView.swift            # AI生成界面UI
│   │   └── Models/
│   │       └── SystemPrompt.swift         # 系统提示词约束
│   │
│   ├── Shared/                           # 共享组件
│   │   ├── Security/
│   │   │   └── AppSecurityFilter.swift    # 安全过滤层
│   │   └── SettingsView.swift            # 设置界面
│   │
│   └── Resources/
│       └── Info.plist                    # 应用配置
│
├── BuildTools/
│   └── build_ipa.sh                      # IPA打包脚本
│
└── README.md                             # 本文档
```

---

## 四、模块详解

### 模块1：巨魔 App 沙盒文件查看器

**核心文件**: `TrollStoreAppScanner.swift`, `SandboxFileBrowser.swift`, `FileViewers.swift`

#### 工作流程

1. 扫描 `/var/mobile/Containers/Data/Application/` 目录
2. 检测每个容器中的 `.appInfo.plist` 文件（TrollStore 标记）
3. 解析 plist 获取应用元数据（Bundle ID、显示名称、版本）
4. 用户选择应用后进入沙盒浏览模式
5. 支持快速访问 Documents、Library、Preferences、tmp 目录

#### 支持的文件查看器

| 格式 | 功能 | 实现方式 |
|------|------|----------|
| JSON | 语法高亮 + 可折叠树形结构 | `JSONSerialization` + 递归视图 |
| Plist | 键值对树形展示 | `PropertyListSerialization` |
| SQLite | 表列表 + 行数据表格 | `sqlite3` C API |
| Hex | 十六进制偏移 + ASCII 对照 | 手动字节分块 |
| Text | 纯文本显示 | UTF-8 解码 |

#### 关键代码

```swift
// TrollStore 应用检测逻辑
let appInfoPath = (containerPath as NSString).appendingPathComponent(".appInfo.plist")
guard fileManager.fileExists(atPath: appInfoPath) else { continue }
// 只有存在 .appInfo.plist 的容器才是 TrollStore 安装的应用
```

### 模块2：本地 Frida 内存调试引擎

**核心文件**: `FridaEngine.swift`, `FridaBridge.swift`, `FridaDebugView.swift`

#### 架构设计

```
Swift UI 层
    ↓
FridaEngine (状态管理 + 安全验证)
    ↓
FridaBridge (frida-gadget 通信桥接)
    ↓
frida-gadget (嵌入式 Frida 运行时)
    ↓
目标进程 (用户选定的 TrollStore App)
```

#### 安全机制

- **进程附加前验证**: 检查是否为用户手动选定、是否为系统进程、是否有 .appInfo.plist
- **脚本执行前审查**: `AppSecurityFilter.validateScript()` 检查禁止关键词
- **无全局注入**: 只能附加到用户在 UI 中明确选择的进程

#### 脚本执行流程

```swift
// 1. 安全验证
let validation = securityFilter.validateScript(script)
guard case .approved = validation else { return }

// 2. 检查附加状态
guard case .attached = state else { return }

// 3. 通过 bridge 执行
bridge?.executeScript(script) { result in
    // 4. 处理输出
}
```

### 模块3：AI 辅助逆向脚本生成

**核心文件**: `AIScriptClient.swift`, `SystemPrompt.swift`, `AIScriptView.swift`

#### 系统提示词约束

系统提示词 (`SystemPrompt.constraints`) 定义了严格的生成边界：

- **允许**: 本地存档读取、本地函数追踪、本地数据结构分析
- **禁止**: 支付绕过、DRM 破解、联机作弊、隐私窃取、全局注入
- **输出**: LLM 被要求在违规请求时返回明确的拒绝信息

#### API 兼容性

支持任何 OpenAI 兼容的 API 端点：

```swift
// 默认配置
LLMConfig(
    apiBaseURL: "https://api.openai.com/v1",  // 可替换为任意兼容端点
    model: "gpt-4o",
    temperature: 0.3,
    maxTokens: 4096
)
```

#### 脚本管理

- 生成的脚本自动保存到 `Documents/GeneratedScripts/`
- 支持脚本命名、查看历史、重新生成
- 生成的脚本可直接在模块2中加载执行

### 模块4：预封装调试权限

**核心文件**: `TrollReverseLab.entitlements`, `BuildTools/build_ipa.sh`

#### 注入的 Entitlements

| 权限 | 用途 |
|------|------|
| `com.apple.private.security.no-sandbox` | 跳过沙盒限制，访问应用容器 |
| `com.apple.security.cs.allow-jit` | Frida gadget JIT 运行时支持 |
| `com.apple.security.cs.disable-library-validation` | 允许加载 Frida 动态库 |
| `com.apple.security.cs.allow-dyld-environment-variables` | DYLD 环境变量注入 |
| `com.apple.security.network.client` | LLM API 网络请求 |
| `com.apple.system-task-ports` | 进程调试端口访问 |
| `get-task-allow` | 允许调试器附加 |
| `platform-application` | TrollStore 平台应用标识 |
| `com.apple.private.tcc.allow` | 完整文件系统访问 |

#### 打包流程

```
xcodebuild (不签名构建)
    ↓
检查 FridaGadget.framework
    ↓
ldid 注入 entitlements
    ↓
验证权限是否生效
    ↓
打包 Payload/ 结构为 IPA
    ↓
生成安装说明
```

---

## 五、安全约束机制

### 三层安全过滤

```
层1: 应用过滤层 (AppSecurityFilter.validateTarget)
  ├─ 必须用户手动选定
  ├─ 屏蔽系统核心进程 (com.apple.* 前缀)
  ├─ 屏蔽 App Store 应用
  └─ 验证 .appInfo.plist 存在 (TrollStore 标记)

层2: 脚本审查层 (AppSecurityFilter.validateScript)
  ├─ 检测 StoreKit/payment 关键词
  ├─ 检测 IAP/receipt 关键词
  ├─ 检测 crack/unlock 关键词
  └─ 违规脚本拒绝执行

层3: AI 提示词约束层 (SystemPrompt.constraints)
  ├─ 系统提示词定义允许/禁止行为
  ├─ LLM 被要求拒绝违规请求
  └─ 输出格式约束 (代码块包裹 + 注释)
```

### 首次启动协议

应用首次启动时强制显示使用协议，用户必须明确同意以下条款：
- 仅用于个人本地 iOS 逆向学习
- 禁止内购绕过、支付欺诈
- 禁止联机游戏篡改、批量破解
- 禁止侵犯版权、盗取隐私数据
- 不对外分发破解脚本

---

## 六、构建与打包

### 方式A: GitHub Actions 云端自动打包（推荐，无需 Mac）

这是最便捷的方式——推送到 GitHub 后自动在云端 macOS 环境编译出 IPA。

```bash
# 1. 初始化 Git 仓库
cd TrollReverseLab
git init
git add .
git commit -m "Initial commit: TrollReverseLab"

# 2. 在 GitHub 上创建仓库并推送
git remote add origin https://github.com/<你的用户名>/TrollReverseLab.git
git push -u origin main

# 3. GitHub Actions 自动触发构建
#    进入 GitHub 仓库 → Actions → Build TrollReverseLab IPA
#    构建完成后在 Artifacts 中下载 IPA 文件

# 4. 或手动触发构建
#    GitHub 仓库 → Actions → Run workflow
```

**GitHub Actions 工作流特性：**
- 使用 macOS 14 (M1) runner，自带 Xcode 15
- 自动安装 xcodegen 生成 Xcode 工程
- 自动安装 ldid 注入 entitlements
- 构建完成后自动打包 IPA 并上传为 artifact
- 保留 30 天可供下载
- 支持 push / tag / 手动触发

### 方式B: 本地 Mac 一键构建

如果你有 Mac，可用 Makefile 或脚本一键构建：

```bash
# 前置要求 (brew 自动安装)
brew install xcodegen ldid

# Makefile 方式 (推荐)
make ipa          # 编译 + 注入权限 + 打包 IPA
make clean        # 清理构建产物

# 或使用脚本
chmod +x local_build.sh
./local_build.sh
```

### 方式C: 手动 Xcode 构建

```bash
# 1. 用 xcodegen 生成 Xcode 项目
xcodegen generate

# 2. 打开 Xcode
open TrollReverseLab.xcodeproj

# 3. 在 Xcode 中选择 Release-iphoneos 构建
# 4. 构建完成后用 ldid 注入权限
ldid -STrollReverseLab/TrollReverseLab.entitlements build/TrollReverseLab.app/TrollReverseLab

# 5. 手动打包 IPA
mkdir -p build/Payload
cp -R build/TrollReverseLab.app build/Payload/
cd build && zip -r TrollReverseLab.ipa Payload/
```

### TrollStore 安装

1. 将 `TrollReverseLab.ipa` 传输到 iOS 设备
2. 打开 TrollStore → 点击 "+" → 选择 IPA
3. TrollStore 自动重签并保留 entitlements
4. 安装完成后即可使用

---

## 七、合规声明

### 合法用途

- 纯本地单机客户端逆向学习
- 存档格式解析与数据结构研究
- 本地参数调试与性能测试
- Frida 逆向技术教学
- iOS 沙盒机制研究

### 禁止用途

- 内购绕过、支付欺诈
- 联机游戏篡改、批量破解 IPA
- 侵犯软件版权
- 盗取用户隐私数据
- 对外分发破解脚本
- 商业化破解用途

### 免责声明

本工具仅供个人学习研究使用。使用者需遵守当地法律法规，对使用本工具产生的任何后果自行承担责任。开发者不对本工具的滥用行为负责。

---

## 八、技术集成路线图

### Phase 1: 基础框架 (当前已完成)

- [x] 项目结构与配置文件
- [x] 沙盒文件查看器 (JSON/Plist/SQLite/Hex)
- [x] Frida 引擎核心架构与安全过滤
- [x] AI 脚本生成客户端
- [x] Entitlements 配置与打包脚本
- [x] SwiftUI 界面框架

### Phase 2: Frida 集成深化

- [ ] 集成 frida-core Swift bindings
- [ ] frida-gadget 动态库嵌入与配置
- [ ] 实际进程枚举与附加功能
- [ ] Frida 消息处理管道
- [ ] Lua 解释器集成 (LuaBridge)

### Phase 3: AI 能力增强

- [ ] 多模型切换支持 (GPT/Claude/本地模型)
- [ ] 脚本模板库
- [ ] 上下文感知生成 (基于沙盒文件结构)
- [ ] 脚本执行结果反馈给 AI 优化

### Phase 4: 体验优化

- [ ] 暗黑模式适配
- [ ] 文件修改功能 (仅本地存档)
- [ ] 书签与收藏功能
- [ ] 导出分析报告
- [ ] iPad 适配

---

## 联系与合作

本项目接受开源开发、技术合作定制。欢迎相关开发者沟通实现方案。

**技术栈**: Swift / SwiftUI / Frida / Lua / OpenAI API / ldid / TrollStore

# QinlinOpen for iOS（非官方 iPhone 客户端）

这是 [rponeawa/QinlinOpen](https://github.com/rponeawa/QinlinOpen)（Android 版，MIT）的 **iOS 原生移植工程**。
原仓库是纯 Kotlin / Jetpack Compose 的 Android 应用，没有任何 iOS 代码，所以「直接编译出 ipa」这件事在原仓库上不成立——本工程是按它的协议和交互重写的 SwiftUI 版本，可以真正打出 iPhone 能装的包。

## 为什么不能直接拿原仓库编译 ipa

| | Android 仓库 | iOS |
|---|---|---|
| 语言 / 框架 | Kotlin + Jetpack Compose | Swift + SwiftUI |
| 编译产物 | .apk（aab） | .ipa |
| 编译环境 | JDK 17 + Android SDK 36（Linux / Win / macOS 都行） | 必须 macOS + Xcode + iOS SDK |
| 安装 | adb / 任意渠道 | 必须 Apple 代码签名后才可安装 |

APK 和 IPA 是两套不同的平台二进制，不存在「换个打包器」的可能。

## 本工程做了什么

- **协议层 1:1 对齐** `QinlinApi.kt`：同一套 `MD5(排序后的 key=value&...&key=qiAnlPinP)` 签名、同一个 `AES/ECB/PKCS5` 手机号加密、同一组请求头（`openid / qversioncode / qchannel / qplatform / qvendor`）、同一个 `open/doorcontrol/v2/open` 开门接口、同样的「`success` / `code` / `data` 可能是嵌套 JSON 字符串」的宽松解析。
- **短信验证码 → 登录 → 拉取全部门禁钥匙 → 点击开门**，与 Android 版一致的流程。
- **登录态只存本机 Keychain**（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`），退出即清除；不写 UserDefaults，不做任何日志上传。
- **钥匙排序**保存在本地，并支持长按拖动（iOS 的 `onMove`）与「上移 / 下移」两种方式。
- **界面**：登录页（手机号 + 验证码 + 60s 倒计时）、钥匙卡片列表（加载中 → 成功校验标记）、下拉刷新、排序模式、退出登录确认、Toast 提示。

## 结构

```
QinlinOpen-iOS/
├── QinlinOpen.xcodeproj/           # 可直接用 Xcode 打开
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/QinlinOpen.xcscheme
├── QinlinOpen/
│   ├── RootView.swift               # @main 入口 + 根视图 + 登录页（含 Toast / 主题色）
│   ├── DoorListView.swift           # 钥匙列表 / 卡片 / 排序
│   ├── AppStore.swift               # 状态机：发送验证码、登录、刷新、开门、排序、退出
│   ├── QinlinAPI.swift              # 协议实现（签名、加密、请求、解析）
│   ├── SecureStore.swift            # Keychain 封装 + 设备标识
│   ├── Models.swift
│   └── Assets.xcassets              # AppIcon / AccentColor
├── build-ipa.sh                     # macOS 一键出 ipa
└── README.md
```

> 说明：这份工程由我按原仓库源码逐函数对照写成，但**没有在 Xcode 里真正编译过**（当前环境是 Linux，没有 iOS SDK）。首次打开如果有个别编译提示，按 Xcode 的 Fix 走即可；签名相关的报错请看下面第 1 和第 3 节。

部署目标 iOS 16.0，Swift 5，Bundle ID 默认 `top.rpone.qinlinopen`（可改成你自己的）。

## 出 ipa 的三种方式

### 1. 有 Mac（推荐）

```bash
# 免签名包，给自签工具用
./build-ipa.sh
# 有付费开发者账号（Team ID 在 developer.apple.com 查）
./build-ipa.sh --signed 你的TeamID
```

也可以用 Xcode 打开 `QinlinOpen.xcodeproj`：选中 target → Signing & Capabilities 勾上 *Automatically manage signing*、填自己的 Team → 连上 iPhone 直接 Run，或 Product → Archive → Distribute App。

### 2. 没有 Mac

用云 Mac（MacinCloud、GitHub Actions 的 `macos-14` runner 等）跑上面的脚本，或把仓库丢给任意 CI 出未签名 ipa，然后本地自签。

### 3. 已经拿到 ipa 后怎么装到 iPhone

- **Sideloadly**（Windows / macOS 都有）：ipa 拖进去，填自己的 Apple ID，自动签名安装。免费账号 7 天有效，到期重装。
- **AltStore / SideStore**：同上，可自动续签。
- **爱思助手 / iMazing**：走「IPA 签名」入口，用 Apple ID 自签。
- **付费开发者账号**：`--signed` 导出的 ipa 可装到自己的设备，有效期 1 年，可分发到最多 100 台已登记 UDID 的设备。

> 首次安装后需要在 iPhone「设置 → 通用 → VPN 与设备管理」里信任该开发者证书，否则打不开。

## 与 Android 版的差异（必须知道）

- **没有桌面小组件**。Android 的 AppWidget 在 iOS 上对应 WidgetKit extension，是另一个 target + App Group 共享钥匙数据，工程量不小，本工程没有做。需要的话可以在这个工程里加一个 Widget Extension，把「绑定钥匙 + 一键开门」用 `Link` / `AppIntent` 实现。
- **没有「每把钥匙单独存一个小组件」的机制**，但钥匙顺序、登录态同样只在本机。
- Android 用 `ANDROID_ID` 作为 `openid`，iOS 没有对应值，这里改成首次启动生成、存进 Keychain 的 16 位随机串，保证同一台设备恒定。理论上服务端只把它当设备标识用，不影响登录和开门。
- 界面按 iOS 习惯重画（List + 卡片），不是像素级复刻 Compose。

## 风险与免责

- 协议常量（`version 5.2.6` / `versionCode 3146` / 签名盐 / AES 密钥 / `appsecret`）来自原仓库，用于兼容官方客户端。官方版本升级后可能需要同步修改，此时表现通常是登录或开门返回 `code` 错误。
- 仅用于你本人已获授权的亲邻账号与门禁；服务端仍会校验会话和钥匙归属，本项目不绕过任何授权。
- 亲邻官方与原作者均与本工程无关；商标、服务端、协议不在 MIT 授权范围内。
- 不要在日志、Issue、截图里贴手机号、验证码、`sessionId` 或完整响应报文。

## 许可证

移植代码沿用原项目的 MIT License。

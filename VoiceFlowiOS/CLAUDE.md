# VoiceFlowiOS - iOS 语音输入应用

iOS 17 + SwiftUI 6 + @Observable

## 技术栈

iOS 17+ · SwiftUI 6 · Swift 6 · @Observable · AVFoundation · Whisper ASR

## 架构目标

iOS Keyboard Extension（自定义键盘）+ 主 App 后台常驻录音引擎。
键盘触发录音时采用三级策略：心跳时间戳判活 → Darwin requestStart + requestAck 握手确认 → URL Scheme 兜底。
主 App 收到 requestStart 后立即回发 requestAck；键盘 .waitingMainApp 状态 15s 超时自动恢复 idle。

<directory>
VoiceFlowiOS/ - Xcode 项目源文件
  ├── VoiceFlowiOSApp.swift  - @main App 入口，Darwin 监听 + 后台保活
  ├── ContentView.swift      - 根视图，Tab 路由
  ├── Core/                  - 业务核心层 (含 BackgroundKeepAlive 静音保活)
  ├── Models/AppState.swift  - @Observable 全局状态
  └── Views/                 - 首页 UI 组件 (8个文件)
VoiceFlowKeyboard/         - 键盘 Extension（Darwin 优先触发 + URL Scheme 兜底）
VoiceFlowiOS.xcodeproj/    - Xcode 项目文件
</directory>

## 首页组件树

```
ContentView
  └── HomeView
        ├── HomeHeader (Logo + 搜索/通知)
        ├── StatsGridView (2x2 统计卡片)
        ├── MainToggleCard (开关 + 偏好设置)
        └── QuickActionsView (开始听写 / 翻译设置)
  └── BottomNavBar (悬浮，首页/历史/词典/账户)
```

## 设计规范（来自 Figma node 1:2）

- 背景：`#fcfcfc`
- 主文字：`#000000`，次要：`#71717a`，inactive：`#94a3b8`
- 边框：`#f1f1f1`，卡片背景：`#f8fafc`
- 卡片圆角：stats 20px，toggle 24px，action 16px
- 阴影：`shadow(radius:10, y:2, opacity:0.03) + shadow(radius:5, y:4, opacity:0.01)`
- 底部导航：悬浮 Capsule，bottom 24px，active = black，inactive = `#94a3b8`

## 开发规范

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

- 每文件不超过 200 行
- SwiftUI @Observable（非 @StateObject/@ObservedObject）
- 颜色全部用 Color(hex:) 扩展，不硬编码
- 组件 private struct 嵌套在父视图文件内

# VoiceFlow iOS — 语音输入 + AI 润色键盘

在任意输入框，用语音替代打字。录音 → 转录 → AI 润色 → 自动插入光标处。

## 核心功能

**自定义键盘**
- 一键录音，语音实时转文字
- AI 自动润色口语为书面语
- 结果直接插入光标处，无需复制粘贴
- 实时波纹动画反馈录音状态

**主应用**
- 录音 + 转录 + 一键复制到剪贴板
- 历史记录（最近 100 条，含原文 + 润色文）
- 人设模板（自定义 LLM 系统提示词）
- 用量统计（时长 / 字数 / 节省时间）

## 技术栈

| 层 | 技术 |
|---|------|
| UI | SwiftUI + @Observable (iOS 17+) |
| 语音采集 | AVFoundation (16kHz/16bit/mono PCM) |
| 语音识别 | ElevenLabs Scribe v2 REST API |
| AI 润色 | OpenRouter / DeepSeek / MiniMax / 智谱 / Kimi |
| 跨进程通信 | Darwin Notification + App Group 文件共享 |
| 存储 | Keychain (API Key) + UserDefaults + 文件 I/O |

**零第三方依赖**，纯系统框架。

## 架构

```
┌─────────────────────┐     Darwin Notification     ┌──────────────────┐
│   VoiceFlowKeyboard │ ◄──────────────────────────► │   VoiceFlowiOS   │
│   (键盘 Extension)   │     App Group 文件共享       │   (主应用)        │
│                     │                              │                  │
│  RecordButton       │  voiceflow://startRecording  │  AudioEngine     │
│  WaveformBars       │ ────────────────────────────►│  RecordingCoord  │
│  LiveTextCard       │                              │  LLMClient       │
│  textDocumentProxy  │ ◄──── pendingResult.txt ─────│  SharedStore     │
└─────────────────────┘                              └──────────────────┘
```

**键盘录音流程：**
1. 键盘点击录音 → URL Scheme 唤醒主 App
2. 主 App 启动 AVAudioSession → 自动返回键盘
3. 音频 PCM 缓存在内存（后台安全，不走网络）
4. 键盘点击停止 → Darwin 通知主 App
5. 主 App：PCM → WAV → ElevenLabs REST API 转录
6. 转录文本 → LLM 润色 → 写入 App Group 共享文件
7. Darwin 通知键盘 → 键盘读取结果 → `insertText()` 插入光标

## 项目结构

```
VoiceFlowiOS/
├── VoiceFlowiOSApp.swift          # @main 入口，URL Scheme + Darwin 监听
├── ContentView.swift              # 根视图，Tab 路由 + 权限引导
├── Core/
│   ├── AudioEngine.swift          # AVAudioSession 音频采集
│   ├── RecordingCoordinator.swift # 录音→转录→润色→注入 完整流程
│   ├── LLMClient.swift            # LLM 润色中枢
│   ├── SharedStore.swift          # App Group 文件共享（跨进程）
│   ├── KeychainManager.swift      # API Key 安全存储
│   ├── PermissionManager.swift    # 麦克风权限管理
│   └── Providers/                 # 可插拔 ASR/LLM 提供商
│       ├── LLMProvider.swift
│       ├── ProviderFactory.swift
│       └── LLM/
│           ├── DeepSeekProvider.swift
│           └── OpenRouterProvider.swift
├── Models/
│   ├── AppState.swift             # 全局状态机 (idle/recording/processing/done/error)
│   ├── HistoryEntry.swift         # 历史记录模型
│   └── StyleTemplate.swift        # 人设模板模型
├── Views/                         # SwiftUI 页面
│   ├── HomeView.swift
│   ├── HistoryView.swift
│   ├── DictionaryView.swift
│   └── AccountView.swift
└── VoiceFlowKeyboard/             # 键盘 Extension
    ├── KeyboardViewController.swift
    ├── KeyboardView.swift
    └── KeyboardViewModel.swift
```

## 快速开始

### 环境要求

- Xcode 16+
- iOS 17.0+ 真机（键盘扩展不支持模拟器）
- Apple Developer 账号（需要签名）

### 配置

1. 克隆仓库
   ```bash
   git clone https://github.com/daohewang/voiceflow-ios-.git
   ```

2. 打开 `VoiceFlowiOS/VoiceFlowiOS.xcodeproj`

3. 修改两个 target 的 **Signing & Capabilities**：
   - Team：选择你的开发者账号
   - Bundle Identifier：改为你的域名
   - App Groups：确认 `group.com.xxx.voiceflow.ios` 一致

4. Cmd+R 运行到真机

### API Key 配置

在 App 内 **设置页** 填入：

| 服务 | 用途 | 获取地址 |
|------|------|---------|
| ElevenLabs | 语音识别 (ASR) | [elevenlabs.io](https://elevenlabs.io) |
| DeepSeek / OpenRouter | AI 润色 (LLM) | [deepseek.com](https://platform.deepseek.com) |

> DeepSeek 在中国大陆可直连，无需 VPN。

### 使用键盘

1. 系统设置 → 键盘 → 添加 VoiceFlow 键盘
2. 开启「完全访问」权限
3. 任意输入框切换到 VoiceFlow 键盘
4. 点击麦克风按钮 → 说话 → 点击停止 → 文字自动插入

## 设计决策

| 决策 | 原因 |
|------|------|
| 本地缓存 PCM + 停止后 REST 转录 | iOS 后台会杀死 WebSocket，本地缓存不受影响 |
| App Group 文件共享 | UserDefaults 在 Extension 中不可靠 (cfprefsd 限制) |
| Darwin Notification | 唯一可靠的 iOS 跨进程实时通知机制 |
| 可插拔 Provider 模式 | 不绑定单一 ASR/LLM 服务商，工厂模式切换 |
| `UIApplication.suspend` | 键盘辅助 App 标准做法，录音启动后自动返回键盘 |

## License

MIT

# VoiceFlowiOS - iOS 语音输入 AI 润色 App
Swift 6 + SwiftUI + @Observable + AVFoundation + URLSession WebSocket

<directory>
Core/ - 业务核心层 (8文件 + Providers子目录)
  AudioEngine.swift       - iOS AVAudioSession 音频采集，16kHz PCM 输出
  ASRClient.swift         - ElevenLabs WebSocket 实时转录
  LLMClient.swift         - LLM 中枢，调用提供商润色文本
  RecordingCoordinator.swift - 录音→转录→润色→UIPasteboard 完整数据流
  KeychainManager.swift   - UserDefaults API Key 存储
  UsageStats.swift        - 录音时长/字数/节省时间统计
  PermissionManager.swift - iOS AVAudioSession 麦克风权限
  Logger.swift            - 调试日志写入 Documents/Logs/

  Providers/ - 提供商协议与工厂
    LLMProvider.swift     - LLMProvider 协议 + LLMProviderType 枚举
    ASRProvider.swift     - ASRProvider 协议 + ASRProviderType 枚举
    ProviderFactory.swift - 运行时创建提供商实例
    LLM/
      DeepSeekProvider.swift    - DeepSeek API 实现
      OpenRouterProvider.swift  - OpenRouter API 实现

Models/ - 数据模型层
  AppState.swift      - 全局状态机，持有 RecordingCoordinator，管理历史/统计/设置
  HistoryEntry.swift  - 历史记录条目 Codable 模型
  StyleTemplate.swift - 人设模板模型 + StyleTemplateStore 单例

Views/ - UI 层 (保持原有 Figma 设计)
  HomeView.swift       - 首页，录音开关 + 实时结果卡 + 统计
  MainToggleCard.swift - 录音开关卡，Toggle → startRecording/stopRecording
  HistoryView.swift    - 历史记录页，真实 HistoryEntry 数据渲染
  DictionaryView.swift - 人设模板页，选择/新建/删除 StyleTemplate
  AccountView.swift    - 设置页，API Key 配置 + LLM 服务商选择
  StatsGridView.swift  - 2x2 统计网格，绑定 AppState 真实数据
  QuickActionsView.swift - 快速操作入口
  BottomNavBar.swift   - 底部 Tab 导航

Extensions/
  Color+Hex.swift - 十六进制颜色扩展
</directory>

<config>
Info.plist        - NSMicrophoneUsageDescription 麦克风权限声明
VoiceFlowiOSApp.swift - @main 入口，注入 AppState.shared
</config>

## 架构决策
- iOS 文本注入：UIPasteboard.general.string（无 macOS 辅助功能依赖）
- 状态管理：AppState.RecordingStatus 枚举状态机（idle/recording/processing/done/error）
- 音频：AVAudioSession .record + .measurement，支持蓝牙麦克风
- 无第三方依赖，纯系统框架

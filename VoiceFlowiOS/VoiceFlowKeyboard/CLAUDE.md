# VoiceFlowKeyboard/
> L2 | 父级: VoiceFlowiOS/CLAUDE.md

## 成员清单

KeyboardViewController.swift: UIInputViewController 子类，SwiftUI 宿主，固定高度 260pt
KeyboardView.swift: 完整键盘 SwiftUI 界面，含 Header / LiveTextCard / WaveformBars / RecordButton
KeyboardViewModel.swift: @Observable 状态层，三段式触发主 App 录音（心跳检查→Darwin ACK→URL Scheme）+ Keychain 接收结果 + Darwin Notification 通信
Info.plist: Extension 配置，NSExtension.RequestsOpenAccess = true（Full Access 必须）
VoiceFlowKeyboard.entitlements: App Group 权限声明

## 架构说明（后台常驻模式）

- Extension 是独立进程，不能 import 主 App target，不能直接录音
- 键盘只负责"触发"和"接收结果"，真正录音由主 App 后台执行
- 触发三级策略：① 读 SharedStore 心跳时间戳判活（<10s 即存活）→ ② Darwin requestStart + 等待 requestAck 确认 → ③ URL Scheme 兜底
- ACK 握手：主 App 收到 requestStart 后立即回发 Darwin requestAck；键盘等待 ACK 超时则降级
- .waitingMainApp 状态：超过 15s 未收到进展自动恢复为 idle，防止键盘卡死
- Darwin Notification 跨进程通信（requestStart/requestAck/recordingStarted/Stopped/audioLevel/resultReady/stopRecording）
- App Group 文件 I/O 跨进程数据传递（SharedStore，含心跳时间戳 + 录音结果）
- textDocumentProxy.insertText() 是文字注入的唯一合法途径
- 录音流程（常驻模式）：键盘心跳/ACK 确认存活 → Darwin requestStart → 主 App 后台直接录音 → REST API 转录 → LLM 润色 → App Group 写入 → Darwin 通知键盘 → 键盘读取插入
- 录音流程（兜底模式）：键盘 URL Scheme → 主 App 前台录音 → suspend 返回 → 后续同上

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

# VoiceFlowKeyboard/
> L2 | 父级: VoiceFlowiOS/CLAUDE.md

## 成员清单

KeyboardViewController.swift: UIInputViewController 子类，SwiftUI 宿主，固定高度 260pt
KeyboardView.swift: 完整键盘 SwiftUI 界面，含 Header / LiveTextCard / WaveformBars / RecordButton
KeyboardViewModel.swift: @Observable 状态层，触发主 App 录音 + Keychain 接收结果 + Darwin Notification 通信
Info.plist: Extension 配置，NSExtension.RequestsOpenAccess = true（Full Access 必须）
VoiceFlowKeyboard.entitlements: App Group 权限声明

## 架构说明

- Extension 是独立进程，不能 import 主 App target，不能直接录音
- 键盘只负责"触发"和"接收结果"，真正录音由主 App 执行
- URL Scheme `voiceflow://startRecording` 唤醒主 App 开始录音
- Darwin Notification 跨进程状态同步（recordingStarted/Stopped/audioLevel/resultReady/stopRecording）
- Keychain (`kSecClassGenericPassword`, service: `com.swordsmanye.voiceflow.shared`) 跨进程数据传递
- App Group UserDefaults/文件 I/O 不可靠（cfprefsd 限制 + 容器 UUID 不一致），已弃用
- textDocumentProxy.insertText() 是文字注入的唯一合法途径
- 录音流程：键盘触发 → URL Scheme 唤醒主 App → 主 App 录音 → 停止后 REST API 转录 → LLM 润色 → Keychain 写入结果 → Darwin 通知键盘 → 键盘读取插入

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

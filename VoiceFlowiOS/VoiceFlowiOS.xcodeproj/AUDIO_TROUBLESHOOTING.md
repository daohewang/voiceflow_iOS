# VoiceFlow 配置检查清单

## ⚠️ 音频录音失败排查指南

如果遇到 `com.apple.coreaudio.avfaudio` 错误，请按以下步骤检查：

---

## 📝 必需的 Info.plist 配置

### 1. 主应用 Info.plist

在主应用的 `Info.plist` 中添加以下权限说明：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>VoiceFlow 需要使用麦克风进行语音输入</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>VoiceFlow 需要使用语音识别功能将您的语音转换为文字</string>
```

### 2. 键盘扩展 Info.plist

在 `VoiceFlowKeyboard` 扩展的 `Info.plist` 中：

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>IsASCIICapable</key>
        <false/>
        <key>RequestsOpenAccess</key>
        <true/>
    </dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.keyboard-service</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).KeyboardViewController</string>
</dict>
```

---

## 🔐 Capabilities 配置

### Xcode 项目设置

1. 选择主应用 Target → Signing & Capabilities
2. 添加 **App Groups**
   - Group ID: `group.com.swordsmanye.voiceflow.ios`

3. 选择键盘扩展 Target → Signing & Capabilities
4. 同样添加 **App Groups**
   - 使用相同的 Group ID: `group.com.swordsmanye.voiceflow.ios`

---

## 🎤 麦克风权限检查

### 在设置中检查权限

1. 打开 iPhone **设置** App
2. 找到 **隐私与安全性** → **麦克风**
3. 找到 **VoiceFlow** 并确保开关是**开启**状态
4. 如果看不到 VoiceFlow，尝试：
   - 完全卸载应用
   - 重新安装
   - 首次启动时允许麦克风权限

---

## 🔧 常见问题解决方案

### 问题 1：音频会话冲突

**症状：** `com.apple.coreaudio.avfaudio` 错误

**解决方法：**
1. 关闭所有其他使用麦克风的应用（录音、语音通话等）
2. 重启 VoiceFlow 应用
3. 如果仍失败，重启手机

### 问题 2：权限未授予

**症状：** "麦克风权限被拒绝"

**解决方法：**
1. 进入 iOS 设置 → 隐私 → 麦克风
2. 找到 VoiceFlow 并开启
3. 返回应用重试

### 问题 3：后台音频配置

**症状：** 应用进入后台后录音停止

**解决方法：**
在主应用 Target → Signing & Capabilities 中：
- 添加 **Background Modes**
- 勾选 **Audio, AirPlay, and Picture in Picture**

### 问题 4：蓝牙耳机问题

**症状：** 使用蓝牙耳机时无法录音

**解决方法：**
- 代码中已配置 `.allowBluetooth` 和 `.allowBluetoothA2DP`
- 确保蓝牙设备已正确连接
- 尝试断开并重连蓝牙设备

---

## 🧪 测试步骤

### 基础测试

1. **安装应用**
   - 使用 Xcode 安装到真机
   - 不要使用模拟器（模拟器不支持麦克风）

2. **首次运行**
   - 启动应用
   - 点击录音按钮
   - 应该会弹出麦克风权限请求
   - 点击"允许"

3. **权限验证**
   - 在首页查看权限状态
   - 应该显示"✅ 麦克风权限已授予"

4. **录音测试**
   - 点击录音按钮
   - 对着麦克风说话
   - 应该能看到音量波形
   - 停止录音后应该能看到识别的文字

### 键盘扩展测试

1. **启用键盘**
   - iOS 设置 → 通用 → 键盘 → 键盘
   - 点击"添加新键盘"
   - 选择 VoiceFlow
   - 打开"允许完全访问"（必需）

2. **使用键盘**
   - 打开任意应用（备忘录、信息等）
   - 切换到 VoiceFlow 键盘
   - 点击麦克风按钮
   - 说话后应该能看到文字出现

---

## 📱 真机测试注意事项

### 必需设备
- **必须使用真实 iOS 设备**（iPhone/iPad）
- iOS 17.0 或更高版本

### Xcode 配置
1. 选择真机作为运行目标
2. 确保开发者证书已配置
3. 修改 Bundle ID 为您的唯一标识符
4. 修改 Team 为您的开发团队

### 首次安装
- 可能需要在 iPhone 设置 → 通用 → VPN与设备管理
- 信任您的开发者证书

---

## 🐛 调试方法

### 查看详细日志

在 Xcode 中运行应用，打开 Console 查看日志：

```
[AudioEngine] AVAudioSession configured successfully
[AudioEngine] Input format: 48000.0Hz, 1 channels
[AudioEngine] Engine started successfully
[RecordingCoordinator] AudioEngine started successfully
```

### 如果看到错误日志

记录完整的错误信息，包括：
- 错误代码
- 错误描述
- 调用栈

---

## 💡 进阶配置

### 音频质量优化

如果录音质量不佳，可以尝试调整 `AudioEngine.swift` 中的参数：

```swift
// 缓冲区大小（值越小延迟越低，但可能不稳定）
bufferSize: 4096  // 可调整为 2048 或 8192

// 采样率（目标格式）
sampleRate: 16000  // ElevenLabs 要求 16kHz
```

### 降低音频延迟

在 `AudioEngine.swift` 中设置更小的缓冲区：

```swift
try audioSession.setPreferredIOBufferDuration(0.005) // 5ms
```

---

## 📞 获取帮助

如果以上方法都无法解决问题：

1. 检查 iOS 版本（需要 iOS 17+）
2. 检查 Xcode 版本（推荐 Xcode 15+）
3. 清理项目：Product → Clean Build Folder
4. 删除应用重新安装
5. 重启设备

---

**最后更新：** 2026年3月18日

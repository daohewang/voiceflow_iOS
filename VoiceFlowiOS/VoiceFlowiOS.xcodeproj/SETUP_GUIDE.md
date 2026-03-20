# VoiceFlow iOS 配置指南

## 📋 必需配置清单

### 1️⃣ 主 App Info.plist 配置

在 **VoiceFlowiOS** target 的 `Info.plist` 中添加以下权限说明：

```xml
<!-- 麦克风权限 -->
<key>NSMicrophoneUsageDescription</key>
<string>VoiceFlow 需要访问麦克风以录制您的语音输入</string>

<!-- 语音识别权限 -->
<key>NSSpeechRecognitionUsageDescription</key>
<string>VoiceFlow 需要使用语音识别将您的语音转换为文字</string>
```

**Xcode 中操作步骤：**
1. 在项目导航器中选择 **VoiceFlowiOS** target
2. 点击 **Info** 标签
3. 点击 **+** 号添加新键：
   - 输入 `Privacy - Microphone Usage Description`
   - Value: `VoiceFlow 需要访问麦克风以录制您的语音输入`
4. 再次点击 **+** 添加：
   - 输入 `Privacy - Speech Recognition Usage Description`
   - Value: `VoiceFlow 需要使用语音识别将您的语音转换为文字`

---

### 2️⃣ 键盘扩展 Info.plist 配置

在 **VoiceFlowKeyboard** target 的 `Info.plist` 中添加：

```xml
<!-- 请求完全访问权限（允许网络和麦克风访问）-->
<key>RequestsOpenAccess</key>
<true/>
```

**Xcode 中操作步骤：**
1. 在项目导航器中选择 **VoiceFlowKeyboard** target
2. 点击 **Info** 标签
3. 点击 **+** 号添加新键：
   - 输入 `RequestsOpenAccess`
   - Type: Boolean
   - Value: YES (勾选)

---

### 3️⃣ App Groups 配置（如需共享数据）

如果主 App 和键盘扩展需要共享数据（如 API Keys），需要配置 App Groups：

#### 主 App (VoiceFlowiOS)
1. 选择 **VoiceFlowiOS** target
2. 点击 **Signing & Capabilities** 标签
3. 点击 **+ Capability** → 选择 **App Groups**
4. 点击 **+** 添加新组：`group.com.swordsmanye.voiceflow.ios`

#### 键盘扩展 (VoiceFlowKeyboard)
1. 选择 **VoiceFlowKeyboard** target
2. 点击 **Signing & Capabilities** 标签
3. 点击 **+ Capability** → 选择 **App Groups**
4. 勾选相同的组：`group.com.swordsmanye.voiceflow.ios`

---

## 🔐 用户权限授予步骤

### 步骤 1：首次运行主 App
当用户首次运行 VoiceFlow 主 App 并尝试录音时：
- 系统会弹出麦克风权限请求
- 用户需要点击「允许」

### 步骤 2：启用键盘
用户需要手动启用自定义键盘：
1. 打开 **设置 → 通用 → 键盘 → 键盘**
2. 点击 **添加新键盘**
3. 选择 **VoiceFlow**

### 步骤 3：授予完全访问权限（重要！）
由于键盘需要访问麦克风和网络，用户必须授予完全访问权限：
1. 打开 **设置 → 通用 → 键盘 → 键盘**
2. 找到 **VoiceFlow** 键盘
3. 开启 **允许完全访问** 开关

**⚠️ 如果不开启此权限，键盘将无法使用语音输入功能！**

---

## 🧪 测试步骤

### 测试主 App 录音
1. 清理项目：`Shift + Cmd + K`
2. 构建项目：`Cmd + B`
3. 运行主 App
4. 点击录音按钮
5. 允许麦克风权限
6. 开始说话测试

### 测试键盘录音
1. 在设备上安装 App
2. 启用键盘并授予完全访问权限（见上述步骤）
3. 打开任意支持文字输入的 App（如备忘录）
4. 切换到 VoiceFlow 键盘
5. 点击麦克风按钮
6. 允许语音识别权限（如弹出）
7. 开始说话测试

---

## ❌ 常见错误及解决方案

### 错误 1: "录音启动失败 com.apple.coreaudio.avfaudio 错误 2003329396"

**原因：**
- 未配置麦克风权限（Info.plist）
- 键盘扩展未开启完全访问权限
- AVAudioSession 配置失败

**解决方案：**
1. ✅ 确认已在 Info.plist 中添加 `NSMicrophoneUsageDescription`
2. ✅ 确认键盘扩展 Info.plist 中有 `RequestsOpenAccess = true`
3. ✅ 确认用户已在设置中开启「允许完全访问」
4. ✅ 重新编译并重新安装 App

### 错误 2: "未识别到语音"

**原因：**
- 网络问题（SFSpeechRecognizer 需要网络）
- 麦克风被其他 App 占用
- 说话声音太小

**解决方案：**
1. 检查设备网络连接
2. 关闭其他使用麦克风的 App
3. 提高音量清晰说话

### 错误 3: "语音识别不可用"

**原因：**
- 未在 Info.plist 中配置语音识别权限
- 用户拒绝了语音识别权限
- 设备不支持或系统限制

**解决方案：**
1. 确认已添加 `NSSpeechRecognitionUsageDescription`
2. 引导用户到 **设置 → 隐私与安全性 → 语音识别** 开启权限
3. 确保 iOS 版本支持（需要 iOS 10+）

---

## 📚 相关文档

- [Apple - Requesting Authorization to Capture Audio](https://developer.apple.com/documentation/avfoundation/audio/requesting-authorization-to-capture-audio)
- [Apple - SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
- [Apple - Custom Keyboard Extensions](https://developer.apple.com/documentation/uikit/keyboards_and_input/creating_a_custom_keyboard)

---

## ✅ 配置完成检查清单

使用此清单确保所有配置正确：

- [ ] 主 App Info.plist 包含 `NSMicrophoneUsageDescription`
- [ ] 主 App Info.plist 包含 `NSSpeechRecognitionUsageDescription`
- [ ] 键盘扩展 Info.plist 包含 `RequestsOpenAccess = true`
- [ ] 主 App 配置了 App Groups（如需要）
- [ ] 键盘扩展配置了相同的 App Groups（如需要）
- [ ] 代码中正确处理权限请求
- [ ] 已测试主 App 录音功能
- [ ] 已在真机上测试键盘录音功能
- [ ] 已确认用户授予了完全访问权限

---

**配置完成后，记得清理构建并重新安装 App！** 🚀

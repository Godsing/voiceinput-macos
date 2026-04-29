# VoiceInput — macOS 菜单栏语音输入法

一款 macOS 14+ 专属菜单栏轻量语音输入应用。按住 Fn 键说话，松开后文字自动插入光标位置。

## 功能

- **按住 Fn 录音** — 按住 Fn 键即开始录音，屏幕底部出现胶囊浮窗，实时显示波形和转写文字
- **松开插入文字** — 松开 Fn 键，转写完成的文字自动粘贴到当前光标位置
- **多语言识别** — 支持简体中文、繁体中文、English、日本語、한국어，从菜单栏切换
- **剪贴板保护** — 输入完成后自动恢复原有剪贴板内容
- **自定义配置** — 可配置 DashScope API Key、模型名称
- **轻量驻留** — 仅菜单栏图标，无 Dock 图标；空闲时自动断开连接，CPU <1%

## 用户指南

### 安装

```bash
cd VoiceInput
make install
```

安装后从 `/Applications/VoiceInput.app` 启动，或直接开发运行：

```bash
make run
```

### 首次配置

1. 启动后 macOS 会请求**麦克风**和**辅助功能**权限，请全部允许
2. 点击菜单栏麦克风图标 → **Settings…**
3. 输入 DashScope API Key → 点击 **Test** 验证 → 点击 **Save**
4. 配置完成

### 使用方法

1. 在任意应用中将光标置于文本输入处
2. **按住 Fn 键**，对着麦克风说话
3. 屏幕底部出现胶囊浮窗，实时显示波形和转写文字
4. **松开 Fn 键**，转写文字自动插入光标位置

### 切换语言

点击菜单栏图标 → 选择识别语言：

| 选项      | 语言   |
| ------- | ---- |
| 简体中文    | 默认   |
| 繁体中文    | 繁体转写 |
| English | 英文转写 |
| 日本語     | 日文转写 |
| 한국어     | 韩文转写 |

选择会持久保存，重启后保留。

## 架构

```
VoiceInput/Sources/VoiceInput/
├── App/
│   ├── AppDelegate.swift          # 应用入口，录音会话协调
│   └── MenuBarController.swift    # 菜单栏状态图标与菜单
├── Audio/
│   └── AudioCaptureEngine.swift   # AVAudioEngine 录音、PCM 转换、RMS 计算
├── Input/
│   ├── GlobalKeyMonitor.swift     # Fn 键全局拦截 (CGEvent tap)
│   ├── TextInjector.swift         # 文字注入 + 剪贴板保存/恢复
│   └── InputMethodManager.swift   # CJK 输入法检测与切换
├── Overlay/
│   ├── CapsuleOverlayPanel.swift  # 浮窗面板 (NSPanel + NSVisualEffectView)
│   └── WaveformView.swift         # 5 柱波形动画 (CVDisplayLink)
├── Settings/
│   ├── ConfigurationStore.swift   # 配置持久化 (UserDefaults + Keychain)
│   └── SettingsWindow.swift       # SwiftUI 设置面板
└── WebSocket/
    ├── RealtimeClient.swift       # WebSocket 客户端，接收循环，重连
    └── SessionConfig.swift        # 协议消息构建器
```

### 核心流程

```
Fn 按下 → GlobalKeyMonitor 拦截
  → AudioCaptureEngine 开始录音 (16kHz/16bit/mono)
  → RealtimeClient 发送 PCM 音频流 (Base64)
  → CapsuleOverlayPanel 显示波形 + 流式文字
Fn 松开 → RealtimeClient.commit + createResponse
  → 等待 response.done
  → TextInjector 保存剪贴板 → 切换输入法 → 模拟 Cmd+V → 恢复剪贴板
  → CapsuleOverlayPanel 隐藏
```

### 技术栈

| 组件        | 技术                                                                     |
| --------- | ---------------------------------------------------------------------- |
| 语言        | Swift 5.9+，macOS 14 SDK                                                |
| 构建系统      | Swift Package Manager + Makefile                                       |
| 音频捕获      | AVAudioEngine (installTap)                                             |
| WebSocket | URLSessionWebSocketTask                                                |
| UI        | AppKit (NSPanel, NSStatusBar, NSVisualEffectView) + SwiftUI (Settings) |
| 配置存储      | UserDefaults + Keychain                                                |
| 测试        | XCTest                                                                 |

## 开发

### 构建 & 运行

```bash
cd VoiceInput
make build          # Release 构建
make run            # 构建并运行
make test           # 运行测试
make clean          # 清理构建产物
make install        # 安装到 /Applications
```

### 运行测试

```bash
make test
```

测试结构：

```
VoiceInputTests/
├── Unit/
│   ├── AudioCaptureEngineTests.swift
│   ├── ConfigurationStoreTests.swift
│   ├── SessionConfigTests.swift
│   └── TextInjectorTests.swift
└── Integration/
    ├── AudioCaptureIntegrationTests.swift
    └── WebSocketIntegrationTests.swift
```

- 单元测试：验证各模块的独立逻辑（配置读写、消息构建、剪贴板快照等）
- 集成测试：验证音频引擎启动/停止、WebSocket 状态机
- 音频集成测试在无麦克风权限时会自动跳过

### 项目规范

**代码质量**

- 每个模块职责单一，文件与目录对应
- 函数体不超过 40 行
- 不添加超出任务需要的抽象或功能

**测试要求**

- 遵循 TDD：先写测试，再写实现
- 测试覆盖率目标 80%+
- 测试文件结构与源码结构对应

**安全**

- API Key 仅存 Keychain，不写入 UserDefaults 或日志
- WebSocket 使用 Bearer 认证
- 不在错误信息中暴露敏感数据

**性能预算**

| 指标         | 目标      |
| ---------- | ------- |
| 浮窗出现延迟     | < 200ms |
| 首个转写 token | < 1s    |
| 文字注入延迟     | < 500ms |
| 空闲内存占用     | < 50MB  |
| 空闲 CPU     | < 1%    |

### 关键设计决策

- **CGEvent tap** 而非 NSEvent.addGlobalMonitor：需要拦截（而不仅是监听）Fn 键以阻止 emoji 面板弹出
- **URLSessionWebSocketTask** 而非第三方库：零依赖，Apple 原生支持
- **Clipboard save/restore + Cmd+V** 而非 Accessibility AXTextInsertion：兼容性更好，覆盖几乎所有应用
- **Carbon TIS API** 而非 NSTextInputContext：全局输入法切换需要 Carbon API，NSTextInputContext 绑定 responder chain
- **Lazy WebSocket**：首次录音时才建立连接，空闲 60s 自动断开

### WebSocket 协议

使用阿里云 DashScope Qwen-Omni-Realtime API，Manual Mode：

```
连接 → session.update (配置文字模式+语言) → [Fn按下] 循环发送 audio.append
→ [Fn松开] commit → createResponse → 接收 text.delta 流 → response.done → 注入文字
```

完整协议文档见 `specs/001-voice-input-app/contracts/websocket-protocol.md`。

## 许可

本项目采用 MIT License。完整条款见 [LICENSE](LICENSE)。

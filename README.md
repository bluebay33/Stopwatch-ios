# MarkLap（iPhone）

原生 SwiftUI iPhone 秒表。MarkLap 专注于精确计时和清晰的分段标记：

- 开始、暂停、继续与清零
- 运行中记录分段；最新分段排在最上方
- 每 0.01 秒刷新，显示到百分之一秒
- 通过系统触感反馈确认开始、暂停、分段和清零

## iOS 平台限制

iOS 不允许第三方 App 可靠地接管硬件音量加/减键。为避免意外改变系统音量以及 App Store 审核风险，此版使用屏幕的 Start/Pause 与 Lap/Reset 控件；不提供 Android 版的音量键模式。

## 打开与运行

1. 将 `volume-stopwatch-ios` 文件夹复制到 Mac。
2. 用 Xcode 16 或更高版本打开 `VolumeStopwatch.xcodeproj`。
3. 在 Signing & Capabilities 选择你的 Apple Development Team，再选择 iPhone 或模拟器运行。

部署目标为 iOS 17.0。云端 TestFlight 构建见 `codemagic.yaml`。

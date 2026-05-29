# DaaiZekBro（大只仔）

为个人力量训练者设计的 iOS 训练记录 App，支持模板管理、组次记录、休息计时与训练历史导出。

## 功能

- 训练模板快速启动与多模板管理
- 每组记录重量、次数、RPE；支持单侧动作（左/右侧）
- 组间休息倒计时 + 本地通知，离开 App 也能收到提醒
- 训练历史月度分组、批量 CSV 导出（16 列，含 e1RM 等衍生指标）
- 全局 kg / lb 单位切换，输入时自动转换存储为 kg

## 技术栈

iOS 17.0+，Swift，SwiftUI，SwiftData，无三方依赖

## 本地运行

前提：Xcode 15+，iOS 17 Simulator

1. 打开 `DaaiZekBro.xcodeproj`
2. 选择 iPhone Simulator，按 ▶ 运行

## 运行测试

日常验证优先运行 unit-only fast run，避免默认 full run 同时执行 UI tests 后在 XcodeBuildMCP 中超时。

```bash
xcodebuild test -project DaaiZekBro.xcodeproj -scheme DaaiZekBro \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData \
  -only-testing:DaaiZekBroTests
```

UI tests 单独运行：

```bash
xcodebuild test -project DaaiZekBro.xcodeproj -scheme DaaiZekBro \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData \
  -only-testing:DaaiZekBroUITests
```

完整回归可运行 full run，但不建议作为 XcodeBuildMCP 的默认/fast 验证路径：

```bash
xcodebuild test -project DaaiZekBro.xcodeproj -scheme DaaiZekBro \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData
```

如果本机没有 `iPhone 17 Pro` simulator，可用 `xcrun simctl list devices available` 查看可用设备后替换 destination。

## 项目结构

```
DaaiZekBro/
├── App/           # 入口、路由
├── Models/        # SwiftData 模型
├── Features/      # Templates · CurrentWorkout · ExerciseLogging · History · Settings
├── Services/      # CSV 导出、Session 生命周期、通知调度
└── DesignSystem/  # 颜色、字体、间距 token、UI 组件
```

## 版本

当前版本 v0.11 — 详见 [CHANGELOG.md](CHANGELOG.md)

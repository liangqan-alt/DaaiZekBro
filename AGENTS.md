# AGENTS.md

## 项目上下文
- 本仓库是 iOS 应用，使用 Swift、SwiftUI、SwiftData。
- Xcode project 为 `DaaiZekBro.xcodeproj`；默认 scheme 为 `DaaiZekBro`。

## 变更策略
- 优先最小改动，仅修改完成当前任务必需的代码。
- 禁止无关重构、风格 churn、跨模块扩散修改或顺手优化。
- 若需要大范围架构改动，先停止编码，说明原因、范围、风险与方案，等待确认。
- 改动必须易审查、易验证、易回滚。

## 架构与代码约束
- 优先遵循现有目录、命名、SwiftUI 数据流和依赖管理方式。
- 非平凡功能优先采用 MVVM-style 分离；不要为简单 SwiftUI View 强行新增 ViewModel、Repository 或 protocol。
- View 应聚焦展示、用户意图、导航和局部 UI 状态。
- View 不应实现网络、同步、迁移、导入导出、复杂业务规则或长事务；简单 `@Query` 展示和 UI 驱动的 SwiftData 小操作可以保留在 View。
- 副作用依赖（存储、网络、时间、UUID、日志、分析）应可替换；在不破坏现有风格时优先使用构造或环境注入。
- 新的大功能优先按 feature 组织；`Core/`、`Shared/` 仅在已有或明确引入时使用。

## 并发、错误与验证
- 新异步代码优先使用 Swift Concurrency；UI 可观察状态更新必须 MainActor-safe。
- 避免无清晰生命周期、错误处理和取消行为的 fire-and-forget `Task`。
- 显式处理错误；禁止静默吞错、强制 unwrap 或未说明的 silent fallback。
- 行为变更或 bug fix 应补充相关测试；无法测试需在最终回复说明。
- 完成前运行相关既有检查；优先使用可用 simulator 运行 `xcodebuild test -scheme DaaiZekBro`，并说明实际命令和结果。
- 仅在仓库已有对应配置且工具可用时运行 `swiftformat .` 或 `swiftlint`；不要擅自新增 formatter/linter 配置。

## 边界
- 未经明确批准，不新增三方依赖，不修改签名、entitlements、权限、隐私清单、CI/CD 或发布配置。
- 更靠近被编辑文件的嵌套 `AGENTS.md` 可覆盖本文件。

## XcodeBuildMCP
- 使用前检查 defaults；缺省时使用 `DaaiZekBro.xcodeproj`、scheme `DaaiZekBro` 和可用 iPhone simulator。
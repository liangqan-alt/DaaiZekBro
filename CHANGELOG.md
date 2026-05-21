# Changelog

本文件记录项目中的显著变更。
格式基于 Keep a Changelog，版本遵循 Semantic Versioning。

## [Unreleased]

## [V0.1] - 2026-05-21

### 新增
- 定义训练记录 MVP 的 SwiftData 数据模型，包括动作、模板、训练 session、训练组记录与单侧动作枚举。
- 添加 19 个预置训练动作与 6 个训练模板的 Seed Data，并支持按名称去重写入与模板动作关系修复。
- 增加模板列表入口，可按固定顺序展示 6 个训练模板并从模板开始训练。
- 增加当前训练页，展示训练时长、模板动作列表、默认休息时间和当前 session 内已记录组数。
- 增加 WorkoutSession 生命周期管理，支持创建、结束、丢弃训练，并处理未结束训练冲突。
- 增加「继续当前训练」入口，支持通过 `templateNameSnapshot` 在模板关系缺失时恢复动作列表。
- 增加占位训练记录页，为后续动作组记录流程提供导航入口。
- 补充 in-memory SwiftData 测试，覆盖 Seed Data、Session 生命周期、模板 fallback、组数统计和未结束训练约束。

### 变更
- 将默认 Xcode 模板中的 `Item` 示例模型替换为训练记录 App 的实际 SwiftData schema。
- 将临时 PR-01 Seed Data 验收界面替换为训练记录 MVP 的模板列表与当前训练导航流程。

# Changelog

本文件记录项目中的显著变更。
格式基于 Keep a Changelog，版本遵循 Semantic Versioning。

## [Unreleased]

### 新增
- 定义训练记录 MVP 的 SwiftData 数据模型，包括动作、模板、训练 session、训练组记录与单侧动作枚举。
- 添加 19 个预置训练动作与 6 个训练模板的 Seed Data，并支持按名称去重写入与模板动作关系修复。
- 增加临时 PR-01 验收界面，用于显示 Seed Data 写入状态、动作数量、模板数量和各模板动作数。
- 补充 in-memory SwiftData 测试，覆盖 Seed Data 写入、幂等性、重复数据收敛、单侧动作标记和模板动作数量。

### 变更
- 将默认 Xcode 模板中的 `Item` 示例模型替换为训练记录 App 的实际 SwiftData schema。

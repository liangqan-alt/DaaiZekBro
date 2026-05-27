# DaaiZekBro 架构分级修订方案
版本：v1.9

## Summary

项目当前处于可继续开发的状态，`App / Features / Services / Models / DesignSystem` 分层清晰，核心业务有 service 和测试兜底。但正处在临界点：再继续加功能，如果不收一收边界，复杂度会主要堆到大 View、`Models.swift`、`Services/` 里。

**当前没有确认必须阻断发布的 P0 架构项。** 若出现已有真实旧 store 无法打开的证据，才需升级为"补旧 schema 快照 + 真实 store migration 测试"。

涉及 schema、cascade、导航、identity 的高风险轴默认分开处理；其他改动按范围和回滚粒度决定是否合并。

---

## P1 — 优先处理，各项独立 PR

### P1-1 建立 schema 单一来源

**当前优先目标：** 生产容器、Preview 容器、测试 helper 共享同一模型清单，不再各自手写。模型清单变更时，所有使用方同步更新。

**验收条件：** 全仓模型类型列表只在一处声明；添加或移除模型类型时，只需改一处。

**migration 入口（可选，条件合并）：** 可在同 PR 内引入空 migration plan 入口作为后续 schema 变更的声明点。引入后，合并前须完成以下验证：

- 用 PR 变更前的 main 基线构建（或最近一个已发布版本）写入至少一条训练记录，生成持久化 store；记录所用版本号或 commit hash
- 用引入 migration 入口后的构建打开同一 store
- 通过标准：启动无失败、历史训练记录可读取

验证失败时，migration 入口推迟到首次真实 schema 变更前处理，不阻塞清单去重合并。

---

### P1-2 替换 `fatalError`，改为可诊断的失败界面

**约束：**

- `ModelContainer` 初始化失败时不崩溃，向用户展示可读的错误信息
- 失败分支不依赖 `modelContext` 环境，不自动擦除本地数据
- 成功与失败分支在 App 入口明确分叉，失败路径可独立渲染
- PR 必须提供可重复触发失败分支的验证方式并记录结果；验证方式不限（注入失败的容器工厂、测试专用入口、手动异常 store 等），由 PR 自行选择

---

### P1-3 冲突解决事务离开 View

**问题：** `TemplateListView` 内的"结束当前 session 并新建 / 丢弃并新建"把业务事务（end/discard + 取消通知 + 创建 session）和导航混在一起，通知取消是静态调用，无法测试。

**约束：**

- 冲突解决的业务事务（结束或丢弃旧 session、创建新 session、取消通知）离开 View
- 冲突解决整体成功后才取消通知；若 PR 采用多阶段保存，须在 PR 内声明每阶段失败时的数据状态和通知状态
- 整体失败时不导航、不取消通知
- 通知取消的依赖可被替换，便于测试
- View 只保留弹窗逻辑和导航触发

**失败路径语义：** 旧 session 已结束或丢弃后，若新 session 创建失败，不取消通知、不导航；旧 session 的最终状态（已结束或已丢弃）由 PR 明确声明，并有测试覆盖该路径。

---

### P1-4 高频查询路径避免无界全表扫描

**问题：** 训练中的核心路径全部全表 fetch 后内存过滤，随数据量线性增长。主要入口按查询语义分三类：

**session 内 set 查询**（查询范围为指定 session 内的 set）：

| 调用点 | 问题类型 | 最小约束 |
|---|---|---|
| `WorkoutSetLogging.setsForExercise` | 全取 `WorkoutSet` 后内存过滤 | 先按 session 范围缩小候选集；旧数据 `exerciseNameSnapshot` 为空时在小集合内做 `exercise?.name` fallback，不退回无界扫描 |

**open-session lifecycle 查询**（查找当前未结束的 session）：

| 调用点 | 问题类型 | 最小约束 |
|---|---|---|
| `WorkoutSessionLifecycle.currentOpenSession` | 全取 `WorkoutSession` 后内存过滤 | 只取未结束的 session，多个时取最近启动的 |

**跨 session 历史查询**（查询范围跨历史记录）：

| 调用点 | 问题类型 | 最小约束 |
|---|---|---|
| `WorkoutSetLogging.lastSet` | 全取 `WorkoutSet` 后排序取首 | 不改变跨 session 历史预填语义；避免无界扫描，具体优化策略由 PR 论证 |

**约束：**

- 表中所有入口改造后不再做无条件全表 fetch；bounded 策略由 PR 说明
- session 内 set 查询：旧数据 `exerciseNameSnapshot` 为空时，先按 session 范围缩小候选集，再在小集合内做 `exercise?.name` fallback，不退回无界扫描
- `lastSet`：跨 session 历史预填语义不变，优化后结果与改造前一致

**本次落地策略：**

- `setsForExercise` 先按 `WorkoutSet.session?.id` 查询候选，再在 session 小集合内沿用 `exerciseNameSnapshot` 优先、空 snapshot 回退 `exercise?.name` 的语义
- `currentOpenSession` 查询限定 `endedAt == nil`，按 `startedAt` 倒序并限制返回 1 条，异常多个 open session 时取最近启动的
- `lastSet` 保持 identity 与 name fallback 两个入口分离，先按动作身份或名称 fallback 谓词缩小候选，再按 `completedAt` 倒序分页；`Side?` 继续在分页结果内过滤，避免 SwiftData 可选 enum 谓词的运行时风险

**验收条件：** 上述行为在查询改造前后一致；改造后各入口不做无条件全表 fetch；相关测试覆盖 fallback 路径和多 open session 情况。

---

## P2 — 顺手改 / 独立 PR

### P2-1 `TrainingDayOverride` 按唯一键精确查询

**约束：** `upsert` / `reset` 操作改为按 `cycleDateKey` 精确查询，利用已有的 `@Attribute(.unique)` 唯一索引，不做全表扫描后内存匹配。

---

### P2-2 Models.swift 只承载模型定义

**原则：** `Models.swift` 内的业务写操作方法和纯展示逻辑与 `@Model` 定义混放。仅当当前 PR 修改了该逻辑，且该逻辑阻碍测试或复用时，才将其迁出至合适位置；否则可暂留，不做纯整理性搬迁。落点由 PR 根据代码形状决定，不预设 repository 层。

---

### P2-3 大 View 按职责提取子 View（顺手）

**原则：** 改到 `TemplateListView`（1018 行）或 `TrainingScheduleView`（1155 行）时，提取当前 PR 实质修改的区域为独立子 View；行为不变；边界和命名由 PR 根据代码形状决定；不做纯重命名 churn。

---

### P2-4 消除展示刷新中的手动 invalidation（独立 PR）

**问题：** `TrainingSchedulePresentation` 内部重新 fetch 调用方已通过 `@Query` 持有的数据，`scheduleDataVersion` hash 是绕过这一问题的脆弱桥接，随记录数增长且对变更不敏感。

**约束：**

- 展示数据的刷新依赖来源必须可追踪、可声明，不依赖手动 hash invalidation；消除 `scheduleDataVersion` 这类手动 invalidation
- 默认方向：优先复用调用方已有 `@Query` 数据，而不是在 Presentation 层重新 fetch；允许 adapter、provider 等方案，具体数据流由 PR 论证
- PR 必须声明各刷新依赖来源及其触发条件，并用"变更或删除模板后今日计划卡刷新正确"作为行为证明

**非目标：** 本项不重写 schedule engine，不改变计划计算逻辑。

---

### P2-5 消除当前导航直接依赖的痛点（独立 PR）

**问题：** 部分 Feature View 直接持有并操作 app-level `path: Binding<[AppRoute]>`，`TrainingScheduleView` 已有 `usesExternalPath` bool 作为补丁，是耦合已成问题的信号。

**约束：** 优先消除当前直接依赖 app-level path 的痛点；可用局部 closure、intent 或其他轻量方式；不要求一次性统一所有 Feature View，不引入全局 coordinator；具体解耦方式由 PR 论证。

**最小出口：** PR 必须声明本次处理的入口和非目标；被处理入口不再直接 mutate app-level `path`，导航行为保持不变。

---

## P3 — 加具体新功能前阻塞性检查

### P3-1 解决 `exerciseName` 作为唯一 identity 的脆弱性

**触发条件：** 凡改动 session 内路由、通知 payload、set 归属、同名动作处理，或 session 创建后模板动作名或动作列表被编辑影响当前 session 的行为，发布前需评估是否需要先完成本项。

**评估出口：** 触发范围内的 PR 若评估后不实施 P3-1，必须在 PR 描述中声明以下四条行为不变量未被破坏，并列出覆盖方式或不适用理由；否则视为未通过评估：

1. 同一 session 内存在同名动作时，路由和通知仍可区分各自目标
2. 计数和删除重编号不因同名动作而串线
3. 通知 payload 对应的 session 已被删除时不崩溃
4. session 创建后模板动作名或动作列表被编辑，当前 session 的 route / notification / set 归属不漂移

**行为不变量（实施时验收）：** 上述四条在路由、通知 payload、set 记录各自的边界内成立；各边界不要求强制共用同一 key，以不违反上述不变量为准。

**相邻问题（独立 PR）：** `WorkoutSessionLifecycle.resolvedTemplate` 的模板名字 fallback 属于历史解析问题，根因与 exercise identity 相同，但改造范围独立；可同期处理，也可单独 PR。

**能力边界：** session 路由和通知只要求 session-local identity；历史展示要求 snapshot 可读；跨 store / 重装属于未来独立能力，不纳入本项验收。

**设计决策（待 PR 论证）：** 以下候选方案各有限制，不预设选型：

| 候选 | 限制 |
|---|---|
| session-scoped index：`(sessionID, exerciseOrderIndex)` | `exerciseOrderIndex` 在 session 生命周期内必须稳定；重排 exercise 会破坏 identity |
| snapshot 的 `persistentModelID` | 跨 store 重建（重装 App）后不稳定，不适合持久化路由 key |
| `Exercise` 上增加全局 `stableID`（schema 变更） | 需走 migration；若选择此方案，需定义 stableID 或 session-local 映射在 snapshot、set、通知 payload、route 中如何解析和传递；不要求所有边界持久化同一 key |

**反例测试（选型时必须覆盖）：** 同一 session 内存在同名动作；session 创建后模板动作名或动作列表被编辑；通知 payload 对应的 session 已被删除。

---

### P3-2 `WorkoutSet` cascade 改造（在 migration 入口落地后实施）

**问题：** `WorkoutSession` 目前对 `WorkoutSet` 没有 cascade relationship，删除 session 时需手工全表 fetch 再逐一删除。

**约束：** 将删除规则声明在关系上，由数据层管理级联删除。

**依赖：** 此项属于 schema 变更，必须在 migration 入口合并后，以独立 migration stage 实施；migration 入口落地只解除合并阻塞，不代表本 PR 自动安全。

**PR 必须验证（含迁移前已有数据）：**

- 验证 fixture 必须包含至少一个迁移前已存在的 session 和相关 sets
- 新 schema 打开后，历史 sets 可读且仍归属原 session
- 删除该 session 后，历史 sets 被级联删除
- 单独删除 set 不影响 session
- 以上行为有回归测试覆盖

---

### P3-3 顺手维护项

- `scheduleDataVersion` 相关 hash 在 P2-4 完成后删除
- 重复的排序 helper 统一至合适位置
- 内联的小型 `some View` computed property 按需提取

---

## 需要形成的能力

以下能力边界需要在对应分级落地后确认，具体类型名和文件由实现收敛后补充：

| 能力 | 对应分级 |
|---|---|
| schema 单一来源：生产、Preview、测试使用同一模型清单 | P1-1 |
| migration 入口：schema 变更有声明点，不再静默升级 | P1-1（条件合并） |
| 可测试的冲突解决边界：通知取消依赖可替换，事务离开 View | P1-3 |
| 旧数据语义不变：高频查询改造后 fallback 路径有回归覆盖 | P1-4 |
| 展示刷新来源清晰：消除手动 invalidation 桥接 | P2-4 |
| session-local exercise identity：同名动作可区分；模板动作名或动作列表编辑后，route / notification / set 归属不漂移 | P3-1 |

---

## Test Plan

| 对应条目 | 覆盖要点 |
|---|---|
| P1-1（清单去重） | 模型清单变更时只改一处；Preview 和测试 helper 与生产容器使用同一列表 |
| P1-1（migration 入口） | 仅当同 PR 引入 migration 入口时执行：用变更前 main 基线（或最近已发布版本）生成的旧 store，新构建打开无失败，历史记录可读；记录所用版本号或 commit hash |
| P1-2 | 容器初始化失败时展示错误界面，不崩溃，不擦除数据；PR 提供的失败分支验证方式已执行并记录结果 |
| P1-3 | 继续当前、结束并新建、丢弃并新建；整体成功后通知取消被触发；整体失败时不触发、不导航；旧 session 已结束后新 session 创建失败时状态符合 PR 声明 |
| P1-4 | 改造后各入口不做无条件全表 fetch；open session 有多个时取最近启动的；`exerciseNameSnapshot` 为空的旧 set 在查询改造前后结果一致；`lastSet` 改造前后跨 session 历史预填结果一致 |
| P2-1 | `upsert` / `reset` 按唯一键精确命中；重复 key 时不新增记录 |
| P2-4 | 变更或删除模板后今日计划卡刷新正确；`scheduleDataVersion` 不再存在 |
| P2-5 | PR 声明处理入口和非目标；被处理入口不再直接 mutate app-level path；导航行为保持不变 |
| P3-1 | 同名动作在同一 session 内可区分；计数和删除重编号不串线；session 创建后模板动作名或动作列表被编辑，route / notification / set 归属不漂移；通知 payload 对应 session 已删时不崩溃 |
| P3-2 | 迁移前已有的 session 和 sets 在新 schema 下可读且归属正确；删该 session 后历史 sets 被级联删除；删 set 不影响 session |

回归命令：`xcodebuild test -scheme DaaiZekBro`；若模拟器不可用，记录失败原因和已运行的替代检查。

---

## Assumptions

1. 当前没有已知线上旧 store 启动失败证据，因此不设 P0；引入 migration 入口的 PR 合并前需完成旧 store 兼容性验证，未执行时不应声称无 migration 发布风险。
2. 不默认擦除用户本地训练数据。
3. 涉及 schema、cascade、导航、identity 的高风险轴默认分开处理；其他改动按范围和回滚粒度决定是否合并。
4. `WorkoutSet cascade` 属于 schema 变更，必须在 migration 入口建立后才能实施；migration 入口落地不代表 cascade PR 自动安全。

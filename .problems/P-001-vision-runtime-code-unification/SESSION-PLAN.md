# P-001 Session Plan

- Problem: `P-001-vision-runtime-code-unification`
- Current Session: none (`S001` closed)
- Next Session: `S002 source-baseline-verification`
- Planning horizon: `S001`～`S020`

## Scope

```text
统一DMS及其依赖的基础库，支持Rockchip与HiSilicon。
BSD、VMS及其他业务暂不在P-001中实施，但架构不能阻碍其后续接入。
```

## Roadmap

`S001`～`S009`相对确定；实现阶段会根据审计结果拆分、合并或跳过。

| Session | 状态 | 功能 | 结束条件 | 实际产物 |
| --- | --- | --- | --- | --- |
| S001 | closed | Problem 初始化与路线图 | AGENTS、脚本、README、Manifest、Session Plan可用 | `AGENTS.md`；`tools/problem-session`；`README.md`；`manifests/source-baselines.yaml`；`SESSION-PLAN.md`；S001 Handoff |
| S002 | planned | 源基线验证 | 所有路径、分支、commit、角色和导入策略经过验证 | — |
| S003 | planned | 现有文档证据复核 | 既有6份DMS文档标记已验证、待验证和失效结论 | — |
| S004 | planned | 构建与依赖审计 | 两个平台的构建入口、依赖库、SDK、模型和配置清单完成 | — |
| S005 | planned | 调用链与运行时审计 | DMS线程、状态、内存、回调、前后处理和平台耦合明确 | — |
| S006 | planned | 统一范围决策 | 明确保留、迁移、重构、重写、废弃及本Problem非目标 | — |
| S007 | planned | 目标架构与目录设计 | `src/base`、`src/runtime`及平台层职责确定 | — |
| S008 | planned | 接口与生命周期设计 | 数据结构、初始化、处理、释放、错误码、线程和内存所有权确定 | — |
| S009 | planned | 迁移顺序与验收矩阵 | 每个模块的来源、目标位置、依赖、验收和回滚方式明确 | — |
| S010 | planned | 构建骨架与测试框架 | 根构建入口、平台工具链和最小测试框架可运行 | — |
| S011 | planned | 日志与内存加密基础库 | 公共接口完成，原平台实现能够接入 | — |
| S012 | planned | 前处理统一 | RGA、AIPP及必要的CPU路径边界明确并实现 | — |
| S013 | planned | 推理公共层 | 统一推理接口、Tensor描述、生命周期和错误处理完成 | — |
| S014 | planned | Rockchip推理后端 | RKNN后端编译、运行和基线对齐通过 | — |
| S015 | planned | HiSilicon推理后端 | OM/AIPP后端编译、运行和基线对齐通过 | — |
| S016 | planned | 目标检测与辅助能力 | object detection、blur、keypoint按审计范围迁移完成 | — |
| S017 | planned | DMS公共运行时 | 平台无关的DMS流程、状态和业务规则完成 | — |
| S018 | planned | Rockchip/HiSilicon集成 | 两个平台分别完成DMS端到端接入 | — |
| S019 | planned | 跨平台验证 | 精度、性能、内存、稳定性、接口和出包验证完成 | — |
| S020 | planned | 留存与Problem关闭 | 文档、决策、遗留项、迁移记录和关闭条件完成 | — |

## 管理规则

- 不预先创建未来 Session 文件。
- planned 只表示当前预测，不表示不可调整。
- 每次启动前细化当前 Session 的 Objective 和结束条件。
- 已关闭的 Session 不重新编号。
- 如果一个 Session 超出合理上下文，应关闭当前 Session并新增下一编号。
- 如果某项不再需要，将其标记为 skipped，不删除历史记录。
- 每次关闭前更新本计划中的状态、实际产物和下一 Session。
- SESSION-PLAN.md 的修改进入该 Session 的功能或文档提交。
- tools/problem-session close 仍然只提交当前 Session Handoff。

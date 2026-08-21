# AGENTS.md

## 1. Repository Purpose

本仓库用于建设统一、可部署、可验证的算法运行时系统，集中管理：

* 推理、图像处理、目标检测等基础库；
* DMS、BSD、VMS等业务运行库；
* PC、Rockchip、HiSilicon等平台实现；
* 构建、测试、版本和发布相关工具；
* 当前代码统一Problem的状态、证据和迁移记录。

当前首要任务是：

```text
P-001：统一Rockchip与HiSilicon的DMS代码，
包括推理库、目标检测库等基础能力和DMS业务实现。
```

本仓库不负责模型训练、数据集管理和独立模型研究。

---

## 2. Instruction Scope

本文件适用于整个仓库。

如果子目录后续包含自己的`AGENTS.md`，子目录规则可以细化本文件，但不得违反以下全局约束：

* 旧源码仓库保持只读；
* 未确认职责前不得迁移代码；
* 未通过Commitment Gate不得进入大规模实现；
* 未取得外部验证证据不得声称完成；
* 不得破坏现有未相关修改。

---

## 3. Authoritative Context

开始工作前，按以下顺序读取相关内容：

1. 根目录`README.md`；
2. 当前Problem记录；
3. 当前问题的`WORKFLOW.json`工作流实例；
4. `manifests/source-baselines.yaml`；
5. 与当前任务直接相关的`docs/`文档；
6. 目标模块的构建文件、接口和源码；
7. 相关测试、日志和版本Manifest。

不要一次加载全部文档。只读取当前任务所需内容。

以下内容分别承担不同职责：

| 内容                                | 职责              |
| --------------------------------- | --------------- |
| `README.md`                       | 仓库长期定位和稳定规则     |
| `AGENTS.md`                       | Agent操作边界       |
| `manifests/source-baselines.yaml` | 旧代码来源和固定Git基线   |
| Problem记录                         | 当前状态、证据、决策和下一步  |
| `WORKFLOW.json`                    | 工作流节点、依赖、状态、门禁和执行尝试 |
| `docs/`                           | 已确认并需要长期维护的设计知识 |
| Git历史                             | 代码变化、审查和回滚依据    |
| 测试结果                              | 外部验证证据          |

聊天记录和Agent总结不能代替上述工程资产。

---

## 4. Source Repository Safety

`manifests/source-baselines.yaml`中声明的旧仓库默认是只读证据源。

禁止在这些仓库中执行：

```text
修改源码
创建或删除文件
切换分支
reset
clean
rebase
commit
push
删除或移动worktree
```

禁止为了查看指定Commit而直接改变旧仓库当前工作区。

应优先使用只读Git命令验证基线和读取内容，例如：

```bash
git -C <repository-root> rev-parse --show-toplevel
git -C <repository-root> cat-file -e '<commit>^{commit}'
git -C <repository-root> cat-file -e '<commit>:<path>'
git -C <repository-root> show '<commit>:<path/to/file>'
git -C <repository-root> ls-tree -r --name-only '<commit>' -- '<path>'
```

如果指定路径、分支或Commit不存在：

1. 停止依赖该来源进行后续判断；
2. 记录实际命令和错误；
3. 将状态保持为`pending-validation`或标记为`invalid`；
4. 报告需要补充的信息；
5. 不得自行选择相似目录代替。

---

## 5. Evidence Rules

所有关于旧代码的关键结论必须引用证据。

有效证据包括：

* Git仓库和完整Commit；
* Commit中的源码路径；
* 具体接口、函数或类型；
* CMake、Makefile或构建脚本；
* 调用关系；
* 测试命令及输出；
* 板端日志；
* 固定输入输出；
* 性能和精度数据。

输出中必须区分：

```text
Confirmed：已有直接证据支持
Inferred：根据多个证据推断，但尚未直接验证
Unknown：当前证据不足
Rejected：已经被反证否定
```

禁止：

* 根据文件名推断完整职责；
* 根据两个目录相似就判定能够直接合并；
* 根据代码能够编译就判定行为一致；
* 在缺少源码时虚构函数级调用关系；
* 将历史印象写成已确认事实。

---

## 6. Source Layering

当前源码只预设两个稳定层次：

```text
src/
├── base/
└── runtime/
```

### `src/base/`

保存跨业务复用的基础库，例如：

* 推理；
* 图像处理；
* 目标检测；
* 模糊检测；
* 关键点；
* 内存与公共工具。

一个组件只有同时满足以下条件，才可以进入`base`：

* 职责不依赖特定业务；
* 接口语义稳定；
* 至少存在明确的复用需求；
* 可以独立构建或测试；
* 不需要引用DMS、BSD、VMS业务类型。

### `src/runtime/`

保存具体业务运行库，例如：

* DMS；
* BSD；
* VMS。

依赖方向必须保持：

```text
runtime → base
base -X→ runtime
```

约束：

* `base`不得依赖`runtime`；
* 不同业务库原则上不得直接互相依赖；
* 公共代码不能仅因为两处代码相似就立即放入`base`；
* 必须先证明它具有稳定、业务无关的职责；
* 平台专用类型不得泄漏到公共业务接口；
* 公共实现不得依赖单一芯片SDK。

---

## 7. Directory Creation Policy

当前阶段不得提前建立大量预想目录。

创建新目录前，必须先完成：

1. 从固定Commit读取源组件；
2. 确认组件真实职责；
3. 确认输入、输出和依赖；
4. 确认平台耦合点；
5. 确认目标组件属于`base`还是`runtime`；
6. 形成源组件到目标模块的迁移映射；
7. 获得人工确认。

在人工确认前，Agent只能：

* 分析代码；
* 更新审计文档；
* 提出目录方案；
* 生成迁移映射草案；
* 记录未决问题。

不得：

* 根据旧目录名称机械创建新目录；
* 直接复制整个旧模块；
* 同时建立多个尚未验证的抽象层；
* 为未来可能存在的BSD、VMS模块预建空目录。

---

## 8. Migration Policy

`import_policy`的含义如下：

### `read-only-reference`

只作为现有行为和调用关系的证据来源。

不得直接迁移整个目录。

### `selective-migration`

必须先完成以下审计：

* 职责；
* 对外接口；
* 依赖；
* 平台耦合；
* 共享状态；
* 线程模型；
* 资源生命周期；
* 错误处理；
* 测试能力；
* 与另一平台实现的差异。

审计完成并确认迁移边界后，才允许迁移必要代码。

### `external-dependency`

按第三方依赖处理。

不得默认把旧仓库中的第三方源码复制到新仓库。

必须确认：

* 版本；
* 获取方式；
* 许可证；
* 本地修改；
* 编译选项；
* 是否需要自有接口封装。

---

## 9. Migration Provenance

每项代码迁移必须能够追溯到：

```text
source repository
source commit
source path
migration method
behavioral changes
verification evidence
```

迁移方式必须明确标记为以下之一：

```text
verbatim：基本原样迁移
refactored：保持职责但重构实现
reimplemented：根据契约重新实现
excluded：确认不进入新仓库
externalized：改为外部依赖
```

不要在每个源码文件中重复堆积来源信息。统一在迁移文档或Manifest中记录来源映射。

---

## 10. Platform Boundaries

平台差异必须通过明确的接口和适配层隔离。

公共代码不得直接暴露：

* Rockchip或HiSilicon SDK类型；
* 平台句柄；
* 平台内存结构；
* 平台专用错误码；
* 平台专用图像结构；
* 平台资源创建和销毁逻辑。

平台差异可能包括：

* 模型加载；
* 推理执行；
* 内存管理；
* 图像格式；
* 前处理；
* 量化模型；
* 线程及资源生命周期；
* 芯片SDK错误处理。

不要为了表面统一而隐藏真实平台差异。

只有职责和语义相同的部分才能进入公共层。

---

## 11. Naming Rules

新代码使用以下规范：

* 业务名称统一使用`dms`、`bsd`、`vms`；
* 旧代码中的`dsm`保留为来源路径，不直接延续为新模块名称；
* 目录、目标和库名称使用小写英文；
* 平台名称使用明确、稳定的标识；
* 不使用`common`、`utils`、`helper`承载无法解释的混合职责；
* 不使用`unified`掩盖尚未真正统一的实现；
* 不因为旧代码同名就认定新代码应保持同一抽象。

---

## 12. 文档写作规则

所有`.md`文件遵守以下规则：

* 除必须保留的技术标识外，标题、字段说明、列表项和正文句子都使用中文；
* 不要出现标题为中文、内容大段切换为英文，或前半部分中文、后半部分英文的混杂写法；
* 普通叙述中的英文词应翻译为中文，例如“Problem”写作“问题”，“Session”写作“会话”，“Commit”写作“提交”，“Manifest”写作“清单”；
* 只有不可替换或替换后会损失精确性的技术标识可以保留英文，例如命令、路径、文件名、类型名、函数名、字段名、状态枚举、Git分支名、提交信息和外部原文；
* 如果因工具或脚本兼容需要保留英文结构化字段名，例如`Objective`、`Evidence`、`Verification`，字段正文说明仍必须使用中文；
* 修改既有Markdown文件时，应在当前修改范围内尽量统一语言风格，不要求一次性重写无关历史内容。

---

## 13. Problem and Session Rules

问题是长期工程目标，工作流实例是问题的可执行控制结构，会话是某个工作流节点的一次有限执行尝试。

工作流节点与会话不是一一对应关系。一个节点可以有多个会话尝试；会话关闭只表示该上下文已经封存，不表示节点、工作流或问题已经完成。节点状态、依赖、人工门禁和执行尝试以当前问题的`WORKFLOW.json`为准。

Session不要求完成整个Problem，也不要求强行完成一个完整阶段；但必须保持局部连续：

```text
同一个目标焦点
+
同一批主要证据
+
同一种主要工作状态
```

出现以下情况时，应结束当前Session并形成Handoff：

* 主要目标发生变化；
* 从分析转向大规模实现；
* 得到关键反证，需要重新定义问题；
* 上下文已经明显混杂；
* 当前成果已经足够由下一Session继续；
* 需要人工确认才能跨越Commitment Gate。

会话结束时至少记录当前工作流节点、执行尝试、父会话以及：

```text
Objective
State Transition
Evidence
Findings
Counterevidence
Decisions
Changes
Verification
Unresolved
Next Session
```

Problem记录只保存状态、结论和证据指针，不复制完整Session对话。

---

## 14. Work Phases and Gates

当前工作按照以下状态推进：

```text
INTAKE
→ FRAME
→ AUDIT
→ DESIGN
→ COMMIT
→ IMPLEMENT
→ VERIFY
→ RETAIN
→ CLOSE
```

### `INTAKE / FRAME / AUDIT`

默认只读。

允许：

* 验证Manifest；
* 阅读源码；
* 建立调用关系；
* 记录差异；
* 更新Problem和审计文档。

禁止迁移业务代码。

### `DESIGN`

允许修改设计文档和迁移映射。

不得把候选方案直接当成已确认架构。

### `COMMIT`

这是人工Commitment Gate。

以下内容必须人工确认：

* 公共层与平台层边界；
* 对外接口；
* ABI变化；
* 迁移顺序；
* 删除旧代码；
* 可接受的行为差异；
* 验收标准和回滚路径。

### `IMPLEMENT`

只允许实施已经确认的设计范围。

发现设计前提不成立时，应停止扩展实现并返回`DESIGN`或`AUDIT`。

### `VERIFY`

必须使用外部Oracle验证，不能仅依据Agent判断。

### `RETAIN / CLOSE`

将稳定知识迁移到正式文档，记录剩余风险和后续Problem，再关闭当前Problem。

如果当前阶段不明确，默认停留在只读分析状态。

---

## 15. Git and Worktree Rules

开始修改前执行：

```bash
git status --short
git branch --show-current
git worktree list
```

确认：

* 当前位于目标Problem worktree；
* 当前分支与Problem一致；
* 没有覆盖用户未提交修改；
* 修改范围属于当前任务。

默认禁止：

* 直接修改`master`或`main`；
* `git reset --hard`；
* `git clean -fd`；
* 强制切换分支；
* 强制删除worktree；
* 改写已经共享的历史；
* 未经要求执行commit、push、merge或rebase。

Agent完成修改后必须提供：

```bash
git status --short
git diff --stat
```

Commit边界按照可独立审查和回滚的变化划分，不按照Session机械划分。

GitLab与GitHub之间同步已提交历史时使用：

```bash
tools/git-sync-remotes setup
tools/git-sync-remotes status
tools/git-sync-remotes sync
```

同步只能使用普通快进推送。远端分叉时必须停止，由人工明确合并或变基方案；不得用`--force`、`--force-with-lease`或删除远端分支消除差异。同步不包含未提交文件，也不改变Session关闭和提交规则。

建议Commit类型：

```text
docs(problem)
docs(migration)
docs(architecture)
build
feat(base/...)
feat(runtime/...)
fix(base/...)
fix(runtime/...)
test(...)
```

---

## 16. Build and Test Rules

当前仓库的构建和测试体系尚未完全建立。

Agent不得虚构构建命令、测试命令或通过结果。

在执行构建前必须：

1. 定位真实构建入口；
2. 检查工具链和平台要求；
3. 记录使用的命令和环境；
4. 区分本地验证与板端验证；
5. 明确哪些验证当前无法执行。

长期目标是使每个基础库和业务库能够：

* 独立构建；
* 独立测试；
* 独立生成产物；
* 通过Manifest参与Release组合。

根目录测试主要覆盖：

* 跨模块集成；
* 旧实现与新实现对齐；
* PC与板端对齐；
* Rockchip与HiSilicon对齐；
* 端到端业务行为。

---

## 17. Verification Standard

以下情况不能视为完成：

* Agent声称完成；
* Session正常结束；
* Herdr显示`done`；
* 代码格式检查通过；
* 单个平台能够编译；
* 单个样例运行成功；
* PR已经创建或合并。

有效完成必须对应明确的Acceptance Criteria和外部证据。

验证报告至少记录：

```text
baseline
candidate
source commit
build environment
hardware/platform
input
expected result
actual result
difference
allowed threshold
command
log/artifact path
final judgment
```

无法执行的验证必须明确写出原因，不能默认为通过。

---

## 18. Release and Version Rules

一个Git仓库不意味着所有组件共享同一个产物版本。

每个基础库和业务库应保持：

* 独立构建Target；
* 独立产物；
* 可识别版本；
* 可追溯源码Commit。

最终Release通过Manifest绑定：

```text
源码Commit
基础库版本
业务库版本
模型版本
配置版本
应用版本
测试报告
```

不得只替换模型、动态库或配置而不记录完整组合。

---

## 19. Stable Knowledge Placement

成果按照以下规则保存：

| 内容                       | 位置                                |
| ------------------------ | --------------------------------- |
| 当前状态、Session Handoff、下一步 | Problem记录                         |
| 已确认架构和接口设计               | `docs/`                           |
| 源代码基线                    | `manifests/source-baselines.yaml` |
| 迁移关系                     | 迁移Manifest或`docs/`                |
| 构建和验证代码                  | 当前仓库                              |
| 通用可复用Capability          | AgentWorkbench                    |
| 通用Agent问题解决方法            | AgentRecord                       |
| 临时日志和中间结果                | 不进入Git或放入明确的临时目录                  |

不要让Problem记录替代正式设计文档。

---

## 20. Required Final Report

每次任务结束时，输出必须包含：

```text
Goal
Inspected
Confirmed
Inferred
Unknown
Changed
Verification
Risks
Next
```

如果修改了文件，还必须列出：

* 修改文件；
* 修改原因；
* 未修改但相关的文件；
* 执行的检查；
* 未执行的检查；
* 是否创建Commit；
* 当前Git状态。

报告应简洁，但不得隐藏证据缺失、验证失败或未解决风险。

---

## Problem / Session 执行规则

当通过 `tools/problem-session` 启动时：

- 必须读取 `PROBLEM_ID`、`SESSION_ID`、`SESSION_FILE`、`WORKFLOW_FILE` 和 `WORKFLOW_NODE`
- 开始工作前读取 `WORKFLOW_FILE`、`SESSION_PLAN` 和 `SESSION_FILE`
- 开始执行节点前运行或等价读取`tools/problem-session instructions "$WORKFLOW_NODE"`提供的输入、产物、约束、外部判定机制和人工门禁快照
- 节点进入`ready`前必须在`WORKFLOW.json`声明非空制品契约，包括制品种类、路径来源、依赖、完成条件、影响关系和是否必需；不得用空目录或空文件代替契约
- 智能体必须按`instructions`返回的实际制品路径读取和修改，不能根据固定文件名或聊天记忆猜测制品位置
- 用户直接修改会话或其他制品后，继续工作前必须重新读取磁盘文件；聊天记忆和智能体摘要不是权威状态
- `H-*`人工经验卡和`D-*`人工决策卡允许用户直接增删；人工确认复选框只能由用户勾选，智能体只能补证据、影响分析和建议
- `review`只检查卡片结构，`verify`区分完整性、正确性和一致性，`reconcile`只提出协调建议，`retain`只提出稳定知识晋升计划；这些命令均不得自动接受节点或关闭会话
- 使用`reconcile --artifact <id>`处理人工编辑时，必须同时检查该制品的前向影响和反向依据；制品依赖顺序不是只能向下修改的限制
- `retain`只能把已验证且节点已接受的活动制品列为可晋升项；晋升目标仍需逐项人工批准，`close`不能代替`retain`
- 只处理当前工作流节点允许的目标、输入、Oracle和人工门禁
- 工作过程中持续更新 Evidence、Decisions、Changes 和 Verification
- 不得因为任务完成、Agent（Codex 或 Claude）退出或上下文压缩而自动关闭 Session
- 只有用户明确表示“该 Session 可以结束了”时，才允许关闭
- 关闭前必须补齐 Evidence、Decisions、Verification、Unresolved 和 Next Session
- 关闭时必须执行：

  ```bash
  tools/problem-session close "$SESSION_FILE"
  ```

- `close` 失败时必须报告原因，不得声称 Session 已结束
- `close`只关闭会话记录，不得自动把工作流节点改为`accepted`
- Agent只能提出工作流状态转换建议；要求人工门禁的转换必须引用人工决策记录
- 不得绕过 `close` 手工提交 Session 文件
- `close` 不得提交业务代码，也不得执行 `git push`
- 每个会话开始时必须确认工作流节点、尝试序号和父会话关系；继续已关闭工作时使用`tools/problem-session continue --from`创建新尝试，不得重开历史会话。
- 结束前必须更新 `SESSION-PLAN.md` 中的状态、实际产物和下一 Session；计划更新应在调用 `close` 前完成并提交。

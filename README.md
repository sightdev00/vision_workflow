# vision-runtime

统一算法运行时仓库，集中管理推理、图像处理、目标检测等基础库，以及 DMS、BSD、VMS 等业务运行库，支持 PC、Rockchip、HiSilicon 等平台的统一构建、测试、版本管理与发布。

---

## Problem / Session 工作流

本仓库使用 Problem 管理长期问题，使用 Session 管理一次有边界的 Agent（Codex 或 Claude）工作上下文。
Session 文件保存结构化工程记录，不保存完整聊天转录。
`WORKFLOW.json`保存权威工作流节点、依赖、状态、门禁和执行尝试；`SESSION-PLAN.md`只保存面向人的路线投影。

### 工作流对象

```text
问题
└── 工作流实例
    ├── 工作流节点
    │   └── 一个或多个Session执行尝试
    ├── 证据
    └── 人工决策
```

Session关闭只表示一次有限上下文已经封存，不表示节点或问题完成。节点进入`accepted`必须经过工作流状态转换；要求人工门禁的节点还必须引用人工决策记录。

### 前提

- 必须在 `problem/P-xxx-<name>` 分支对应的 Git worktree 中运行。
- 当前 worktree 同一时间只允许存在一个状态为 `active` 的 Session。
- 已安装并登录 Codex CLI 或 Claude Code（`claude`）CLI。
- 首次使用时赋予脚本执行权限：

```bash
chmod +x tools/problem-session
bash -n tools/problem-session
```

### 启动新 Session

```bash
tools/problem-session start [--node <node-id>] <topic>
```

例如：

```bash
tools/problem-session start --node document-evidence-review document-review
```

`topic` 只允许使用小写字母、数字和单连字符。

脚本会自动：

1. 从当前 `problem/P-xxx-<name>` 分支推导 Problem ID。
2. 检查是否已经存在active Session。
3. 检查工作流节点存在、状态为`ready`且前置节点均为`accepted`。
4. 根据已有文件生成下一个`S001`、`S002`等编号。
5. 在`.problems/<problem-id>/sessions/`创建Session文件并写入节点、尝试、父会话、Agent和接口。
6. 将新尝试写入`WORKFLOW.json`，并把`ready`节点推进为`active`。
7. 设置`PROBLEM_ID`、`SESSION_ID`、`SESSION_PLAN`、`SESSION_FILE`、`WORKFLOW_FILE`和`WORKFLOW_NODE`。
8. 从仓库根目录启动所选Agent（默认 Codex），并要求读取 `AGENTS.md`、`SESSION_PLAN` 和 `SESSION_FILE`。

Agent 启动后，只需描述本次目标，例如：

```text
这次确定 vision-runtime 的一级、二级目录设计；先分析并提出方案，不实施代码迁移。
```

### 选择 Agent 和接口

默认使用 Codex。通过全局选项 `-a, --agent` 或环境变量 `PROBLEM_SESSION_AGENT` 切换为 Claude：

```bash
tools/problem-session -a claude start <topic>
PROBLEM_SESSION_AGENT=claude tools/problem-session resume
```

`-a, --agent` 可取值 `codex`（默认）或 `claude`；未指定时读取 `PROBLEM_SESSION_AGENT`，仍未设置则回退到 `codex`。

通过 `-i, --interface` 选择对应 Agent 目录下的接口切换脚本：

```bash
tools/problem-session -a codex -i chatgpt start <topic>
tools/problem-session -a claude -i ds resume
PROBLEM_SESSION_AGENT=claude PROBLEM_SESSION_INTERFACE=qwen tools/problem-session resume
```

例如 `-a codex -i chatgpt` 会在启动 Codex 前通过 `source` 加载
`~/.codex/switch_chatgpt.sh`；`-a claude -i ds` 会加载
`~/.claude/switch_ds.sh`。未指定 `-i` 时读取
`PROBLEM_SESSION_INTERFACE`，仍未设置则保留当前 Agent 接口配置。脚本名称
以所选 Agent 目录下的实际文件为准，不在 Codex 和 Claude 之间自动映射别名。

各 Agent 的调用方式：

| Agent | `start` | `resume` |
| --- | --- | --- |
| codex | `codex -C <repo> <prompt>` | `codex resume --last` |
| claude | `claude <prompt>` | `claude --continue` |

> 注意：`resume` 依赖各 Agent 自己的会话历史。用 Codex 启动的 Session 若改用 Claude 恢复，
> 无法衔接原对话；请始终使用与启动时相同的 Agent。

### 恢复 active Session

Agent（Codex 或 Claude）意外退出或工作尚未完成时执行：

```bash
tools/problem-session resume
```

脚本会查找唯一的 active Session，恢复环境变量，并执行当前 worktree 下所选 Agent
的续聊：Codex 为 `codex resume --last`，Claude 为 `claude --continue`。不要在同一
Problem worktree 中绕过该脚本启动无关的 Agent 会话，否则续聊可能恢复到错误的聊天。

`resume`只恢复状态为`active`的工程会话。状态为`closed`的会话是已封存的事实和交接记录，不应改回`active`。

继续已关闭会话所对应的工作流节点时使用：

```bash
tools/problem-session continue --from <session-file> <topic>
```

`continue`会创建新Session，继承原节点并记录父会话和新的执行尝试序号，不改写历史记录。

### 查看和检查工作流

```bash
tools/problem-session status
tools/problem-session doctor
```

`status`从`WORKFLOW.json`和磁盘重新派生节点及制品状态，显示必需制品完成比例、阻塞原因和下一动作。`doctor`检查节点图、制品标识、制品依赖、影响引用、完成类型、安全路径、尝试文件和活动Session绑定。

节点执行和人工协作使用以下命令：

```bash
tools/problem-session status --json
tools/problem-session instructions <node-id> [--json]
tools/problem-session review [session-file] [--json]
tools/problem-session verify <node-id> [session-file] [--json]
tools/problem-session reconcile [session-file] [--artifact artifact-id] [--json]
tools/problem-session retain [session-file] [--json]
tools/problem-session note experience|decision <title> [session-file]
```

`instructions`输出节点的稳定知识层、活动制品、实际路径、依赖、完成条件、影响关系、外部判定机制和人工门禁。`review`只检查人工经验卡、人工决策卡和兼容的`U-*`确认项是否结构完整；`verify`从制品图计算完整性，并分别报告正确性和一致性，正确性仍须外部判定机制和人工判断。`reconcile --artifact`显示所选制品的前向影响和反向依据，要求智能体重新读取相关磁盘文件后逐项提出修改。`retain`从晋升制品读取来源和目标，只生成稳定知识晋升计划，不修改目标文件，也不关闭会话。`--json`用于不同智能体共享稳定机器接口。

人工经验卡使用`H-*`，人工决策卡使用`D-*`。用户可以直接编辑、增删和勾选这些卡片；智能体不得代替用户确认决定。文件存在、结构检查通过、验证通过、节点接受和会话关闭是不同状态，不得互相替代。

### 转换工作流节点

```bash
tools/problem-session transition <node-id> <state> [decision-record]
```

脚本只允许正式模型中定义的状态转换。进入`ready`前检查前置节点是否均为`accepted`，并要求节点已经声明非空制品契约；进入`accepted`前检查所有必需制品满足完成条件。要求人工门禁的节点进入`accepted`、`rejected`或`superseded`时还必须提供仓库内的人工决策记录。Agent可以提出转换建议，但不能自己生成最终人工判断。

### 结束 Session

完成当前工作后，在 Agent（Codex 或 Claude）中明确输入：

```text
该 Session 可以结束了。
```

Agent 必须先更新 `SESSION-PLAN.md` 中的状态、实际产物和下一 Session，并将该计划
更新纳入当前 Session 的功能或文档提交。随后补齐 `Evidence`、`Decisions`、
`Verification`、`Unresolved` 和 `Next Session`，然后执行：

```bash
tools/problem-session close "$SESSION_FILE"
```

`close` 会：

1. 检查目标文件属于当前 Problem 且状态为 active。
2. 检查必填章节存在且非空。
3. 写入结束时间并将状态改为 closed。
4. 只提交当前 Session 文件，提交信息格式为：

```text
docs(P-001): record session S001
```

5. 保留其他 staged、unstaged 和 untracked 文件，不执行 `git push`。

如果校验或提交失败，Agent 必须报告原因，不得声称 Session 已结束。

### Git 管理原则

- 业务代码、测试和文档修改按功能单独提交。
- `SESSION-PLAN.md` 的更新随当前 Session 的功能或文档提交。
- Session 记录由 `tools/problem-session close` 单独提交。
- `close` 不会提交业务文件或 `SESSION-PLAN.md`，也不会自动 push。
- 推送前人工检查：

```bash
git status --short
git log --oneline -5
git push
```

### 查看当前Session

```bash
tools/problem-session status
```

如果出现多个 active Session，应先人工确认保留哪一个，不要直接修改编号或删除记录。

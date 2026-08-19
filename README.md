# vision-runtime

统一算法运行时仓库，集中管理推理、图像处理、目标检测等基础库，以及 DMS、BSD、VMS 等业务运行库，支持 PC、Rockchip、HiSilicon 等平台的统一构建、测试、版本管理与发布。

---

## Problem / Session 工作流

本仓库使用 Problem 管理长期问题，使用 Session 管理一次有边界的 Codex 工作上下文。
Session 文件保存结构化工程记录，不保存完整聊天转录。
`SESSION-PLAN.md` 保存 Problem 级路线图、各 Session 状态、实际产物和下一 Session。

### 前提

- 必须在 `problem/P-xxx-<name>` 分支对应的 Git worktree 中运行。
- 当前 worktree 同一时间只允许存在一个 `Status: active` 的 Session。
- 已安装并登录 Codex CLI。
- 首次使用时赋予脚本执行权限：

```bash
chmod +x tools/problem-session
bash -n tools/problem-session
```

### 启动新 Session

```bash
tools/problem-session start <topic>
```

例如：

```bash
tools/problem-session start directory-design
```

`topic` 只允许使用小写字母、数字和单连字符。

脚本会自动：

1. 从当前 `problem/P-xxx-<name>` 分支推导 Problem ID。
2. 检查是否已经存在 active Session。
3. 根据已有文件生成下一个 `S001`、`S002` 等编号。
4. 在 `.problems/<problem-id>/sessions/` 创建 Session 文件。
5. 设置 `PROBLEM_ID`、`SESSION_ID`、`SESSION_PLAN` 和 `SESSION_FILE`。
6. 从仓库根目录启动 Codex，并要求读取 `AGENTS.md`、`SESSION_PLAN` 和 `SESSION_FILE`。

Codex 启动后，只需描述本次目标，例如：

```text
这次确定 vision-runtime 的一级、二级目录设计；先分析并提出方案，不实施代码迁移。
```

### 恢复 active Session

Codex 意外退出或工作尚未完成时执行：

```bash
tools/problem-session resume
```

脚本会查找唯一的 active Session，恢复环境变量，并执行当前 worktree 下的
`codex resume --last`。不要在同一 Problem worktree 中绕过该脚本启动无关的 Codex
会话，否则 `--last` 可能恢复到错误的聊天。

### 结束 Session

完成当前工作后，在 Codex 中明确输入：

```text
该 Session 可以结束了。
```

Codex 必须先更新 `SESSION-PLAN.md` 中的状态、实际产物和下一 Session，并将该计划
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

如果校验或提交失败，Codex 必须报告原因，不得声称 Session 已结束。

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

### 查看当前 Session

```bash
find .problems -path '*/sessions/*.md' -type f -print
grep -R -l -- '- Status: active' .problems/*/sessions 2>/dev/null
```

如果出现多个 active Session，应先人工确认保留哪一个，不要直接修改编号或删除记录。

# Agent instructions

## Commit messages

每次 commit 必须完整描述这次提交包含的改动，不能只写一个主题、把其他功能藏在实现里。

- Subject：一句简短的祈使句，概括本次提交的主目标。
- Body：用 bullet 逐条列出本次提交中的功能、修复、界面变化、文档和测试。
- 一次提交包含多个功能时，subject 只做概括，body 必须把所有功能点都列出来。
- 不要因为某个改动较小就省略；用户能感知的行为、数据迁移和兼容性变化都要写。
- 如果一次改动包含多个不相关功能，优先拆成多个 commit。

示例：

```text
Rebuild workflows around Alfred object graphs

- Replace the flat action model with Alfred objects, connections and uidata
- Add Script Filter JSON/XML handling and graph execution
- Support multiple output connections and workflow-relative scripts
- Rework the Workflows pane, object palette and configuration sheets
- Fix disabled workflow styling and Configure Workflow behavior
- Add REA evidence, documentation and regression tests
```

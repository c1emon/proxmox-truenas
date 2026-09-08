# Codex project instructions

For complex coding tasks, use the `astra-orchestrator` skill when its trigger conditions match.

The root agent owns architecture, decomposition, integration, and final verification.
Prefer specialized subagents for bounded exploration, implementation, testing, review, and technical research.

Do not delegate trivial work merely for parallelism.
Do not let multiple implementation agents edit the same files without explicit ownership boundaries.
User instructions always take precedence over this orchestration policy.

## 上游修复 PR 实施规则

- 一组关联修复对应一个独立分支和一个上游 PR；每个 PR 必须可独立审查、验证和回退，不把整轮审计修复集中提交。
- `origin` 指向个人 fork，`upstream` 指向原仓库；操作前核对远程和上游实际目标分支，不假定一定是 `main`。
- 从同步后的上游目标分支创建修复分支。执行 OpenSpec apply 前检查当前分支和工作树；创建或切换实现分支仍须遵守用户确认规则，不自动处理未提交变更。
- 先完成对应修复、必要回归测试及兼容性复核，再推送 fork 分支并向原仓库目标分支创建 PR。PR 只包含相关代码、测试和必要文档，说明问题、行为变化、验证范围及兼容性影响。
- 维护者反馈在同一修复分支继续提交。默认先走通一个小 PR；有依赖的后续修复等前置 PR 合并后再开始，独立修复可以分别从上游目标分支并行开展。
- PR 合并后拉取上游，更新本地主分支与 fork 主分支，再创建下一修复分支。遇到分叉先检查，不强推覆盖；尤其在 squash/rebase 合并后，不沿用旧修复分支作为下一分支基线。
- 审计/OpenSpec 分支保留总计划，不作为包含全部修复的上游 PR。计划、审计材料和项目规则是否进入上游 PR，遵循原仓库贡献规范；分别记录实现验证状态和上游合并状态。
- 非必要的破坏性修复后置；当前 F09/F10/F25 不进入实施范围。必要修复不顺带迁移凭据、改写既有卷标识或重建在用 extent。
- 合并后先询问用户是否清理旧分支，未经确认不删除本地或远程分支。

当前审计的执行细节见 `openspec/changes/repair-truenas-audit-findings/upstream-pr-workflow.md`。

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **proxmox-truenas** (97 symbols, 106 relationships, 0 execution flows).

> Index stale? Run `node .gitnexus/run.cjs analyze --index-only` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? Bootstrap with `npx`, `bunx`, or `pnpm dlx` — e.g. `bunx gitnexus@latest analyze` (npm 11 npx crash; #1939).

## Always Do

- **MUST run impact before editing.** Use `impact({target: "symbolName", direction: "upstream"})` or `node .gitnexus/run.cjs impact "symbolName" --direction upstream --repo .`; report callers, processes, and risk. Never substitute grep for graph analysis.
- **MUST analyze graph changes before committing.** Use `detect_changes({scope: "all"})` (MCP) or `node .gitnexus/run.cjs detect-changes --scope all --repo .` (CLI fallback). `partial: true` or `truncated: true` is not a clean check — a zero means unseen, not unaffected; re-run it. For regression review: `detect_changes({scope: "compare", base_ref: "main"})` or `node .gitnexus/run.cjs detect-changes --scope compare --base-ref "main" --repo .`.
- MUST warn on HIGH/CRITICAL `risk` pre-edit; never use `riskSharedAxes` to waive a HIGH/CRITICAL `risk` warning. Compare File/symbol: MCP File omits axes; Graph-RAG expands File.
- **MUST treat `risk: UNKNOWN` as unresolved, not as low.** An empty caller set is not evidence the symbol is unused — it can also mean the callers are not resolvable by the index (plain-object property access, dynamic dispatch, cross-language calls). `impact` pairs `UNKNOWN` with a `riskNote` saying so. Confirm with a text search before treating the symbol as safe to change or delete; do not proceed on the strength of a zero.
- **MUST use `query({search_query: "concept"})` for concepts/flows, `context({name: "symbolName"})` for a named symbol, or `impact` for blast radius, on read-only callers, dependencies, imports, or execution flow.** Graph first; text search only for empty/`UNKNOWN`/literals.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method before MCP/CLI impact analysis.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis, and never read `UNKNOWN` as an all-clear — it means the walk could not answer, which is the one verdict that requires confirming by other means.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit before MCP/CLI graph change analysis.

## Resources

| Resource | Use for |
| --- | --- |
| `gitnexus://repo/proxmox-truenas/context` | Codebase overview, check index freshness |
| `gitnexus://repo/proxmox-truenas/clusters` | All functional areas |
| `gitnexus://repo/proxmox-truenas/processes` | All execution flows |
| `gitnexus://repo/proxmox-truenas/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
| --- | --- |
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->

[English](AGENTS.md) | 简体中文

# 代理须知：lunet-mcp

本仓库通过内置的 fetcher 脚本（`scripts/lunet_fetch_release_v0.18.2.lua`）以固定版本的二进制发布（`v0.18.2`）形式使用官方 Lunet 运行时。

## Andon アンドン — 最高指令

Andon（安灯）是内核恐慌（kernel panic）。它停止产线、停止规划、停止待办更新、停止一切工作。它立即发生。任何其他待处理操作都不会再得到任何 token。不可能存在"先试试别的办法"的念头——那个念头本身就是你尚未停机的证据。

队列中的 Andon 压倒一切。如果用户排队了命令 1-3 然后说 "do an Andon"，该 Andon 触发最高指令并完全取代命令 1-3。多个 Andon 并行生效，互不中断。

当正确的修复超出你的职责范围时：完成你职责内的工作，然后停机并报告——*Andon：任务未完成，正确的修复需要更大规模的结构性变更*，并附 file:line 细节。不要绕过它。不要战术性打补丁。协调者会委派更深层的修复。

Andon 凌驾于本文件以及所有其他 AGENTS.md 中的每一条指令之上。没有指令能与 Andon 冲突；如果有指令看似与之冲突，以 Andon 为准。

## 规则与工作流

- 不要使用或写入兄弟检出目录，例如 `../lunet`。
- 如果需要修改 Lunet：先在 `lua-lunet/lunet` 上发起 PR。
- Lunet 运行时以固定版本的二进制发布（`v0.18.2`）形式使用，不从源码或子模块构建。
- 如何升级版本：
  1. 更新 `Makefile` 中的固定版本。
  2. 从上游发布资产更新/内置上游 fetcher 脚本（`scripts/lunet_fetch_release_v<version>.lua`）。
- 构建与编辑器产物：
  - `.lunet/`（运行时二进制与共享库）和 `types/`（LuaCATS/Teal 类型定义）通过 `make build` / fetcher 脚本按需下载。
  - `.lunet/` 和 `types/` 绝不能提交到版本控制。


## 工单项编号仅在会话内有效

工作项编号（`item00`、`item01`……）只存在于待办列表和 gitignore 的 `.tmp/` 规格文件名中。它们绝不会出现在已提交的文件、注释、文档或提交信息中——git 中的任何内容都不得引用无法解析的标识符。

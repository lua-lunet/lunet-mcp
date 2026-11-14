[English](PLAN_15.md) | 简体中文

# 实施计划 - Issue #15

> 历史文档：这是 PLAN_15.md（v0.9.2 迁移计划）的中文翻译，仅作记录保留。

## 升级到 Lunet v0.9.2 并切换为二进制发布消费

### 1. 概述与目标

目标是将 `lunet-mcp` 从"通过 git 子模块（`deps/lunet`）和 `xmake` 从源码构建 Lunet 框架"迁移为"使用官方上游预构建二进制发布包（`v0.9.2`）"。这简化了下游开发，消除了对编译工具链（`xmake`、C 编译器）的依赖，并通过 LuaCATS / Teal 类型定义提供开箱即用的编辑器导航。

### 2. 架构与设计

- **二进制运行时布局**：
  - 下载的发布产物位于 `.lunet/`（被 git 忽略）。
  - 可执行运行器：`.lunet/bin/lunet-run`（或 `.lunet/lunet-run`）。
  - 运行时共享库：`lunet.so` / `lunet.dylib` / `lunet.dll` 与 `lunet/httpc.so`。
  - 类型定义：解压至 `types/`，用于编辑器自动补全与诊断。
- **发布 Fetcher**：
  - 内置脚本：`scripts/lunet_fetch_release_v0.9.2.lua`。
  - 由主机 `lua`（Lua 5.1+ 或 LuaJIT）驱动，使用标准的 curl / tar / unzip 系统工具。
  - 从 `lua-lunet/lunet` 的 GitHub 发布下载对应平台的 tarball/zip。
- **编辑器与 IDE 集成**：
  - `.luarc.json` 配置 `workspace.library = ["types"]`，支持 LuaCATS 与 Teal 的编辑器导航。

### 3. 迁移策略与组件

#### A. 发布 Fetcher 集成
- 内置 `scripts/lunet_fetch_release_v0.9.2.lua`。
- 支持目标目录 `.lunet/` 及 `types/` 的解压。

#### B. 构建与执行工具（Makefile、脚本）
- 更新 `Makefile`：
  - 目标 `build` / `fetch`：调用发布 fetcher 填充 `.lunet/`。
  - 目标 `run`：通过 `.lunet/bin/lunet-run` 执行 `app/main.lua`。
  - 目标 `clean-all`：清理 `.lunet/` 与 `types/` 及临时日志。
  - 移除所有 xmake 与子模块调用。
- 更新辅助脚本（`run.sh`、`scripts/lunet_bin.sh`）。

#### C. 移除子模块与 xmake
- 从 `.gitmodules` 与 git 索引中移除 `deps/lunet` 子模块。
- 移除 `.xmake/` 及所有 xmake 工程引用。

#### D. 容器化（Dockerfile）
- 更新 `Dockerfile`，安装运行时系统库（`libuv1`、`libluajit-5.1-2`、`libcurl4`、`zlib1g`）。
- 下载或复制二进制运行时 `lunet-run` 与共享库。

#### E. 持续集成（.github/workflows/ci.yml）
- 通过移除子模块初始化与 xmake 构建步骤简化 CI 工作流。
- 运行 fetcher 脚本获取 `v0.9.2` 二进制，并在 Linux/macOS 上运行测试。

#### F. 测试验证
- 在 `lunet-run` 下验证 `test/stress_mcp.lua` 与 `test/bench_memory.lua`。
- 验证 SSE 流与 Tavily 工具集成。

### 4. 验证循环

1. 运行 fetcher：`make build`（下载 v0.9.2 发布产物到 `.lunet/`）。
2. 启动服务器：`make run` 或 `.lunet/bin/lunet-run app/main.lua`。
3. 验证端点：
   - 服务器信息：`curl -s http://localhost:8080/`
   - SSE 连接：`curl -sN http://localhost:8080/sse`
4. 运行压力与基准测试：
   - `make stress`
   - `make bench`
5. 验证 Docker 镜像构建与运行。

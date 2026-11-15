[English](README.md) | 简体中文

# lunet-mcp

[![Lunet v0.19.0](https://img.shields.io/badge/Lunet-v0.19.0-blue?logo=lua&logoColor=white)](https://github.com/lua-lunet/lunet/releases/tag/v0.19.0)

一个最小化的 MCP（Model Context Protocol）服务器，基于 [Lunet](https://github.com/lua-lunet/lunet) 框架，演示 Tavily 网页搜索。同时支持现代的 **Streamable HTTP** 传输（2025-03-26 规范）与传统的 **HTTP+SSE** 传输（2024-11-05 规范）。

## 为什么选择 Lunet？

MCP 服务器通常部署为边车（sidecar）进程，或运行在资源受限的环境中。本实现优先考虑：

- **占用极小** — 7 MB 运行时内存，对比 Node/Bun/Python 的 14-28 MB
- **镜像更小** — 171 MB Docker 镜像，对比 367-420 MB
- **依赖稳定** — libuv 与 LuaJIT 是成熟、久经考验的库，享有 Debian LTS 支持
- **无依赖漂移** — 没有 npm/pip 生态的负担与频繁的安全补丁

### 性能对比

运行 `./compare.sh` 复现以下基准测试：

| 实现方案 | Docker 镜像 | 运行时内存 |
|----------------|--------------|----------------|
| **lunet-mcp** | **171 MB** | **7 MB** |
| tavily-mcp (Node.js) | 420 MB | 18 MB |
| tavily-mcp (Bun) | 382 MB | 14 MB |
| FastMCP (Python) | 367 MB | 28 MB |

lunet-mcp 的内存占用比 Node.js 少 **2.5 倍**，比 Bun 少 **2 倍**，比 Python 少 **4 倍**。

## 特性

- **MCP 2025-03-26** 协议支持（Streamable HTTP 传输）
- **MCP 2024-11-05** 传统 HTTP+SSE 传输，兼容旧客户端
- **Streamable HTTP 传输** — 单一 `POST /mcp` 端点，JSON 或 SSE 响应，`Mcp-Session-Id` 会话头
- **SSE 传输**，实时通信
- **Tavily 搜索**集成
- **内存高效**（Docker 中约 7 MB RSS，原生约 2 MB）
- **零开销追踪**（禁用时无任何开销）
- **跨平台**二进制（Linux amd64/arm64、macOS arm64、Windows amd64）

## 下载

预构建二进制可从 [GitHub Releases](https://github.com/lua-lunet/lunet-mcp/releases/tag/nightly) 获取：

| 平台 | 压缩包 |
|----------|---------|
| Linux (amd64) | `lunet-mcp-linux-amd64.tar.gz` |
| Linux (arm64) | `lunet-mcp-linux-arm64.tar.gz` |
| macOS (arm64) | `lunet-mcp-macos.tar.gz` |
| Windows (amd64) | `lunet-mcp-windows-amd64.zip` |

## 运行

### macOS (arm64)

```bash
# 安装依赖
brew install luajit libuv zlib curl

# 下载并解压
curl -L -o lunet-mcp-macos.tar.gz \
  https://github.com/lua-lunet/lunet-mcp/releases/download/nightly/lunet-mcp-macos.tar.gz
tar -xzf lunet-mcp-macos.tar.gz

# 配置 API 密钥
echo "TAVILY_API_KEY=your_key_here" > .env

# 运行
./run.sh
```

### Linux (Debian/Ubuntu)

```bash
# 安装依赖
sudo apt-get update
sudo apt-get install -y libuv1 libluajit-5.1-2 libcurl4 zlib1g curl

# 下载并解压（按平台选择 arm64 或 amd64）
curl -L -o lunet-mcp-linux-arm64.tar.gz \
  https://github.com/lua-lunet/lunet-mcp/releases/download/nightly/lunet-mcp-linux-arm64.tar.gz
tar -xzf lunet-mcp-linux-arm64.tar.gz

# 配置 API 密钥
echo "TAVILY_API_KEY=your_key_here" > .env

# 运行
./run.sh
```

### Windows (amd64)

```powershell
# 从 GitHub releases 下载并解压 zip
# 然后在解压目录中：

# 配置 API 密钥
echo TAVILY_API_KEY=your_key_here > .env

# 运行
.\run.bat
```

## 使用 Docker 测试

你可以在 Docker 容器中运行 Linux 二进制。在 macOS 或其他平台上测试时很有用。

```bash
# 启动一个挂载二进制的容器
docker run -d --name mcp-server -p 8080:8080 \
  -v /path/to/extracted/linux-app:/app -w /app \
  debian:trixie-slim \
  /bin/bash -c 'apt-get update -qq && apt-get install -y -qq libuv1 libluajit-5.1-2 libcurl4 zlib1g curl >/dev/null 2>&1 && export $(cat .env | xargs) && HOST=0.0.0.0 ./bin/lunet-run --dangerously-skip-loopback-restriction app/main.lua'

# 测试
curl http://localhost:8080/

# 停止
docker stop mcp-server && docker rm mcp-server
```

### macOS 上的 Colima

在 macOS 上，使用 [Colima](https://github.com/abiosoft/colima) 运行 Linux arm64 容器：

```bash
# 启动 Colima
colima start

# 下载并解压 Linux arm64 构建
curl -L -o lunet-mcp-linux-arm64.tar.gz \
  https://github.com/lua-lunet/lunet-mcp/releases/download/nightly/lunet-mcp-linux-arm64.tar.gz
mkdir -p linux-app
tar -xzf lunet-mcp-linux-arm64.tar.gz -C linux-app

# 复制进 Colima 虚拟机
colima ssh -- mkdir -p /tmp/testapp
tar -czf - -C linux-app . | colima ssh -- tar -xzf - -C /tmp/testapp

# 复制你的 .env
echo "TAVILY_API_KEY=your_key_here" | colima ssh -- tee /tmp/testapp/.env

# 运行服务器
docker run -d --name mcp-server -p 8080:8080 \
  -v /tmp/testapp:/app -w /app \
  debian:trixie-slim \
  /bin/bash -c 'apt-get update -qq && apt-get install -y -qq libuv1 libluajit-5.1-2 libcurl4 zlib1g curl >/dev/null 2>&1 && export $(cat .env | xargs) && HOST=0.0.0.0 ./bin/lunet-run --dangerously-skip-loopback-restriction app/main.lua'

# 从 macOS 测试
curl http://localhost:8080/
./test_tavily.sh

# 清理
docker stop mcp-server && docker rm mcp-server
colima stop
```

## 端点

| 方法 | 路径 | 说明 |
|--------|------|-------------|
| GET | `/` | 服务器信息（JSON） |
| POST | `/mcp` | Streamable HTTP 传输：发送 JSON-RPC，返回 JSON 或 SSE 响应 |
| DELETE | `/mcp` | 终止 Streamable HTTP 会话（`Mcp-Session-Id` 请求头） |
| GET | `/sse` | 传统 SSE 流（创建会话） |
| POST | `/message?session=<id>` | 传统传输：发送 JSON-RPC 消息 |

## 测试

```bash
# 查询服务器信息
curl http://localhost:8080/

# 运行 Tavily 搜索测试
./test_tavily.sh

# 手动连接 SSE 流
curl -N http://localhost:8080/sse
```

## MCP 协议流程

### Streamable HTTP（2025-03-26 规范）

1. 客户端向 `/mcp` POST `initialize` JSON-RPC 请求
2. 服务器返回结果并附带 `Mcp-Session-Id` 响应头
3. 客户端携带 `Mcp-Session-Id` 请求头向 `/mcp` POST JSON-RPC 消息
4. 服务器在该 POST 自身的响应中以 JSON 或 SSE 格式返回结果

### 传统 HTTP+SSE（2024-11-05 规范）

1. 客户端 GET `/sse` 建立 SSE 连接
2. 服务器发送携带会话 ID 的 `endpoint` 事件
3. 客户端 POST JSON-RPC 消息到 `/message?session=<id>`
4. 服务器通过该 GET 连接上的 SSE 事件返回响应

本仓库按设计不提供 HTTPS 终结（TLS termination）。
若要运行面向公网的 MCP SSE，你可以用 nginx 作为边车部署本代码，
或部署在云负载均衡器之后的私有云网络中。这是 Unix 哲学：
在专用工具之间传递数据。它带来"QMail 安全模型"——
协议攻击的处理与业务逻辑进程隔离。

## 可用工具

### tavily-search

使用 Tavily AI 搜索引擎进行网络搜索。

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "tavily-search",
    "arguments": {
      "query": "latest AI news",
      "max_results": 5
    }
  }
}
```

## 环境变量

| 变量 | 默认值 | 说明 |
|----------|---------|-------------|
| `TAVILY_API_KEY` | - | Tavily API 密钥（必需） |
| `PORT` | 8080 | 服务器端口 |
| `HOST` | 127.0.0.1 | 绑定地址（Docker 中使用 0.0.0.0） |
| `MCP_TRACE` | off | 追踪级别（off/error/warn/info/debug/trace） |
| `MCP_TRACE_FILE` | stderr | 追踪输出文件 |

## 开发与运行

通过内置的 fetcher 脚本使用官方预构建的 Lunet v0.19.0 发布归档。

### 前置要求

- 主机工具：`lua`（5.1+ 或 LuaJIT），用于运行 fetcher
- 运行时库：
  - **macOS**：`brew install luajit libuv zlib curl`
  - **Linux (Debian/Ubuntu)**：`sudo apt-get install -y libuv1 libluajit-5.1-2 libcurl4 zlib1g`

### 获取与运行流程

```bash
# 克隆仓库
git clone https://github.com/lua-lunet/lunet-mcp.git
cd lunet-mcp

# 获取预构建的 Lunet v0.19.0 运行时与类型定义
make build

# 配置 API 密钥
echo "TAVILY_API_KEY=your_key_here" > .env

# 运行 MCP 服务器
make run
```

### 编辑器与类型支持

fetcher 会将类型定义填充到 `types/`。配置 `.luarc.json` 以启用 LuaCATS 与 Teal 的编辑器导航和类型检查：

```json
{
  "$schema": "https://raw.githubusercontent.com/sumneko/vscode-lua/master/setting/schema.json",
  "workspace.library": ["types"]
}
```

## 零开销追踪

服务器内置零开销追踪系统，禁用时**没有任何开销**。

```bash
# 不追踪（生产环境，零开销）
./run.sh

# 详细启动 - 显示服务器横幅
./run.sh -v
# 或：./run.sh --verbose

# Info 级别 - 查看会话与工具调用
MCP_TRACE=info ./run.sh

# Debug 级别 - 查看 HTTP 请求与 MCP 方法
MCP_TRACE=debug ./run.sh
```

## 基准测试

对比其他 MCP 实现的内存与镜像大小：

```bash
./compare.sh
```

对比对象：
- `tavily-mcp`（Node.js，经 npx）
- `tavily-mcp`（Bun）
- FastMCP（Python）

## 许可证

MIT

---

> 本项目基于 [Lunet](https://github.com/lua-lunet/lunet) 构建，其源自 [夏磊 (Xia Lei)](https://github.com/xialeistudio) 的 [xialeistudio/lunet](https://github.com/xialeistudio/lunet)。另见他的精彩文章：[Lunet: Design and Implementation of a High-Performance Coroutine Network Library](https://www.ddhigh.com/en/2025/07/12/lunet-high-performance-coroutine-network-library/)。

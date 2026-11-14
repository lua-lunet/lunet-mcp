# lunet-mcp

[![Lunet v0.18.2](https://img.shields.io/badge/Lunet-v0.18.2-blue?logo=lua&logoColor=white)](https://github.com/lua-lunet/lunet/releases/tag/v0.18.2)

A minimal MCP (Model Context Protocol) server demonstrating Tavily web search, built on the [Lunet](https://github.com/lua-lunet/lunet) framework. Supports both the modern **Streamable HTTP** transport (spec 2025-03-26) and the legacy **HTTP+SSE** transport (spec 2024-11-05).

## Why Lunet?

MCP servers are often deployed as sidecar processes or in resource-constrained environments. This implementation prioritizes:

- **Minimal footprint** - 7 MB runtime memory vs 14-28 MB for Node/Bun/Python
- **Small image size** - 171 MB Docker image vs 367-420 MB for alternatives
- **Stable dependencies** - libuv and LuaJIT are mature, battle-tested libraries with Debian LTS support
- **No dependency churn** - No npm/pip ecosystem overhead or constant security patches

### Performance Comparison

Run `./compare.sh` to reproduce these benchmarks:

| Implementation | Docker Image | Runtime Memory |
|----------------|--------------|----------------|
| **lunet-mcp** | **171 MB** | **7 MB** |
| tavily-mcp (Node.js) | 420 MB | 18 MB |
| tavily-mcp (Bun) | 382 MB | 14 MB |
| FastMCP (Python) | 367 MB | 28 MB |

lunet-mcp uses **2.5x less memory** than Node.js, **2x less** than Bun, and **4x less** than Python.

## Features

- **MCP 2025-03-26** protocol support (Streamable HTTP transport)
- **MCP 2024-11-05** legacy HTTP+SSE transport for older clients
- **Streamable HTTP transport** — single `POST /mcp` endpoint, JSON or SSE responses, `Mcp-Session-Id` session header
- **SSE transport** for real-time communication
- **Tavily search** integration
- **Memory-efficient** (~7 MB RSS in Docker, ~2 MB native)
- **Zero-cost tracing** for debugging (no overhead when disabled)
- **Cross-platform** binaries (Linux amd64/arm64, macOS arm64, Windows amd64)

## Downloads

Pre-built binaries are available from [GitHub Releases](https://github.com/lua-lunet/lunet-mcp/releases/tag/nightly):

| Platform | Archive |
|----------|---------|
| Linux (amd64) | `lunet-mcp-linux-amd64.tar.gz` |
| Linux (arm64) | `lunet-mcp-linux-arm64.tar.gz` |
| macOS (arm64) | `lunet-mcp-macos.tar.gz` |
| Windows (amd64) | `lunet-mcp-windows-amd64.zip` |

## Running

### macOS (arm64)

```bash
# Install dependencies
brew install luajit libuv zlib curl

# Download and extract
curl -L -o lunet-mcp-macos.tar.gz \
  https://github.com/lua-lunet/lunet-mcp/releases/download/nightly/lunet-mcp-macos.tar.gz
tar -xzf lunet-mcp-macos.tar.gz

# Set up API key
echo "TAVILY_API_KEY=your_key_here" > .env

# Run
./run.sh
```

### Linux (Debian/Ubuntu)

```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y libuv1 libluajit-5.1-2 libcurl4 zlib1g curl

# Download and extract (use arm64 or amd64 as appropriate)
curl -L -o lunet-mcp-linux-arm64.tar.gz \
  https://github.com/lua-lunet/lunet-mcp/releases/download/nightly/lunet-mcp-linux-arm64.tar.gz
tar -xzf lunet-mcp-linux-arm64.tar.gz

# Set up API key
echo "TAVILY_API_KEY=your_key_here" > .env

# Run
./run.sh
```

### Windows (amd64)

```powershell
# Download and extract the zip from GitHub releases
# Then in the extracted directory:

# Set up API key
echo TAVILY_API_KEY=your_key_here > .env

# Run
.\run.bat
```

## Testing with Docker

You can run the Linux binary in a Docker container. This is useful for testing on macOS or other platforms.

```bash
# Start a container with the binary mounted
docker run -d --name mcp-server -p 8080:8080 \
  -v /path/to/extracted/linux-app:/app -w /app \
  debian:trixie-slim \
  /bin/bash -c 'apt-get update -qq && apt-get install -y -qq libuv1 libluajit-5.1-2 libcurl4 zlib1g curl >/dev/null 2>&1 && export $(cat .env | xargs) && HOST=0.0.0.0 ./bin/lunet-run --dangerously-skip-loopback-restriction app/main.lua'

# Test
curl http://localhost:8080/

# Stop
docker stop mcp-server && docker rm mcp-server
```

### macOS with Colima

On macOS, use [Colima](https://github.com/abiosoft/colima) to run Linux arm64 containers:

```bash
# Start Colima
colima start

# Download and extract the Linux arm64 build
curl -L -o lunet-mcp-linux-arm64.tar.gz \
  https://github.com/lua-lunet/lunet-mcp/releases/download/nightly/lunet-mcp-linux-arm64.tar.gz
mkdir -p linux-app
tar -xzf lunet-mcp-linux-arm64.tar.gz -C linux-app

# Copy into Colima VM
colima ssh -- mkdir -p /tmp/testapp
tar -czf - -C linux-app . | colima ssh -- tar -xzf - -C /tmp/testapp

# Copy your .env
echo "TAVILY_API_KEY=your_key_here" | colima ssh -- tee /tmp/testapp/.env

# Run the server
docker run -d --name mcp-server -p 8080:8080 \
  -v /tmp/testapp:/app -w /app \
  debian:trixie-slim \
  /bin/bash -c 'apt-get update -qq && apt-get install -y -qq libuv1 libluajit-5.1-2 libcurl4 zlib1g curl >/dev/null 2>&1 && export $(cat .env | xargs) && HOST=0.0.0.0 ./bin/lunet-run --dangerously-skip-loopback-restriction app/main.lua'

# Test from macOS
curl http://localhost:8080/
./test_tavily.sh

# Cleanup
docker stop mcp-server && docker rm mcp-server
colima stop
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Server info (JSON) |
| POST | `/mcp` | Streamable HTTP transport: send JSON-RPC, get JSON or SSE response |
| DELETE | `/mcp` | Terminate a Streamable HTTP session (`Mcp-Session-Id` header) |
| GET | `/sse` | Legacy SSE stream (creates session) |
| POST | `/message?session=<id>` | Legacy transport: send JSON-RPC message |

### Streamable HTTP transport (recommended)

The client picks the transport by which endpoint it calls. Modern clients
(Codex, mcp-inspector, current MCP SDKs) should use `POST /mcp`:

1. `POST /mcp` with an `initialize` JSON-RPC request and
   `Accept: application/json, text/event-stream`
2. Server replies with the result and an `Mcp-Session-Id` response header
3. Subsequent POSTs include the `Mcp-Session-Id` header
4. Each POST is answered on its own response with either a plain
   `application/json` body or an SSE-formatted (`text/event-stream`) body
5. Notifications are answered with `202 Accepted` and no body
6. `DELETE /mcp` terminates the session

```bash
# Initialize (capture the Mcp-Session-Id header from the response)
curl -i -X POST http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"demo","version":"0.0.1"}}}'

# List tools (JSON response)
curl -X POST http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "Mcp-Session-Id: <session-id>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

## Testing

```bash
# Check server info
curl http://localhost:8080/

# Run Tavily search test
./test_tavily.sh

# Connect to SSE stream manually
curl -N http://localhost:8080/sse

# HTTP framing regression tests (server must be running; fixes
# lua-lunet/lunet-mcp#22 and lua-lunet/lunet-mcp#23)
make test-framing
```

## MCP Protocol Flow

### Streamable HTTP (spec 2025-03-26)

1. Client POSTs an `initialize` JSON-RPC request to `/mcp`
2. Server responds with the result and an `Mcp-Session-Id` header
3. Client POSTs JSON-RPC messages to `/mcp` with the `Mcp-Session-Id` header
4. Server answers each POST with JSON or an SSE body on that same response

### Legacy HTTP+SSE (spec 2024-11-05)

1. Client GETs `/sse` to establish SSE connection
2. Server sends `endpoint` event with session ID
3. Client POSTs JSON-RPC messages to `/message?session=<id>`
4. Server responds via SSE events on the GET connection

There is no HTTPS termination support in this repo by design. 
If you want to run a public-facing MCP SSE you can trivially
deploy this code with nginx as a sidecar else on a private cloud 
network behind a cloud load balancer. That is The Unix Way of piping 
data between specialist tools. It gives you the “QMail Security Model” 
where dealing protocol attacks is process segregated from any 
business logic. 

## Tools Available

### tavily-search

Search the web using Tavily AI search engine.

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

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TAVILY_API_KEY` | - | Tavily API key (required) |
| `PORT` | 8080 | Server port |
| `HOST` | 127.0.0.1 | Bind address (use 0.0.0.0 for Docker) |
| `MCP_TRACE` | off | Trace level (off/error/warn/info/debug/trace) |
| `MCP_TRACE_FILE` | stderr | Output file for traces |

## Development and Running

Consumes official pre-built Lunet v0.18.2 release archives via the vendored fetcher script.

### Prerequisites

- Host tool: `lua` (5.1+ or LuaJIT) for running the fetcher
- Runtime libraries:
  - **macOS**: `brew install luajit libuv zlib curl`
  - **Linux (Debian/Ubuntu)**: `sudo apt-get install -y libuv1 libluajit-5.1-2 libcurl4 zlib1g`

### Fetch and Run Workflow

```bash
# Clone the repository
git clone https://github.com/lua-lunet/lunet-mcp.git
cd lunet-mcp

# Fetch pre-built Lunet v0.18.2 runtime and type definitions
make build

# Configure API key
echo "TAVILY_API_KEY=your_key_here" > .env

# Run the MCP server
make run
```

### Editor & Type Support

The fetcher populates `types/` with type definitions. Configure `.luarc.json` for LuaCATS and Teal editor navigation and type checking:

```json
{
  "$schema": "https://raw.githubusercontent.com/sumneko/vscode-lua/master/setting/schema.json",
  "workspace.library": ["types"]
}
```

## Zero-Cost Tracing

The server includes a zero-cost tracing system that has **no overhead when disabled**.

```bash
# No tracing (production, zero overhead)
./run.sh

# Verbose startup - show server banner
./run.sh -v
# or: ./run.sh --verbose

# Info level - see sessions and tool calls
MCP_TRACE=info ./run.sh

# Debug level - see HTTP requests and MCP methods
MCP_TRACE=debug ./run.sh
```

## Benchmarking

Compare memory and image size against other MCP implementations:

```bash
./compare.sh
```

This tests against:
- `tavily-mcp` (Node.js via npx)
- `tavily-mcp` (Bun)
- FastMCP (Python)

## License

MIT

---

> This project uses [Lunet](https://github.com/lua-lunet/lunet), which is based on [xialeistudio/lunet](https://github.com/xialeistudio/lunet) by [夏磊 (Xia Lei)](https://github.com/xialeistudio). See also his excellent write-up: [Lunet: Design and Implementation of a High-Performance Coroutine Network Library](https://www.ddhigh.com/en/2025/07/12/lunet-high-performance-coroutine-network-library/).

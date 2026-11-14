#!/usr/bin/env luajit
-- MCP Tavily Demo Server
--
-- A minimal MCP (Model Context Protocol) server exposing Tavily search
-- via the Streamable HTTP transport (spec 2025-03-26) and the legacy
-- HTTP+SSE transport (spec 2024-11-05). Uses the Lunet framework for
-- async I/O and the upstream lunet.http / lunet.jsonic / lunet.httpc
-- modules for HTTP framing, JSON, and outbound requests.
--
-- Usage:
--   luajit app/main.lua
--   # or via make:
--   make run
--
-- Environment:
--   TAVILY_API_KEY - Your Tavily API key (from .env)
--   PORT           - Server port (default 8080)
--   MCP_TRACE      - Trace level (0-5 or off/error/warn/info/debug/trace)
--
-- Test:
--   curl http://localhost:8080/
--   curl -N http://localhost:8080/sse
--
-- Tracing:
--   MCP_TRACE=info make run
--   MCP_TRACE=debug make run
--
-- Verbose startup:
--   ./bin/lunet -v app/main.lua   # or --verbose


io.stdout:setvbuf('no')
io.stderr:setvbuf('no')

-- Parse -v/--verbose for startup logging
local VERBOSE = false
for i = 1, #arg do
    if arg[i] == "-v" or arg[i] == "--verbose" then
        VERBOSE = true
        break
    end
end

local lunet = require("lunet")
local socket = require("lunet.socket")
local http = require("lunet.http")
local jsonic = require("lunet.jsonic")
local httpc = require("lunet.httpc")

-- Zero-cost tracing (no overhead when MCP_TRACE is not set)
local trace = require("app.trace")

local MCP_VERSION = "2024-11-05"
local STREAMABLE_HTTP_VERSION = "2025-03-26"
local SUPPORTED_PROTOCOL_VERSIONS = { STREAMABLE_HTTP_VERSION, MCP_VERSION }
local SERVER_NAME = "lunet-tavily-mcp-demo"
local SERVER_VERSION = "0.1.0"

-- dkjson encodes empty tables as []; the MCP spec wants JSON objects
-- for empty result payloads (ping result, capabilities.tools)
local EMPTY_OBJECT = setmetatable({}, { __jsontype = "object" })

local CORS = {
    origin = "*",
    methods = { "GET", "POST", "DELETE", "OPTIONS" },
    headers = { "Content-Type", "Mcp-Session-Id", "Last-Event-ID", "MCP-Protocol-Version" },
}

-- Load .env file
local function load_env_file(path)
    local file = io.open(path, "r")
    if not file then return end
    for line in file:lines() do
        local key, value = line:match("^([%w_]+)=(.*)$")
        if key and value then
            value = value:gsub("^['\"]", ""):gsub("['\"]$", "")
            if not os.getenv(key) then
                rawset(_G, "_ENV_" .. key, value)
            end
        end
    end
    file:close()
end

local function getenv(key)
    return os.getenv(key) or rawget(_G, "_ENV_" .. key)
end

load_env_file(".env")
local TAVILY_API_KEY = getenv("TAVILY_API_KEY")
if not TAVILY_API_KEY then
    if VERBOSE then
        print("WARNING: TAVILY_API_KEY not set. Tavily search will fail.")
    end
    trace.warn("CONFIG", "TAVILY_API_KEY not set")
end

-- Session ID generator
local function random_id()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local id = {}
    for i = 1, 16 do
        local idx = math.random(1, #chars)
        id[i] = chars:sub(idx, idx)
    end
    return table.concat(id)
end

-- SSE event formatter
local function sse_event(event_name, data)
    local lines = {}
    if event_name then
        lines[#lines + 1] = "event: " .. event_name
    end
    lines[#lines + 1] = "data: " .. data
    lines[#lines + 1] = ""
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

-- JSON-RPC helpers
local function jsonrpc_response(id, result)
    return jsonic.encode({
        jsonrpc = "2.0",
        id = id,
        result = result,
    })
end

local function jsonrpc_error(id, code, message)
    return jsonic.encode({
        jsonrpc = "2.0",
        id = id,
        error = {
            code = code,
            message = message,
        },
    })
end

-- Tavily API call via lunet.httpc
local function tavily_search(query, max_results)
    if not TAVILY_API_KEY then
        return nil, "TAVILY_API_KEY not configured"
    end

    max_results = max_results or 5
    local request_body = jsonic.encode({
        query = query,
        max_results = max_results,
        include_answer = true,
        search_depth = "basic",
    })

    local api_url = getenv("TAVILY_API_URL") or "https://api.tavily.com/search"

    local resp, herr = httpc.request({
        url = api_url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. TAVILY_API_KEY,
        },
        body = request_body,
        timeout_ms = 30000,
        max_body_bytes = 5 * 1024 * 1024,
    })
    if not resp then
        return nil, "Tavily request failed: " .. (herr or "unknown")
    end

    local response = resp.body
    if not response or response == "" then
        return nil, "Empty response from Tavily API"
    end

    local ok, result = pcall(jsonic.decode, response)
    if not ok or not result then
        return nil, "Failed to parse Tavily response: " .. tostring(result)
    end

    if result.error then
        return nil, "Tavily API error: " .. tostring(result.error)
    end

    return result
end

-- MCP tool definitions (just tavily-search)
local tools = {
    {
        name = "tavily-search",
        description = "Search the web using Tavily AI search engine. Returns relevant web content with titles, URLs, and snippets.",
        inputSchema = {
            type = "object",
            properties = {
                query = {
                    type = "string",
                    description = "The search query",
                },
                max_results = {
                    type = "number",
                    description = "Maximum number of results (1-10, default 5)",
                },
            },
            required = { "query" },
        },
    },
}

-- Handle tool calls
local function handle_tool_call(name, arguments)
    trace.info("TOOL", "Calling tool: %s", name)

    if name == "tavily-search" then
        local query = arguments.query
        local max_results = arguments.max_results or 5
        if max_results > 10 then max_results = 10 end
        if max_results < 1 then max_results = 1 end

        trace.debug("TOOL", "tavily-search query=%s max_results=%d", query, max_results)

        local result, err = tavily_search(query, max_results)
        if not result then
            trace.error("TOOL", "tavily-search failed: %s", err or "unknown")
            return {
                content = {{type = "text", text = "Error: " .. (err or "unknown")}},
                isError = true,
            }
        end

        trace.debug("TOOL", "tavily-search returned %d results", result.results and #result.results or 0)

        local output = {}
        if result.answer then
            output[#output + 1] = "Answer: " .. result.answer
            output[#output + 1] = ""
        end
        if result.results then
            output[#output + 1] = "Results:"
            for i, r in ipairs(result.results) do
                output[#output + 1] = i .. ". " .. (r.title or "No title")
                output[#output + 1] = "   URL: " .. (r.url or "")
                if r.content then
                    local snippet = r.content:sub(1, 200)
                    if #r.content > 200 then snippet = snippet .. "..." end
                    output[#output + 1] = "   " .. snippet
                end
                output[#output + 1] = ""
            end
        end

        return {
            content = {{type = "text", text = table.concat(output, "\n")}},
        }
    end

    return {
        content = {{type = "text", text = "Unknown tool: " .. name}},
        isError = true,
    }
end

-- Handle MCP JSON-RPC requests
local function handle_mcp_request(msg)
    local method = msg.method
    local params = msg.params or {}
    local id = msg.id

    trace.debug("MCP", "Request: method=%s id=%s", method or "nil", tostring(id))

    if method == "initialize" then
        local negotiated = MCP_VERSION
        for _, v in ipairs(SUPPORTED_PROTOCOL_VERSIONS) do
            if params.protocolVersion == v then
                negotiated = v
                break
            end
        end
        return jsonrpc_response(id, {
            protocolVersion = negotiated,
            capabilities = {
                tools = EMPTY_OBJECT,
            },
            serverInfo = {
                name = SERVER_NAME,
                version = SERVER_VERSION,
            },
        })
    elseif method == "notifications/initialized" then
        return nil
    elseif method == "tools/list" then
        return jsonrpc_response(id, {
            tools = tools,
        })
    elseif method == "tools/call" then
        local tool_name = params.name
        local arguments = params.arguments or {}
        local result = handle_tool_call(tool_name, arguments)
        return jsonrpc_response(id, result)
    elseif method == "ping" then
        return jsonrpc_response(id, EMPTY_OBJECT)
    else
        return jsonrpc_error(id, -32601, "Method not found: " .. (method or "nil"))
    end
end

-- Session storage
local sessions = {}

-- Streamable HTTP sessions (POST /mcp transport, spec 2025-03-26)
local mcp_sessions = {}

-- Write a raw SSE response head (no Content-Length: the stream length is
-- unknown; the connection close or keep-alive delimits it)
local function write_sse_head(client, connection, extra_headers)
    local header_str = "HTTP/1.1 200 OK\r\n"
        .. "Content-Type: text/event-stream\r\n"
        .. "Cache-Control: no-cache\r\n"
    if connection == "close" then
        header_str = header_str .. "Connection: close\r\n"
    else
        header_str = header_str .. "Connection: keep-alive\r\n"
    end
    for k, v in pairs(extra_headers or {}) do
        header_str = header_str .. k .. ": " .. v .. "\r\n"
    end
    for k, v in pairs(http.cors_headers(CORS)) do
        header_str = header_str .. k .. ": " .. v .. "\r\n"
    end
    header_str = header_str .. "\r\n"
    socket.write(client, header_str)
end

-- Handle SSE connection (legacy transport)
local function handle_sse_request(client)
    write_sse_head(client, "keep-alive")

    local session_id = random_id()
    local endpoint = "/message?session=" .. session_id
    socket.write(client, sse_event("endpoint", endpoint))

    sessions[session_id] = {
        client = client,
        messages = {},
    }

    trace.info("SSE", "Session %s connected", session_id)
end

-- Handle legacy message POST
local function handle_message_request(client, request)
    local session_id = request.query_params.session
    if not session_id then
        socket.write(client, http.response(400, {}, jsonrpc_error(nil, -32600, "session parameter required"), CORS, false))
        return "close"
    end

    local session = sessions[session_id]
    if not session then
        socket.write(client, http.response(404, {}, jsonic.encode({error = "Session not found"}), CORS, false))
        return "close"
    end

    if not request.body or request.body == "" then
        socket.write(client, http.response(400, {}, jsonic.encode({error = "Empty body"}), CORS, false))
        return "close"
    end

    local ok, msg = pcall(jsonic.decode, request.body)
    if not ok or type(msg) ~= "table" or msg == jsonic.null then
        socket.write(client, http.response(400, {}, jsonic.encode({error = "Invalid JSON"}), CORS, false))
        return "close"
    end

    socket.write(client, http.response(202, {}, "", CORS, false))

    local response = handle_mcp_request(msg)
    if response and session.client then
        local err = socket.write(session.client, sse_event("message", response))
        if err then
            trace.info("SSE", "Session %s disconnected: %s", session_id, tostring(err))
            socket.close(session.client)
            sessions[session_id] = nil
        end
    end

    return "close"
end

-- Handle POST /mcp (Streamable HTTP transport)
local function handle_mcp_post(client, request)
    local persistent = request.persistent_connection
        and (request.headers["connection"] or ""):lower() ~= "close"

    local function respond_json(status, body, extra_headers)
        local headers = { ["Access-Control-Expose-Headers"] = "Mcp-Session-Id" }
        for k, v in pairs(extra_headers or {}) do
            headers[k] = v
        end
        socket.write(client, http.response(status, headers, body, CORS, persistent))
    end

    local function respond_sse(responses, extra_headers)
        write_sse_head(client, "close", extra_headers)
        for _, r in ipairs(responses) do
            socket.write(client, sse_event("message", r))
        end
    end

    if not request.body or request.body == "" then
        respond_json(400, jsonrpc_error(nil, -32600, "Invalid Request: empty body"))
        return "close"
    end

    local ok, msg = pcall(jsonic.decode, request.body)
    if not ok or type(msg) ~= "table" or msg == jsonic.null then
        respond_json(400, jsonrpc_error(nil, -32700, "Parse error"))
        return "close"
    end

    local messages = {}
    local is_batch = msg[1] ~= nil
    if is_batch then
        for _, m in ipairs(msg) do
            messages[#messages + 1] = m
        end
    else
        messages[1] = msg
    end

    local has_initialize = false
    for _, m in ipairs(messages) do
        if type(m) == "table" and m.method == "initialize" then
            has_initialize = true
        end
    end

    if not has_initialize then
        local session_id = request.headers["mcp-session-id"]
        if not session_id or session_id == "" then
            respond_json(400, jsonrpc_error(nil, -32600, "Missing Mcp-Session-Id header"))
            return "close"
        end
        if not mcp_sessions[session_id] then
            respond_json(404, jsonrpc_error(nil, -32600, "Session not found"))
            return "close"
        end
    end

    local responses = {}
    for _, m in ipairs(messages) do
        if type(m) ~= "table" or m == jsonic.null then
            responses[#responses + 1] = jsonrpc_error(nil, -32600, "Invalid Request")
        elseif m.method == nil and (m.result ~= nil or m.error ~= nil) then
            trace.debug("MCP", "Ignoring client response message")
        else
            local response = handle_mcp_request(m)
            if response then
                responses[#responses + 1] = response
            end
        end
    end

    local extra_headers = {}
    if has_initialize then
        local session_id = random_id()
        mcp_sessions[session_id] = { created = os.time() }
        extra_headers["Mcp-Session-Id"] = session_id
        trace.info("MCP", "Streamable HTTP session %s created", session_id)
    end

    if #responses == 0 then
        respond_json(202, "", extra_headers)
        return "close"
    end

    if (request.headers["accept"] or ""):find("text/event-stream", 1, true) then
        respond_sse(responses, extra_headers)
        return "close"
    end

    local body = responses[1]
    if is_batch then
        body = "[" .. table.concat(responses, ",") .. "]"
    end
    respond_json(200, body, extra_headers)

    return persistent and "keep" or "close"
end

-- Handle DELETE /mcp (session termination)
local function handle_mcp_delete(client, request)
    local session_id = request.headers["mcp-session-id"]
    if session_id and mcp_sessions[session_id] then
        mcp_sessions[session_id] = nil
        trace.info("MCP", "Streamable HTTP session %s terminated", session_id)
        socket.write(client, http.response(200, {}, "", CORS, false))
    else
        socket.write(client, http.response(404, {}, "", CORS, false))
    end
    return "close"
end

-- Route one parsed request. Returns "keep" (serve more requests on this
-- connection), "close" (connection consumed), or "hold" (stream left open).
local function route_request(client, request)
    trace.debug("HTTP", "%s %s", request.method, request.path)

    if request.method == "OPTIONS" then
        socket.write(client, http.preflight_response(CORS, false))
        return "close"
    end

    if request.path == "/sse" and request.method == "GET" then
        handle_sse_request(client)
        return "hold"
    end

    if request.path == "/mcp" then
        if request.method == "POST" then
            return handle_mcp_post(client, request)
        elseif request.method == "DELETE" then
            return handle_mcp_delete(client, request)
        elseif request.method == "GET" then
            socket.write(client, http.response(405, { ["Allow"] = "POST, DELETE" }, "", CORS, false))
            return "close"
        end
    end

    if request.path == "/message" and request.method == "POST" then
        return handle_message_request(client, request)
    end

    if request.path == "/" and request.method == "GET" then
        local info = {
            name = SERVER_NAME,
            version = SERVER_VERSION,
            protocol = "MCP",
            protocolVersion = MCP_VERSION,
            endpoints = {
                sse = "/sse",
                message = "/message?session=<id>",
                mcp = "/mcp",
            },
            tools = {},
        }
        for _, tool in ipairs(tools) do
            info.tools[#info.tools + 1] = tool.name
        end
        socket.write(client, http.json_response(200, info, CORS, false))
        return "close"
    end

    socket.write(client, http.response(404, {}, "Not Found", nil, false))
    return "close"
end

-- Main client handler: one connection, sequential requests until the
-- client closes, a framing error, or a request-declared close.
local function handle_client(client)
    local conn = http.new_connection(function()
        local chunk, read_err = socket.read(client)
        if not chunk then return nil, read_err end
        return chunk
    end)

    while true do
        local request, err, status = conn:next_request()
        if not request and not status then
            socket.close(client)
            return
        end
        if not request then
            socket.write(client, http.error_response(status or 400, { err }, nil, false))
            socket.close(client)
            return
        end

        local outcome = route_request(client, request)
        if outcome == "hold" then
            return
        end
        if outcome ~= "keep"
            or not request.persistent_connection
            or (request.headers["connection"] or ""):lower() == "close" then
            socket.close(client)
            return
        end
    end
end

-- Initialize random seed
math.randomseed(os.time())

-- Main server
lunet.spawn(function()
    local port = tonumber(getenv("PORT")) or 8080
    local host = getenv("HOST") or "127.0.0.1"
    local listener, err = socket.listen("tcp", host, port)
    if not listener then
        trace.error("SERVER", "Cannot listen on port %d: %s", port, err or "unknown")
        io.stderr:write("FATAL: Cannot listen: " .. (err or "unknown") .. "\n")
        return
    end

    trace.info("SERVER", "Starting on port %d", port)
    if VERBOSE then
        print("MCP Tavily Demo Server")
        print("======================")
        print("Protocol: MCP " .. MCP_VERSION .. " / " .. STREAMABLE_HTTP_VERSION)
        print("Server:   " .. SERVER_NAME .. " v" .. SERVER_VERSION)
        print("Port:     http://" .. host .. ":" .. port)
        print("")
        print("Endpoints:")
        print("  GET  /       -> Server info")
        print("  POST /mcp    -> Streamable HTTP transport (JSON or SSE responses)")
        print("  DELETE /mcp  -> Terminate Streamable HTTP session")
        print("  GET  /sse    -> SSE stream (creates session, legacy transport)")
        print("  POST /message?session=<id> -> Send JSON-RPC message (legacy transport)")
        print("")
        print("Tools: tavily-search")
        print("")
        print("Test:")
        print("  curl http://localhost:" .. port .. "/")
        print("  curl -N http://localhost:" .. port .. "/sse")
    end

    while true do
        local client = socket.accept(listener)
        if client then
            lunet.spawn(function()
                handle_client(client)
            end)
        end
    end
end)

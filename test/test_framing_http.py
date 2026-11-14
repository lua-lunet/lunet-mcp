#!/usr/bin/env python3
"""HTTP framing regression tests for the app/main.lua server.

Regression coverage for lua-lunet/lunet-mcp#22 (intermittent 400
"Invalid Request: empty body" when a client sends headers and body in
separate writes) and lua-lunet/lunet-mcp#23 (adoption of the upstream
lunet.http framing layer, which also fixed the silent truncation of
requests larger than one 4 KiB socket read).

How to run:

    # 1. Start the server (from the repo root):
    make run            # or: .lunet/v0.18.2/lunet-run app/main.lua

    # 2. In another shell (from the repo root):
    python3 test/test_framing_http.py

    PORT=9000 python3 test/test_framing_http.py   # custom port

Requires Python 3 stdlib only. Exits non-zero on any failure.
"""

import json
import os
import socket
import sys
import time

HOST = "127.0.0.1"
PORT = int(os.environ.get("PORT", "8080"))

PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else " :: " + str(detail)[:200]))

def send(req_bytes, read_all=True, timeout=10):
    s = socket.create_connection((HOST, PORT), timeout=timeout)
    s.sendall(req_bytes)
    chunks = b""
    while True:
        b = s.recv(65536)
        if not b: break
        chunks += b
    s.close()
    head, _, payload = chunks.partition(b"\r\n\r\n")
    lines = head.decode().split("\r\n")
    status = int(lines[0].split()[1])
    hdrs = {}
    for l in lines[1:]:
        if ":" in l:
            k, v = l.split(":", 1)
            hdrs[k.strip().lower()] = v.strip()
    return status, hdrs, payload

# 1. Issue #22 deterministic repro: headers first, body later -> must be 200 now
body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                   "params": {"protocolVersion": "2025-03-26", "capabilities": {},
                              "clientInfo": {"name": "p", "version": "0"}}}).encode()
s = socket.create_connection((HOST, PORT), timeout=10)
s.sendall(b"POST /mcp HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n"
          b"Accept: application/json\r\nContent-Length: %d\r\n\r\n" % len(body))
import time; time.sleep(0.5)
s.sendall(body)
resp = s.recv(65536).decode()
s.close()
check("#22 split-write initialize -> 200", " 200 " in resp.split("\r\n")[0], resp)
check("#22 split-write returns Mcp-Session-Id", "mcp-session-id:" in resp.lower(), resp)

# shared session for authenticated calls
body0 = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                    "params": {"protocolVersion": "2025-03-26"}}).encode()
st0, h0, p0 = send(b"POST /mcp HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n"
                   b"Accept: application/json\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s" % (len(body0), body0))
SID = h0.get("mcp-session-id")
check("session for authenticated tests", st0 == 200 and SID, (st0, h0))

def post(body, extra=""):
    return send(b"POST /mcp HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n"
                b"Accept: application/json\r\nConnection: close\r\nMcp-Session-Id: %s\r\n%s"
                b"Content-Length: %d\r\n\r\n%s" % (SID.encode(), extra.encode(), len(body), body))

# 2. Large body (200 KiB) framed correctly
big_query = "x" * (200 * 1024)
body = json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                   "params": {"name": "tavily-search", "arguments": {"query": big_query}}}).encode()
st, hdrs, payload = post(body)
resp = json.loads(payload)
check("200 KiB body framed correctly", st == 200 and "result" in resp, (st, payload[:120]))

# 3. Body just over the old 4 KiB single-read window
body = json.dumps({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                   "params": {"name": "tavily-search", "arguments": {"query": "y" * 5000}}}).encode()
st, hdrs, payload = post(body)
resp = json.loads(payload)
check("5 KiB body framed correctly", st == 200 and "result" in resp, (st, payload[:120]))

# 4. Chunked transfer-encoding decoded
body = json.dumps({"jsonrpc": "2.0", "id": 4, "method": "tools/list"}).encode()
chunked = b""
chunk = body[:20]
chunked += b"%x\r\n%s\r\n" % (len(chunk), chunk)
if len(body) > 20:
    chunked += b"%x\r\n%s\r\n" % (len(body) - 20, body[20:])
chunked += b"0\r\n\r\n"
st, hdrs, payload = send(b"POST /mcp HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n"
                         b"Accept: application/json\r\nConnection: close\r\nMcp-Session-Id: %s\r\n"
                         b"Transfer-Encoding: chunked\r\n\r\n" % SID.encode() + chunked)
resp = json.loads(payload)
check("chunked body decoded", st == 200 and any(t["name"] == "tavily-search" for t in resp.get("result", {}).get("tools", [])), (st, payload[:120]))

# 5. Keep-alive: two requests on one connection
s = socket.create_connection((HOST, PORT), timeout=10)
r1 = json.dumps({"jsonrpc": "2.0", "id": 5, "method": "initialize",
                 "params": {"protocolVersion": "2025-03-26"}}).encode()
r2 = json.dumps({"jsonrpc": "2.0", "id": 6, "method": "ping"}).encode()
req = (b"POST /mcp HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n"
       b"Accept: application/json\r\nMcp-Session-Id: %s\r\nContent-Length: %d\r\n\r\n%s" % (SID.encode(), len(r1), r1)
       + b"POST /mcp HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n"
         b"Accept: application/json\r\nMcp-Session-Id: %s\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s" % (SID.encode(), len(r2), r2))
s.sendall(req)
buf = b""
while True:
    b = s.recv(65536)
    if not b: break
    buf += b
s.close()
check("keep-alive/pipelined requests both answered", buf.count(b'"id":5') == 1 and buf.count(b'"id":6') == 1, buf[:300])

# 6. Oversize body rejected with 413 at the cap (1 MiB + margin)
big = json.dumps({"jsonrpc": "2.0", "id": 7, "method": "tools/call",
                  "params": {"name": "tavily-search", "arguments": {"query": "z" * (1100 * 1024)}}}).encode()
s = socket.create_connection((HOST, PORT), timeout=10)
try:
    s.sendall(b"POST /mcp HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n"
              b"Accept: application/json\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s" % (len(big), big))
except (ConnectionResetError, BrokenPipeError):
    pass
try:
    payload = s.recv(65536)
except (ConnectionResetError, socket.timeout):
    payload = b""
s.close()
check("oversize body -> 413", b" 413 " in payload, payload[:120])

print()
print("PASS: %d  FAIL: %d" % (len(PASS), len(FAIL)))
if FAIL:
    for f in FAIL:
        print("  FAILED: " + f)
    sys.exit(1)

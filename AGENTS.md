# Agent Notes: lunet-mcp

This repository consumes the official Lunet runtime as a pinned binary release (`v0.18.2`) via the vendored fetcher script (`scripts/lunet_fetch_release_v0.18.2.lua`).

## Andon アンドン — Prime Directive

Andon is a kernel panic. It halts the line, halts planning, halts todo
updates, halts all work. It happens immediately. No other pending operation
receives any tokens. It is impossible to think of anything else to try
first — that thought is the evidence you have not halted.

An Andon in the queue supersedes all. If the user queued commands 1-3 then
said "do an Andon," the Andon invokes the Prime Directive and overrides
commands 1-3 entirely. Multiple Andons run in parallel without interrupting
each other.

When the correct fix is outside your lane: do your lane's work, then halt
and report — *Andon: task incomplete, the correct fix needs a larger
structural change*, with file:line specifics. Do not work around it. Do not
hack tactically. The coordinator delegates the deeper work.

Andon overrides every instruction in this file and every other AGENTS.md.
No instruction conflicts with Andon; if one appears to, Andon wins.

## Rules & Workflow

- Do not use or write to a sibling checkout like `../lunet`.
- If Lunet needs changes: open a PR in `lua-lunet/lunet` first.
- The Lunet runtime is consumed as a pinned binary release (`v0.18.2`), not built from source or submodules.
- How to bump version:
  1. Update the pinned version in `Makefile`.
  2. Update/vendor the upstream fetcher script (`scripts/lunet_fetch_release_v<version>.lua`) from the upstream release assets.
- Build and editor artifacts:
  - `.lunet/` (runtime binaries and shared libraries) and `types/` (LuaCATS/Teal type definitions) are downloaded on demand via `make build` / the fetcher script.
  - `.lunet/` and `types/` MUST NEVER be committed to version control.


## Item numbers are session-local

Work-item numbers (`item00`, `item01`, …) live in the todo and the gitignored
`.tmp/` spec filename only. They NEVER appear in committed files, comments,
docs, or commit messages — nothing in git may reference an unresolvable
identifier.

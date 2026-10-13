# Vendored swift-sdk (Windows only)

`Sources/MCP` is copied from [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk)
at tag **0.12.1** (MIT, see `LICENSE`). The root `Package.swift` uses this copy
**only when building on Windows**; macOS and Linux keep the upstream package.

## Why

`Sources/MCP/Base/Transports/HTTPClientTransport.swift` uses `#if os(Linux)` to
mean "not an Apple platform". On Windows that sends the build down the Apple
branch, which imports `EventSource` — a dependency the SDK's own manifest only
provides on Apple platforms — so the `MCP` module fails to compile with
`no such module 'EventSource'`. No upstream release has a fix (checked
2026-10-13, latest is 0.12.1).

## The patch

In `HTTPClientTransport.swift` only:

- `#if os(Linux)` → `#if os(Linux) || os(Windows)`
- `#if !os(Linux)` → `#if !(os(Linux) || os(Windows))`

Windows uses swift-corelibs-foundation, like Linux, so the Linux branches are
the right ones. Nothing else in `Sources/MCP` is changed.

GODDESS doesn't use the HTTP client transport; it only needs the module to
compile. The stdio transport GODDESS uses on Windows lives in
`Sources/Products/GODDESS/MCP/WindowsStdioTransport.swift`, because upstream's
`StdioTransport` only exists on Darwin, Glibc and Musl.

## Updating

Copy `Sources/MCP` from the new upstream tag, re-apply the patch above, and
drop this folder entirely once upstream builds on Windows unmodified.

# ToolboxScriptRuntime

QuickJS **2026-06-04**, MIT, from <https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz>.
Archive SHA-256: `b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a`.

Only engine sources are included; no `quickjs-libc`, std/os module, CLI, filesystem,
network, module loader or host timers. Upstream files are unchanged. `ToolboxBridge.c`
and `include/CQuickJS.h` are the app-specific boundary. `SOURCE_MANIFEST.json`
records the exact source inventory. The package is local and builds without downloads.

The bridge evaluates shipped bundles only, parses an encoded request as JSON and
calls a fixed function. User SQL/JavaScript/HTML is never evaluated as code.
Each request owns one runtime and context. Native cancellation is atomic. Runtime
heap is 128 MiB, VM stack 1 MiB on a dedicated 4 MiB worker stack; cold load has
10 seconds, operation 5 seconds (MJML 10). The allocator records denied allocations
so a library cannot disguise OOM as a syntax error. Returned JSON is bounded to
8 MiB; transformed content has a separate 4 MiB UTF-8 limit.

C sources are built with `-O2` in Debug too: unoptimized QuickJS exceeded its stack
guard in ordinary parser fixtures. This does not enable JIT or execute user code.
No input, result or engine exception is logged or persisted.

Changes to upstream version, bridge or memory/stack/deadline policy require targeted
runtime/security regression on macOS and iOS Simulator. See
[development checks](../../docs/DEVELOPMENT.md) and [verification limits](../../PUBLIC_RELEASE_AUDIT.md).

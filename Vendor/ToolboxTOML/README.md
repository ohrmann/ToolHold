# ToolboxTOML — pinned local TOML parser

Upstream: https://github.com/cktan/tomlc17
Commit: bbf1a3bf97d36d63744d12f4ae78047db5b662cb (2026-10-16).
Retrieved 2026-10-18. MIT license: LICENSE; full notice also in app resources.
TOML 1.1 grammar. No remote SwiftPM dependencies or runtime network access.

Only src/tomlc17.c, src/tomlc17.h and LICENSE are vendored, with local SwiftPM/module metadata.
`toolbox.patch` records every source modification relative to the pinned originals:

- EOF diagnostics for inline arrays/tables report their expected closing delimiter from native parser state.
- Exact source UTF-8 byte spans on value datums, including unrounded number and timestamp tokens.
- Structured syntax/resource/numeric-range/cancellation statuses and reported byte offset.
- Per-parse cancellation callback, no mutation of global allocator/options. Cancel cannot return a successful partial tree.
- Combined inline-container recursion capped at 64; dotted key path cap aligned to 64.
- Library table/array count caps raised to the app input bound (262144) so no independent 16k-node limit is introduced. Swift enforces actual JSON depth64 including implicit TOML root/array-of-table wrappers.
- Original bounded numeric/timestamp token buffer retained: maximum 118 bytes, a resource-limit status rather than Invalid TOML. This is a documented parser implementation bound, not a truncation.

The app only calls in-memory toml_toolbox_parse()/toml_free(), never the library's file APIs.
Native Double values validate finite range only; output uses the original source token.
Swift UTF-8 checks reject invalid decoded escape sequences instead of replacing data.
Upstream may issue narrowing-conversion warnings under the project's C warning flags;
all in-memory sizes/offsets are bounded well below INT_MAX. No warning suppression was added.

Original source SHA-256:
- toolbox-tomlc17-original.c: d1187db58aa32b49d0df755d2e62378dcbb577c0f5314d73f366d974fb95a052
- toolbox-tomlc17-original.h: 29c0909092f4b23c7edce705167064f4a90548db5334b4aa2cd95d7ad801adb9

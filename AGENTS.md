# Contributor and agent instructions

This is Developer Toolbox, branded ToolHold, a native Swift/SwiftUI application. Start with [README.md](README.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and the affected tool in [docs/TOOL_CATALOG.md](docs/TOOL_CATALOG.md).

- Keep changes focused; preserve core/UI boundaries, typed workers, cancellation/revision checks and resource bounds. Avoid unrelated refactoring or dependencies.
- Keep working inputs, outputs and secrets in memory. Do not add document persistence, telemetry or implicit network access. Preview resource loading has a narrow, explicit opt-in policy; see architecture.
- Preserve native editor identity, selection, Undo and IME. Verify affected focus, scrolling and hide/show behavior at runtime when changing those paths.
- Do not execute user input as code or implement cryptographic standards from scratch. Keep JWT decoding separate from verification and certificate inspection separate from trust.
- Use synthetic fixtures. Never log, upload or commit working credentials, private keys, customer data or identifying diagnostics.
- Build: `xcodebuild -project "Developer Toolbox.xcodeproj" -scheme "ToolHold Navigation" -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/local-macos CODE_SIGNING_ALLOWED=NO build`.
- Tests: `swift test --scratch-path .build/tests`; use `--filter` for affected suites. See [development](docs/DEVELOPMENT.md) for resource checks and UI/harness limitations. Documentation-only changes need content/link checks and any tests that consume edited documents, not an unrelated full runtime run.
- Report checks actually performed and untested cases. A build is not GUI, sandbox, signing or device verification. Investigate a failed UI run before retrying it without a changed condition.
- Dependency updates require an exact stable version, checksum, official advisory review, source/license evidence, retained notices and relevant regressions. Keep vendored modifications documented.
- Preserve `LICENSE`, `NOTICE` and third-party notices. Follow `BRANDING_TERMS.md` when working with branding assets.
- Ordinary local commits are allowed within agreed tasks. Pushes (including force-push), release publication and repository setting changes require explicit authorization. Do not rewrite existing history without explicit authorization. Preserve unrelated working-tree changes.

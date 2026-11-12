# Development and verification

Use the [root README](../README.md) for supported platforms, Xcode builds, SwiftPM tests and signing limitations. [Architecture](ARCHITECTURE.md) describes the boundaries to preserve; [Contributing](../CONTRIBUTING.md) describes review expectations.

## Focused tests

Run from the repository root. Swift Testing and XCTest share the SwiftPM entry point:

```sh
swift test --scratch-path .build/tests
swift test --scratch-path .build/tests --filter JSONCoreTests
swift test --scratch-path .build/tests --filter NavigationCoreTests
```

Choose suites for the changed core from [Package.swift](../Package.swift). A substantial parser, crypto or shared-editor change needs corresponding negative, boundary and cancellation tests. UI work may need a native probe or the separate Xcode UI target; a core test does not verify Save dialogs, provider behavior, App Sandbox or editor focus.

Two suites consume documentation paths directly:

- `NavigationCoreTests.canonicalCatalogMatchesDocumentation` parses [TOOL_CATALOG.md](TOOL_CATALOG.md). Keep category titles, order, IDs, tool titles and navigation descriptions aligned with `MyApp/NavigationCore/ToolCatalog.swift`.
- `JSONProcessorTests.checkedInFixtures` loads JSON files from [M0_TEST_FIXTURES](M0_TEST_FIXTURES/README.md). Preserve those paths or update the consumer in the same change. These are deliberately synthetic and sometimes malformed inputs.

[Generated-model compiler tests](../Tests/GeneratedModels/README.md) are an optional separate harness with explicit Swift, TypeScript, .NET, Java/Jackson and Kotlin toolchains. They are not automatically run by `swift test`; unavailable compilers are not successful checks. Retained fixture READMEs document synthetic certificate/JWT/QR origins and reproduction requirements. Never replace them with real credentials or customer input.

## Resource and notice checks

These checks use checked-in inputs and do not download dependencies:

```sh
python3 scripts/code-markup/check.py
python3 scripts/check-network-references.py
python3 scripts/GenerateHTMLEntityTable.py --check
python3 scripts/check-third-party-notices.py
```

For app bundle checks, first build as shown in the README, then run:

```sh
python3 scripts/verify-release-packaging.py .build/local-macos/Build/Products/Debug/ToolHold.app
python3 scripts/check-third-party-notices.py .build/local-macos/Build/Products/Debug/ToolHold.app
```

The [script index](../scripts/README.md) separates validation from generators that overwrite resources or build vendored binaries. Normal app builds need neither npm nor online package resolution. Regeneration is deliberate work: preserve source/version/checksum manifests and notices, review the diff and run affected tests. Do not refresh data or upgrade a dependency as a side effect of an unrelated change.

## Platform probes

`Tests/Native*` contains focused platform harnesses for editor, preview, crypto and file behavior. They are not an additional automatically discovered test suite. Read a harness before running it: some interact with clipboard, dialogs, file destinations or system services. Use disposable data and locations. Probe builders in [scripts](../scripts/README.md) create temporary apps for macOS or iOS Simulator; a probe success does not establish production signing or provider compatibility.

For a macOS probe requiring sandbox validation, use the builder's documented `--sandbox` option where available, then inspect actual entitlements and exercise the relevant behavior. For system Save/export failures, inspect the failed run and identify a changed condition before repeating UI automation; do not change team, bundle ID or provisioning just to make a test pass.

## Reporting verification

Use focused checks for a local fix and broader checks for shared behavior or a release candidate. Documentation changes normally require content, links and diff checks; run tests when a document is an actual fixture or metadata input. Record commands, results and untested platforms. Distinguish a current run from retained historical evidence, compilation from GUI behavior, and source-publication readiness from binary distribution. Do not mark a feature released or invent a release date from an implementation task.

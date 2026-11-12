# Contributing

Developer Toolbox is source-available under [PolyForm Perimeter 1.0.1](LICENSE) for the project rights Vitalii Kolosov is entitled to license. Read [NOTICE](NOTICE), [third-party terms](THIRD_PARTY_NOTICES.md) and [asset provenance](ASSET_PROVENANCE.md) before reusing or contributing material. The [separate branding permission](BRANDING_TERMS.md), Version 1, is effective 2026-11-12 and accommodates technical forks, builds and permitted app redistribution for the listed artwork within its stated scope.

## Issues

- Search existing issues. Describe the expected and actual behavior, app revision, macOS/Xcode version and exact reproduction steps.
- Reduce input to a synthetic example. Remove credentials, private URLs, keys, personal data and identifying file paths from text, screenshots and logs.
- Report potential vulnerabilities using [SECURITY.md](SECURITY.md), with no exploit details or sensitive payloads in public discussions.

## Pull requests

- Keep changes focused. Explain the concrete problem, changed behavior, verification performed and any untested platforms or risks.
- Follow the existing Swift/SwiftUI and core/UI boundaries. Avoid unrelated refactoring, new features or dependencies in bug fixes. Discuss large changes before implementing them.
- Preserve offline processing, memory-only working data, cancellation/resource limits and native editor selection/Undo behavior. Do not add input/output persistence, telemetry or network calls without an explicit design decision.
- Add a stable regression test when fixing consequential logic. Follow the build/test instructions in [README.md](README.md); report unavailable checks honestly. Documentation-only edits do not require a full runtime test run.
- Keep upstream copyright, licenses and modification notices intact. A dependency/resource update needs an exact source/version, checksum, license evidence and relevant tests.
- Submit only material you have the right to contribute. State the origin/license of copied code, datasets and artwork. Identify AI-assisted material and review it; do not submit confidential prompts or third-party content you cannot license.

Contributions to original project code are submitted under the repository's PolyForm Perimeter License 1.0.1 unless explicitly agreed otherwise. This does not assign copyright or authorize unrelated relicensing. Third-party material keeps its existing terms. Do not include branding assets whose distribution rights have not been established.

Maintainers may request changes or decline a contribution. No review deadline, support schedule or acceptance commitment is promised.

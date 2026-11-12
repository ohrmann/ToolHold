# Public source preparation and known limitations

Prepared: **2026-11-12**. This is an independent source snapshot for public review. Original private Git history, local diagnostics, private documentation archives, IDE user settings and historical automated UI-test screenshots are not included. The original private repository and its local archive remain separate.

## Source and rights basis

Vitalii Kolosov, acting as an individual, confirms rights in this personal project and the absence of contractual restrictions from his employer. The project was initiated and directed by him; substantial code was generated using Codex under his supervision. Main icons were created through ChatGPT Images at his direction; the [asset register](ASSET_PROVENANCE.md) distinguishes their derivatives, synthetic QR fixtures and system assets. These are owner-reported provenance/rights statements, not an independent examination of private contracts or generation accounts.

The standard [PolyForm Perimeter License 1.0.1](LICENSE), [required notice](NOTICE) and upstream [third-party terms](THIRD_PARTY_NOTICES.md) are retained. [Branding Permission Version 1](BRANDING_TERMS.md) was approved and became effective **2026-11-12**; its scope, permissions, restrictions and termination mechanism are unchanged. Neither the code license nor the branding permission guarantees exclusive copyright in every AI-generated fragment, uniqueness or third-party clearance beyond the rights the grantor can grant. No new concrete third-party borrowing concern is inferred solely from AI assistance.

The publication snapshot starts an independent Git repository on `main`, with no inherited commits, refs, reflogs, object alternates, private remote or copied Git configuration. An explicit file manifest selected current working-tree content, including reviewed uncommitted changes. No ignored archive or bulk untracked-file copy was used. Automatic UI captures are omitted; required synthetic image and cryptographic fixtures remain.

## Verification status

The following checks ran from this publication copy on **2026-11-12**, using Xcode 27.2 / Swift 6.4.2 on macOS 27.2.1, Apple Silicon. DerivedData, module/package caches, logs and SwiftPM scratch output were separate from both source repositories. No original-checkout configuration, dependency cache or build product was used as an input. This is current-computer verification, not a clean-machine, Intel-hardware or physical-device test.

| Category | Status | Result |
|---|---|---|
| Security audit | WARNING | Copy-specific scan found no confirmed live secret, personal absolute path or private-remote reference. Previously audited synthetic fixtures retained. Privacy and binary-security limits below remain. |
| Git history audit | PASS | Independent initialization on main; no inherited commits, refs, reflogs, object alternates, shared object storage or remote. Original private history remains unchanged. |
| Dependencies & licenses | WARNING | All seven local packages and required resources included; manifest/hash checks passed. All 101 retained upstream notice texts verified in source and both app bundles. Existing advisory/provenance limits remain. |
| Build reproducibility | PASS | Unsigned macOS Release and generic iOS Simulator Debug (arm64/x86_64) builds succeeded from this copy with separate output/caches. No missing private configuration. |
| Architecture review | WARNING | Prior focused review/fixes retained; no application refactor or new exhaustive security assessment. |
| Automated tests | PASS | Main SwiftPM suite: 650 Swift Testing + 22 XCTest = 672 tests passed, no failures or reported skips. Separate UI/manual binary gates remain below. |
| Documentation | PASS | Local Markdown file/anchor links and consistency checked. Historical captures and references to them removed; current macOS screenshots remain optional. |
| License | PASS | Standard PolyForm and effective Branding Permission Version 1 copied unchanged. Owner confirms personal-project rights and no employer restriction; third-party terms and limits of available rights preserved. |

Reproducible entry points, from this repository root (the actual runs additionally supplied dedicated module/package cache paths and used four build jobs):

```sh
TOOLHOLD_VERIFY_DIR="$(mktemp -d /tmp/toolhold-verify.XXXXXX)"
xcodebuild -project "Developer Toolbox.xcodeproj" -scheme "ToolHold Navigation" \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$TOOLHOLD_VERIFY_DIR/macos" CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= build
xcodebuild -project "Developer Toolbox.xcodeproj" -scheme "ToolHold Navigation" \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$TOOLHOLD_VERIFY_DIR/simulator" CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= build
swift test --disable-sandbox --jobs 4 --scratch-path "$TOOLHOLD_VERIFY_DIR/tests" \
  --cache-path "$TOOLHOLD_VERIFY_DIR/swift-cache"
```

`--disable-sandbox` affects SwiftPM build tooling, not the application's App Sandbox. Builds retain existing warnings, principally C integer conversions in vendored code, Swift mutability/deprecated UI APIs and an unsupported SDKROOT condition; these were not suppressed or refactored in source preparation. The initial whole-tree whitespace check also reports inherited whitespace in 57 unchanged source, fixture and upstream/generated files; none is introduced by the public-only document edits. Those files remain byte-identical to preserve the selected source, fixture behavior, hashes and notices.

Offline checks passed: `scripts/code-markup/check.py`, `scripts/check-network-references.py`, `scripts/GenerateHTMLEntityTable.py --check` (2,231 entities) and `scripts/check-third-party-notices.py`. `scripts/verify-release-packaging.py` and the notice checker also passed for both built app bundles (privacy manifest/plist/icon metadata and notices). Local Markdown targets/anchors were checked, with the existing upstream DocC semantic link left to DocC resolution. External URL syntax was reviewed; remote availability was not exhaustively probed.

The explicit manifest contains 1,793 publication files. Every app source, test, fixture, dependency, build script and legal text matches its selected current-worktree source; public-only edits are limited to documentation and `.gitignore`. Both the standard `LICENSE` and the entire approved `BRANDING_TERMS.md` are byte-identical to the original. No local symlink, hardlink, nested repository or opaque IDE user state was copied. The pinned upstream OpenSSL source archive is retained as a required offline reproducibility input, with its existing source hash and license; it contains no Git metadata or archive path traversal.


## Known security and privacy limits

No confirmed live credential was found in the earlier audit; the copy-specific scan also found none before staging. Secret scanning is heuristic, not proof that every opaque value is harmless. Public synthetic keys and certificates must never be used outside tests. Earlier local-file URL and editor-expiry fixes are included without unrelated functional changes.

Working inputs and outputs are held in memory. Clipboard managers, native Undo, exports and system/provider staging can retain data; clearing the UI is not secure erasure. Static previews can explicitly load external HTTPS images, stylesheets and fonts; that opt-in discloses resource URLs and host connection metadata and is revoked on input changes. Scripts, frames and general navigation remain blocked. See [privacy](README.md#security--privacy) and [architecture](docs/ARCHITECTURE.md).

There is no claim of a current vulnerability-free dependency set, exhaustive similarity search, independent legal certification or complete manual platform coverage. Follow up on any concrete provenance or security issue found later; existing third-party terms remain applicable.

## Binary distribution gates


These remain open and are **not** resolved by preparing a source snapshot:

1. **PKI system Save:** the earlier macOS UI test passed Cancel, then failed to observe export completion after Save. It did not establish whether bytes were written or distinguish panel/provider/sandbox/test-lifecycle causes. A diagnostic retry failed earlier during Home setup and supplied no useful Save stack sample. Investigate this observed failure and verify export/overwrite under the intended signed app and destinations; passing core filesystem tests does not close it.
2. **OpenSSL advisories:** the pinned libcrypto is 4.0.3. The [official advisory list](https://openssl-library.org/news/vulnerabilities/), checked 2026-11-12, listed five low-severity issues from 2026-11-10 affecting versions before 4.0.4: CVE-2026-88823, CVE-2026-107496, CVE-2026-88822, CVE-2026-95691 and CVE-2026-95692. They concern AES-GCM-SIV, CMS encryption and QUIC. No application calls to those operations were found; QUIC is disabled and encrypted-key/PFX policy limits cipher use. This limits demonstrated reachability, not all possible indirect exposure. Review a current stable update, rebuild all slices and run relevant crypto regressions before distributing binaries. Historical npm audit snapshots are not current vulnerability clearance.
3. **Distribution checks:** production signing/notarization, actual sandbox entitlements, PKI Save/privacy/local permissions, physical devices, destination providers and relevant accessibility coverage need completion. No distribution-account or export-compliance clearance is claimed.

## Source publication and binary distribution

Preparing a source repository does not publish it or authorize a binary release. The copy-specific checks passed, and the owner has authorized the initial source commit with message `Initial public release of ToolHold`. Creating a GitHub repository, adding a remote, pushing or publishing releases requires separate owner instructions. Binary distribution remains subject to the gates above. Current macOS screenshots are optional presentation work, not missing build inputs.

## Final commit preparation — 2026-11-12

Agent instructions were simplified to permit ordinary local commits within agreed tasks while retaining explicit authorization for pushes, force-push, releases and repository setting changes. Legal documents and the approved branding permission are unchanged.

The index contains 1,793 files, about 135.32 MiB uncompressed. The largest is the pinned offline OpenSSL source archive at 55,235,667 bytes (52.68 MiB). It is below GitHub's 100 MiB per-file block threshold and above its 50 MiB warning threshold; no file exceeds the blocking limit. See [GitHub's file-size rules](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github). The archive remains an intentional reproducibility input, not a diagnostic artifact.

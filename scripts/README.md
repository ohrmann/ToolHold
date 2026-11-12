# Developer scripts

Run commands from the repository root. Python scripts use Python 3 and the standard library unless a procedure below states otherwise. Checked-in resources are normal build inputs; generators are optional and can overwrite files.

## Offline checks

| Command | Checks |
|---|---|
| `python3 scripts/code-markup/check.py` | Bundled JavaScript hashes, versions and manifest consistency |
| `python3 scripts/check-network-references.py` | Committed network-reference snapshots and metadata |
| `python3 scripts/GenerateHTMLEntityTable.py --check` | Generated HTML entity table against the pinned input |
| `python3 scripts/check-third-party-notices.py [APP]` | Required license/notice texts in source and, optionally, a built app |
| `python3 scripts/verify-release-packaging.py APP` | Platform-specific built-app packaging |

See [README build/test commands](../README.md) and [development guidance](../docs/DEVELOPMENT.md). Passing these checks is not a current vulnerability audit or an authorization to distribute binaries.

## Run and regenerate

- [run-macos.sh](run-macos.sh) builds and runs an unsigned macOS Debug app. See the [macOS run helper](../docs/IDE_RUN.md); editor-specific configurations are local.
- [Code & Markup bundles](code-markup/README.md): Node 22+ and npm are required only for deliberate regeneration. `npm ci` downloads pinned packages; an ordinary app build does not.
- [build-pki-backend.py](build-pki-backend.py) rebuilds the pinned offline OpenSSL archive using Xcode tools, Perl and make. See [ToolboxPKI](../Vendor/ToolboxPKI/README.md) and [OpenSSL provenance](../ThirdPartyNotices/OpenSSL/README.md). It replaces vendored XCFramework outputs; do not run it as a routine check.
- [GenerateHTMLEntityTable.py](GenerateHTMLEntityTable.py), [generate-network-references.py](generate-network-references.py) and [generate_text_unicode.py](generate_text_unicode.py) regenerate tables from pinned local inputs. Network/Unicode generators require a separately prepared directory of source files matching the manifests; they do not fetch those files themselves. Review their source/options, associated manifests and [third-party terms](../THIRD_PARTY_NOTICES.md) before changing a dataset.
- `generate-pki-fixtures.py`, `generate-pki-envelope-fixtures.py`, `generate-pki-negative-fixtures.py` and `pki-fixture-containers.c` support synthetic PKI corpora. They need their documented local crypto/compiler tools. Inspect commands and destinations first; generated keys are nonproduction test material. See [PKI fixtures](../Tests/PKICoreTests/Fixtures/README.txt).

## Native probe builders

`build-code-markup-probe.py`, `build-color-files-probe.py`, `build-date-network-probe.py` and `build-pki-probe.py` assemble focused native test applications using existing build products. Each requires `--platform`, `--derived-data` and `--output`; use `--help` for accepted platforms and optional flags. `ios` means Simulator; PKI also supports `ios-device` and requires an appropriate device setup for actual execution. Where present, `--sandbox` enables the macOS probe's sandbox configuration; check actual entitlements and behavior.

Read the associated `Tests/Native*` source before running a probe: it may interact with clipboard, Save dialogs or system services. Use disposable files and synthetic data. These harnesses are not automatically run by SwiftPM, and a probe success does not close the [remaining binary-release checks](../PUBLIC_RELEASE_AUDIT.md#binary-distribution-gates).

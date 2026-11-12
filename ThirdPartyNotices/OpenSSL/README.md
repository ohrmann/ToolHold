# OpenSSL / libcrypto provenance

- **Version:** 4.0.3, released 2026-09-29. This is a pinned build, not a claim of the current latest or vulnerability-free release; see [known advisory follow-up](../../PUBLIC_RELEASE_AUDIT.md#binary-distribution-gates).
- **License:** Apache-2.0, unmodified upstream text in [LICENSE.txt](LICENSE.txt). This application is not a FIPS-validated implementation.
- **Source:** <https://github.com/openssl/openssl/releases/download/openssl-4.0.3/openssl-4.0.3.tar.gz>; vendored offline in `Vendor/ToolboxPKI/upstream/`.
- **SHA-256:** `325b5c806167c13b40b1ffeadfe0248197c00eccc4cf123ec1e28d2d2fd216d9`, compared with the official release checksum. A detached PGP signature was not independently verified; do not claim otherwise.
- **Build:** `python3 scripts/build-pki-backend.py`; source is not patched. Exact configure switches and slices: `Vendor/ToolboxPKI/backend-manifest.json`. Built locally with Xcode 27 / Apple clang, five static slices: macOS arm64/x86_64, iOS arm64, Simulator arm64/x86_64. Package minimums macOS14/iOS17; application deployment settings remain unchanged.
- **Distribution:** static libcrypto only, no libssl, CLI, dynamic providers, HTTP/socket/TLS code, config autoload or DSO loading. The legacy provider is statically available and loaded only for an explicit legacy PFX read. The application bridge has a private library context and never supplies filesystem paths to OpenSSL, installs trust, or imports keys into Keychain.
- **Existing codec:** SwiftASN1 1.7.3 remains the existing vendored dependency; the retained source/version evidence is in its manifest. No additional ASN.1 implementation was introduced.

Before upgrading: check the latest stable upstream release and security advisories, verify the source checksum/provenance, rebuild every slice, run PKI interoperability/negative/sanitizer tests, and update this notice and the manifest. Do not update only a binary or silently switch a cipher/format profile. Exported PKCS#8 uses explicitly selected PBKDF2-HMAC-SHA-256/AES-256-CBC and 100,000 iterations. PFX uses the pinned release's PBES2/PBKDF2-HMAC-SHA-256/AES-256-CBC profile and explicit 100,000 encryption/MAC iterations; its actual protection metadata is displayed on import. Do not infer future library defaults from this pin.

Crypto algorithms are upstream implementations. Application-owned code is the bounded C ownership/policy bridge under `Vendor/ToolboxPKI/Sources/CToolboxPKI` and the Swift adapter/workspaces. [Verification and remaining gates](../../PUBLIC_RELEASE_AUDIT.md#binary-distribution-gates).

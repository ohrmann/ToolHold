# ToolboxPKI

Local Swift package for the Certificates & PKI tools. `CToolboxPKI` exposes a small DER/opaque-handle API over a locally built static OpenSSL 4.0.3 XCFramework. No production CLI, network request, Keychain import, arbitrary config, or file path API.

`upstream/` is the pinned official source archive; `backend-manifest.json` records its SHA-256 and build options. Rebuild offline with `python3 scripts/build-pki-backend.py` from the repository root. The script rejects an unexpected source checksum. Build outputs in `/tmp/toolbox-pki-build` can be removed before a clean reproduction. Five compiled slices are merged into three XCFramework platform groups.

Ownership: each TBPKI context owns keys, certificates, bags and providers. All returned TBPKIBuffer objects must be released with `tb_pki_buffer_free`; input buffers are borrowed only for the call. Export buffers and contexts are cleansed on C-side release. The Swift actor serializes access, checks revisions and owns context lifetime. Swift String/Data copies cannot be guaranteed wiped. Calling Cancel prevents publication; a synchronous OpenSSL call may finish before the serial worker processes another job.

See [license/provenance](../../ThirdPartyNotices/OpenSSL/README.md), [ownership and processing contracts](../../docs/ARCHITECTURE.md), [verification and remaining gates](../../PUBLIC_RELEASE_AUDIT.md#binary-distribution-gates).

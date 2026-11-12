# Offline language bundles

The application ships the checked-in bundles in `MyApp/CodeMarkupCore/Resources`.
Node/npm are developer-only dependencies, not required for Xcode builds or runtime.

To reproduce (from the repository root, with Node 22+ and npm):

```sh
npm ci --ignore-scripts --prefix scripts/code-markup
node scripts/code-markup/build.mjs
```

`package-lock.json` pins all versions/integrities. The build uses browser exports,
IIFE, ES2022, no runtime imports, source maps or downloads. The manifest records
bundle SHA-256/bytes and dependency licenses. `ThirdPartyNotices/CodeMarkup` retains
upstream license/notice files, including transitive dependencies. Optional esbuild
platform packages are build-time only. Regeneration may access npm during `npm ci`;
normal app builds and user processing never access npm or a remote service.

`engine.mjs` owns adapters, semantic checks and static-preview policy.
`mjml.mjs`/`polyfills.mjs` isolate the optional compiler bundle and pure Buffer shim.
Do not expose Node APIs, external resolution, dynamic modules or user evaluation.
Do not weaken minifier semantics or preview layers to make a fixture pass.

`npm-audit-2026-10-23.json` is a dated dependency audit snapshot (zero known findings),
not a claim of a security audit or future absence of vulnerabilities.

Check hashes without downloading or rebuilding:

```sh
python3 scripts/code-markup/check.py
```

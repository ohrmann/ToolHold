# Code & Markup notices

Pinned browser parser/formatter/compiler packages and their transitive notices.
See `MyApp/CodeMarkupCore/Resources/code-markup-manifest.json` for exact package
versions, npm integrity/resolved-source fields and bundle hashes. Build-time-only
packages are retained in the inventory as well. Runtime makes no package downloads.

Direct dependencies: sql-formatter 15.9.0 (MIT), Prettier 3.9.10 (MIT), yaml 2.9.1
(ISC), parse5 8.0.1 (MIT), css-tree 3.2.1 (MIT), Terser 5.51.2 (BSD-2-Clause),
Marked 18.1.1 (MIT), mjml-browser 5.4.1 (MIT), Cheerio 1.2.0 (MIT), Buffer 6.0.3
(MIT). esbuild 0.28.2 (MIT) is build-time only. Transitive files include MIT, ISC,
BSD-2/3-Clause, 0BSD, CC0 and Python-2.0 notices. No dependency was relicensed.

QuickJS's MIT license and source provenance live in `Vendor/ToolboxScriptRuntime`.
The dated npm audit is in `scripts/code-markup`; it does not cover QuickJS or amount
to an independent application-security assessment.

2026-11-12 notice audit: boolbase 1.0.0 omits a standalone LICENSE in its npm
artifact; its ISC text is now retained from the official upstream
https://github.com/fb55/boolbase/blob/master/LICENSE (retrieved 2026-11-12).
railroad-diagrams 1.0.0 omits a standalone license file but has a CC0 statement
in its pinned JavaScript header; that statement is retained verbatim in
node_modules_railroad-diagrams_NOTICE. Its current upstream license must not
be substituted for the pinned artifact's terms. These notices are also in the
packaged code-markup-licenses.txt; JavaScript bundles are unchanged.

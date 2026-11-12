# DynamicJSON JSONPath adaptation

Upstream: https://github.com/objecthub/swift-dynamicjson
Pinned source commit: `a5790021b30ecb60a1e3b7af708eb61e693f18ed` (reviewed 2026-10-18).
Copyright © 2024 Matthias Zenger. Apache License 2.0; see LICENSE.

Only the JSONPath query AST and parser are vendored in JSONCore/JSONPathEngine.
They are renamed JSONPathQuery/JSONPathQueryParser and modified. JSON input parsing,
JSON Schema, streaming, mutation, CLI tools and network-related code are not included.
The NodeID evaluator adapts upstream JSONPathEvaluator selection, descendant, slice,
filter and typed-value architecture to our immutable source document.

Local changes: retain numeric query lexemes; exact decimal and Unicode-scalar
comparisons; direct source NodeIDs instead of dictionary/Double conversion;
static function/type checking; reject arithmetic/variables/non-standard functions;
strict scalar escapes and surrogate decoding; source UTF-16 query positions;
query nesting/segment/result/work/time/copy budgets and task cancellation.
I-Regexp uses a separate non-checking RFC 9485 mapping to Foundation ICU with
progress/deadline checks; it is not a custom regex engine.

Maintenance: preserve these headers and the license, review upstream changes,
run the pinned JSONPath CTS plus targeted lossless/cancellation fixtures before
updating. The existing JSONProcessor is still the sole JSON-input grammar.

The application resource ThirdPartyNotices.txt includes attribution and license.

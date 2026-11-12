# Swift JSON Schema — vendored validator subset

- Upstream: https://github.com/ajevans99/swift-json-schema
- Commit: `8d314b50fa77814b12cf3c020878e47a4e78dc8a`
- License: MIT; full text in LICENSE and app ThirdPartyNotices.txt.
- Included: runtime JSONSchema + OrderedJSON sources and Draft 2020-12 resources.
- Excluded: builders, macros, conversions, networking, CLI, tests/docs tooling, all package dependencies.
- Location: MyApp/JSONCore/SchemaEngine. Public input always comes from JSONProcessor.inspectStructure;
  upstream parse convenience is only used for bundled trusted meta-schemas/test fixtures.

Local patches (2026-10-18):

1. Merge runtime modules; internal access replaces package access; Context renamed SchemaEngineContext
   to avoid SwiftUI representable Context collision. Foundation resource bundle support retained.
2. Narrow scalar-exact ordered map/set shim replaces swift-collections dependency; property maps,
   dependency maps, pointer components and object hashes preserve exact decoded scalar identities.
3. minLength/maxLength count Unicode scalars, not Swift graphemes.
4. Task-local lock-protected runtime budget: cancellation, deadline, work, stack depth,
   non-progress evaluation cycle guard. Checkpoints in compile/evaluation/large loops and arithmetic.
   Product adapter serializes jobs and uses a bounded 8 MiB native worker stack with cancellation relay.
5. Foundation regex with explicit ECMAScript-compatible mapping for dot/end, ASCII classes,
   whitespace, control escapes and boundaries; unsupported extensions are explicit. Bounded compile
   input/quantifiers and progress-cancellable matching. JSONPath I-Regexp code is not reused.
6. Typed additional-property metadata; bounded value-free branch messages and source-aware adapter.
7. Remove recursive Reference.resolved cache and clear context evaluation caches at root completion
   to prevent context/schema retain cycles while compiled schemas remain reusable.
8. Preserve actual child location for false-subschema diagnostics; transparent wrappers flatten
   into actionable issues while combinator branches retain hierarchy.
9. Product's fixed standard dialect is not disabled by a user schema's $vocabulary declaration.
   Upstream custom-meta handling remains available only to the conformance harness context.

No custom schema evaluator replaces upstream algorithms. Track patch changes against this pinned
source when updating; compare conformance, arithmetic, Unicode, ref/dynamic/annotation and budgets.

Official tests are separately vendored under Tests/JSONCoreTests/Fixtures/Schema202012 from
https://github.com/json-schema-org/JSON-Schema-Test-Suite commit
`55719286c33ae0d1823bfb65fea10338a19bc37c`, MIT license retained there.

Extension D-051 (2026-10-18):

- Native Draft-07 and 2019-09 keyword profiles: tuple items/additionalItems,
  dependencies, recursive anchors/references, reference sibling and ID scope semantics.
  No schema rewriting or independent evaluator. 2020-12 behavior retained.
- Dialect-specific bundled meta-schema loading; explicit resource registration reuses
  the existing engine context and resolver. Mixed-dialect sets are blocked by the adapter.
- Format validators are opt-in through an audited Toolbox profile. The upstream default
  validator collection is not enabled wholesale. This is not full format-assertion support.
- Fixture provenance for added Schema7 and Schema2019-09: same JSON-Schema-Test-Suite
  commit and MIT notice as Schema202012 above; original expectations unchanged.
- Draft-07 location-independent absolute IDs are registered/resolved by their complete URI;
  diagnostics retain the physical source document rather than fabricating pointer fragments on a named anchor.

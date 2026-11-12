# T-011 generated-code checks

This is developer tooling, never linked into the application. Fixtures contain synthetic data only. The Swift test exports **production generator output**, not hand-written equivalent models. No downloads/installations happen in `verify.py`.

```sh
MODELS_FIXTURE_DIRECTORY=/tmp/toolbox-models-artifacts swift test --filter JSONModelGenerationTests.exportProductionArtifactsForCompilerVerification
python3 Tests/GeneratedModels/verify.py --artifacts /tmp/toolbox-models-artifacts --tools /tmp/toolbox-models-tools
```

Use `--language swift|typeScript|cSharp|java|kotlin` and/or `--fixture Basic` to repeat only affected cases; `--start-at java/EmptyObject` continues a previously interrupted matrix. Each combination compiles the actual artifact, decodes the fixture and checks meaningful values/keys. DTO null/missing widening and original numeric spelling are deliberately not treated as round-trip failures. TypeScript checks positive/negative assignments and Node JSON parsing, not runtime schema validation.

## Pinned prerequisites

Actual versions and SHA-256 are in [toolchains.json](toolchains.json). Paths can differ on another machine:

- Apple Swift 6.4 / Foundation.
- TypeScript 5.9.3 extracted under `<tools>/package` (`package/bin/tsc`), Node 24.5.0. Optional explicit acquisition: download the versioned npm tarball to `<tools>/typescript.tgz`, verify its recorded SHA-256, then extract. No global npm install needed.
- .NET SDK 9.0.304 with restored .NET 8 reference packs; generated code compiles as C# 12 / net8.0. The test executable rolls forward to installed runtime 9.0.8. This does **not** test execution on runtime .NET 8. `DOTNET_CLI_HOME` and telemetry-off are set by the runner. A first restore may require network access for standard reference packs.
- JDK 17.0.16 (`MODELS_JDK_BIN`, then `JAVA_HOME/bin`, then `javac` on PATH). No personal JDK path is assumed. Jackson databind/core 2.22.2, annotations 2.22 in the normal Maven cache. This checks the Jackson **2** package profile, not Jackson 3.
- Kotlin compiler/serialization plugin 2.2.20; runtime core/json JVM 1.9.0. Local cached jars were reused; no Kotlin runtime is bundled with Toolbox.

Kotlin command configuration is `<tools>/kotlin.json`:

```json
{
  "java": "/absolute/jdk17/bin/java",
  "compiler": ["/absolute/kotlin-compiler-embeddable-2.2.20.jar", "/absolute/kotlin-stdlib-2.2.20.jar", "/absolute/kotlin-reflect.jar", "/absolute/kotlinx-coroutines-core-jvm.jar", "/absolute/annotations.jar"],
  "plugin": "/absolute/kotlin-serialization-compiler-plugin-embeddable-2.2.20.jar",
  "libs": ["/absolute/kotlin-stdlib-2.2.20.jar", "/absolute/kotlinx-serialization-core-jvm-1.9.0.jar", "/absolute/kotlinx-serialization-json-jvm-1.9.0.jar", "/absolute/annotations.jar"]
}
```

`compiler` is the Java compiler process classpath; `libs` is the generated-code compile/runtime classpath. Compiler/plugin must match. Missing tools or dependencies fail explicitly; do not report a missing backend as passed.

## Runtime traps covered

- Kotlin's ordinary JsonElement encoding can round long decimals. The generated JsonElement-backed wrapper serializer uses the official `JsonUnquotedLiteral` API (explicit experimental opt-in), including root/array/mixed values. It does not parse JSON grammar.
- Jackson treats `@JsonProperty("")` as an implicit property name. Empty names use an exact AnySetter/AnyGetter bridge with helper names that avoid source keys. The typed empty-key value is available via `emptyMemberValue()`.
- Encoding empty Java POJOs in the harness disables `FAIL_ON_EMPTY_BEANS`; decoding uses the actual generated `fromJson`. This is a consumer serializer configuration, not a hidden Toolbox parser change.

See [development guidance](../../docs/DEVELOPMENT.md) for test scope and [verification limitations](../../PUBLIC_RELEASE_AUDIT.md). Run this harness explicitly when changing generated-model profiles; the SwiftPM summary alone does not establish consumer-toolchain coverage.

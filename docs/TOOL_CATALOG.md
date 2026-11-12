# Tool catalog

All 78 tool routes listed below are implemented and available in the application, across eight categories. Tool-specific input, output and format limits remain authoritative in the implementation and diagnostics. Checks before distributing signed binaries are tracked separately in [verification and known limitations](../PUBLIC_RELEASE_AUDIT.md#binary-distribution-gates).

This file is also a test contract: `NavigationCoreTests.canonicalCatalogMatchesDocumentation` reads category headings, table order, IDs, titles and navigation descriptions. Preserve that structure when updating metadata.

The Core column names the main implementation module. Engineering notes summarize behavior and constraints; they are not compatibility guarantees.

### Data & JSON (11)

| ID | Tool | Core | Engineering notes | Navigation description |
|---|---|---|---|---|
| T-001 | JSON Formatter / Validator / Minifier | `JSONCore` | Preserve JSON semantics and provide precise source diagnostics. | Format and validate |
| T-002 | JSON Tree Viewer | `JSONCore` | Search nested values and navigate to source without replacing the editor. | Explore JSON structure |
| T-003 | Structural JSON Diff | `JSONCore` | Compare structure independently of whitespace and object-key order. | Compare JSON structures |
| T-004 | JSONPath Explorer | `JSONCore` | Use the supported JSONPath dialect with bounded evaluation. | Query nested values |
| T-005 | JSON Schema Validator | `JSONCore` | Support the implemented schema drafts; resolve registered resources locally. | Check schema compliance |
| T-006 | JSON ↔ YAML | `JSONCore` | Make YAML scalar resolution and JSON representability explicit. | Convert JSON/YAML data |
| T-007 | JSON ↔ CSV / TSV | `JSONCore` | Require explicit choices for nested objects and flattening. | Convert objects and tables |
| T-008 | JSON ↔ XML | `JSONCore` | Expose mapping limits; JSON/XML conversion is not universally reversible. | Convert JSON/XML documents |
| T-009 | JSON ↔ TOML | `JSONCore` | Reject JSON values that cannot be represented by the TOML profile. | Convert JSON/TOML configurations |
| T-010 | CSV / TSV Table Viewer | `JSONCore` | Handle BOM, Unicode, quoting and large tables within resource limits. | Browse delimited tables |
| T-011 | JSON → Models | `JSONCore` | Generate Swift, TypeScript, C#, Java and Kotlin profiles with explicit numeric/null policies. | Generate typed models |
### Encoders & Inspectors (11)

| ID | Tool | Core | Engineering notes | Navigation description |
|---|---|---|---|---|
| T-012 | Base64 Text / Base64URL | `EncodingCore` | Keep alphabet, strict/forgiving mode and text encoding explicit. | Encode and decode text |
| T-013 | Base64 File / Image | `EncodingCore` | Process files incrementally; keep text decoding separate from binary data. | Encode files as text |
| T-014 | URL Percent Encode / Decode | `EncodingCore` | Distinguish URL components, form fields and URI text. | Escape URL components |
| T-015 | URL Parser & Query Editor | `EncodingCore` | Preserve query order, duplicate keys and raw representations. | Inspect and edit queries |
| T-016 | HTML Entity Encode / Decode | `EncodingCore` | Use the pinned HTML entity table and avoid accidental repeated decoding. | Convert HTML entities |
| T-017 | String Escape / Unescape | `EncodingCore` | Select Swift, JSON or JavaScript escaping explicitly. | Escape special characters |
| T-018 | Hex ↔ UTF-8 / Bytes | `EncodingCore` | Report invalid UTF-8 and preserve arbitrary bytes without replacement characters. | Inspect text as bytes |
| T-019 | GZip Compress / Decompress | `EncodingCore` | Bound decompressed output and expansion work. | Compress and decompress data |
| T-020 | JWT Decoder & Claims Inspector | `JSONCore` | Decoding does not verify a signature; inspect time claims separately. | Inspect token claims |
| T-078 | JWT Encoder | `JSONCore` | Select algorithm/key explicitly and protect signing material. | Encode token claims |
| T-021 | HTTP Basic Auth Header Builder | `EncodingCore` | Do not persist source credentials; Base64 is reversible. | Build credential headers |
### Generators & Crypto (11)

| ID | Tool | Core | Engineering notes | Navigation description |
|---|---|---|---|---|
| T-022 | UUID v4/v7, ULID, NanoID Generator | `GeneratorCore` | Use the UUID/ULID/NanoID profiles and cryptographically secure entropy. | Create unique identifiers |
| T-023 | Secure Password Generator | `GeneratorCore` | Use the system cryptographic RNG without a weak fallback or output history. | Create random passwords |
| T-024 | Passphrase Generator | `GeneratorCore` | Use the bundled wordlist and distinguish entropy estimates from guarantees. | Generate memorable secrets |
| T-025 | Random Token / Secret Generator | `GeneratorCore` | Generate bounded CSPRNG output and treat the result as a secret. | Generate random secrets |
| T-026 | Hash & Checksum Generator | `DigestCore` | Stream selected hashes/checksums over text or files. | Calculate data fingerprints |
| T-027 | HMAC Generator | `DigestCore` | Keep HMAC keys out of logs and preferences. | Authenticate messages with keys |
| T-028 | QR Code Generator | `QRCodeCore` | Render locally, protect function modules and verify decorated symbols. | Encode content as QR |
| T-029 | QR Code Decoder | `QRCodeCore` | Decode local images within image/pixel budgets; no camera/network service required. | Read codes from images |
| T-030 | X.509 Certificate Inspector | `CertificateCore` | Inspect PEM/DER certificates, extensions and fingerprints without implying trust. | Inspect certificate fields |
| T-031 | Password Strength Estimator | `PasswordStrengthCore` | Estimate locally; heuristic strength is not a security guarantee. | Estimate password resilience |
| T-032 | JWT Signature Verifier | `JSONCore` | Select the algorithm and key policy explicitly; separate signature and claims checks. | Check token signatures |
### Text & Strings (10)

| ID | Tool | Core | Engineering notes | Navigation description |
|---|---|---|---|---|
| T-033 | Text Diff | `TextCore` | Compare lines and optional character changes with bounded output. | Compare text changes |
| T-034 | List / Set Comparator | `TextCore` | Distinguish set and multiset operations and preserve selected ordering. | Find shared list entries |
| T-035 | Regex Tester | `TextCore` | Use the bounded PCRE2 profile; distinguish no matches from invalid patterns. | Test regular expressions |
| T-036 | String Case Converter | `TextCore` | Convert case and naming conventions using the selected profile. | Transform naming conventions |
| T-037 | Line Sort & Deduplicate | `TextCore` | Sort and deduplicate with explicit comparison and line-ending policies. | Organize and deduplicate lines |
| T-038 | Unicode / Invisible Character Inspector | `TextCore` | Inspect scalars, invisible/control characters and confusable hints. | Reveal hidden characters |
| T-039 | Lorem Ipsum Generator | `TextCore` | Generate configurable placeholder text. | Generate placeholder paragraphs |
| T-040 | Mock Data Generator | `TextCore` | Generate synthetic records; do not infer realistic personal data. | Generate sample records |
| T-041 | Text / Word / Byte Statistics | `TextCore` | Count text units, words, lines and encoded bytes explicitly. | Measure text size |
| T-042 | Find & Replace with Regex | `TextCore` | Preview replacements and apply edits with native Undo support. | Replace matching patterns |
### Date, Network & Numbers (10)

| ID | Tool | Core | Engineering notes | Navigation description |
|---|---|---|---|---|
| T-043 | Unix Timestamp Converter | `DateTimeCore` | Convert Unix timestamps with explicit units. | Convert epoch times |
| T-044 | ISO 8601 / RFC 3339 Inspector | `DateTimeCore` | Report unsupported syntax separately from malformed date/time input. | Inspect date representations |
| T-045 | Timezone Converter | `DateTimeCore` | Convert between named time zones without hiding DST ambiguity. | Compare times across zones |
| T-046 | Date Arithmetic | `DateTimeCore` | Perform explicit date arithmetic and interval calculations. | Calculate date intervals |
| T-047 | Cron Parser | `DateTimeCore` | Use an explicit supported cron dialect; no scheduler is installed. | Explain schedule expressions |
| T-048 | IPv4/IPv6 CIDR Calculator | `NetworkReferenceCore` | Calculate IPv4/IPv6 prefixes and ranges without scanning hosts. | Calculate subnets and ranges |
| T-049 | HTTP Status Reference | `NetworkReferenceCore` | Use the pinned offline HTTP status snapshot. | Look up response meanings |
| T-050 | MIME Type Lookup | `NetworkReferenceCore` | Distinguish registry entries, extension hints and operating-system fallback. | Identify content types |
| T-051 | chmod Permissions Calculator | `NetworkReferenceCore` | Convert symbolic and octal Unix permission representations. | Calculate file access modes |
| T-052 | Number Base Converter | `NumberCore` | Preserve exact integer/decimal values within supported bounds. | Convert numeric representations |
### Code & Markup (9)

| ID | Tool | Core | Engineering notes | Navigation description |
|---|---|---|---|---|
| T-053 | SQL Formatter | `CodeMarkupCore` | Use an explicit SQL dialect; never execute queries. | Improve query readability |
| T-054 | XML Formatter / Validator | `CodeMarkupCore` | Validate/format XML without loading external entities. | Format and check XML |
| T-055 | YAML Formatter / Validator | `CodeMarkupCore` | Keep alias expansion, scalar interpretation and resource limits bounded. | Format and check YAML |
| T-056 | HTML Formatter / Minifier | `CodeMarkupCore` | Format/minify markup without executing page scripts. | Reformat or compact HTML |
| T-077 | MJML Editor & Preview | `CodeMarkupCore` | Compile the pinned MJML engine locally; no includes/scripts; preview assets require opt-in. | Build responsive emails |
| T-057 | CSS Formatter / Minifier | `CodeMarkupCore` | Preserve supported CSS semantics while formatting/minifying. | Reformat or compact stylesheets |
| T-058 | JavaScript Formatter / Minifier | `CodeMarkupCore` | Parse and transform JavaScript; never evaluate user code. | Reformat or compact scripts |
| T-059 | Markdown Preview | `CodeMarkupCore` | Render sanitized Markdown; external HTTPS assets require explicit consent. | Preview rendered Markdown |
| T-060 | HTML Preview | `CodeMarkupCore` | Use isolated static WebKit preview with scripts blocked and external resources off by default. | Preview rendered HTML |
### Color & Files (8)

| ID | Tool | Core | Engineering notes | Navigation description |
|---|---|---|---|---|
| T-061 | HEX / RGB / HSL Color Converter | `ColorCore` | Handle sRGB channels and alpha explicitly. | Translate color representations |
| T-062 | WCAG Contrast Checker | `ColorCore` | Compare calculated contrast with the displayed WCAG thresholds. | Check text readability |
| T-063 | Image Format Converter | `ImageToolsCore` | Use supported raster formats and explicit alpha/color/metadata policies. | Change image encoding |
| T-064 | Image Resize / Compress | `ImageToolsCore` | Expose dimensions, aspect ratio, quality and compression tradeoffs. | Adjust dimensions and size |
| T-065 | Image Metadata Inspector / Stripper | `ImageToolsCore` | Inspect metadata and export a separate stripped result; GPS requires reveal. | Inspect or remove metadata |
| T-066 | SVG to CSS / Data URI | `ImageToolsCore` | Encode/decode SVG Data URIs without executing embedded scripts. | Embed vector graphics |
| T-067 | cURL to Code Converter | `RequestToolsCore` | Parse supported cURL literals and emit code; do not execute a request or shell. | Generate request snippets |
| T-068 | Connection String Inspector | `RequestToolsCore` | Inspect connection parameters with secrets masked; do not open a connection. | Inspect database connection parameters |
### Certificates & PKI (8)

| ID | Tool | Core | Engineering notes | Navigation description |
|---|---|---|---|---|
| T-069 | Self-Signed Development Certificate Generator | `PKICore` | Generate development certificate profiles with subject/SAN and explicit key/export policy. | Create development certificates |
| T-070 | CSR Generator & Inspector | `PKICore` | Generate/inspect PKCS#10 requests and validate their signatures. | Create and inspect requests |
| T-071 | PEM ↔ DER Converter | `PKICore` | Preserve DER bytes and object order when converting supported envelopes. | Change certificate encoding |
| T-072 | PKCS#12 / PFX Manager | `PKICore` | Handle the supported PKCS#12 encryption, integrity and identity profiles. | Package certificates and keys |
| T-073 | Certificate Chain Validator | `PKICore` | Validate against local anchors; offline checks do not establish fresh revocation status. | Check local certificate chains |
| T-074 | Certificate / Private Key Matcher | `PKICore` | Match keys with certificate material and a possession proof without exporting private parameters. | Check key correspondence |
| T-075 | Public / Private Key Inspector | `PKICore` | Inspect algorithm properties/fingerprints without exposing private parameters. | Inspect key properties |
| T-076 | Batch Certificate Expiration Report | `PKICore` | Process local certificate files/folders; preserve partial in-memory results on cancellation. | Review certificate expiry dates |

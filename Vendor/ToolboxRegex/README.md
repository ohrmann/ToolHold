# Local PCRE2 engine

Pinned upstream PCRE2 **10.49**, BSD-3-Clause WITH PCRE2-exception. Source archive and copied upstream file hashes: `manifest.json`; full upstream license in `../../ThirdPartyNotices/PCRE2/LICENCE.md` and the app notices.

16-bit UTF/UCP build, interpreter only (no SUPPORT_JIT). `CRegex` is a small application-owned adapter with atomic cancellation, monotonic deadlines, allocation accounting, compile/match/depth/heap/capture limits and `pcre2_next_match` global iteration. It does not log or retain input. Deadline is cooperative, not an OS hard real-time guarantee. The Swift raw pattern budget is 8,192 UTF-16 units; literal mode expands into safe hex escapes under a separate derived-pattern cap. All output is discarded when resource controls abort processing.

Update procedure: download the official release archive; verify/record its SHA-256; copy the same upstream source list in manifest; regenerate config/header/chartables from release generic files; retain the app-owned bridge and adapter; update versions/notices; run RegexContractTests and resource/cancellation/native-editor tests on supported platforms. Do not enable JIT without separate review.

# WHATWG HTML character references

Static public data, retrieved 2026-10-19 from https://html.spec.whatwg.org/entities.json.

- `entities.json`: 2231 records (2125 semicolon-terminated, 106 legacy spellings).
- SHA-256: `d741d877ac77c4194c4ad526b5b4a19aef8dfe411ab840a466891cdbb9f362e6`.
- Source: [HTML named character references](https://html.spec.whatwg.org/multipage/named-characters.html).
- Local generator: `python3 scripts/GenerateHTMLEntityTable.py`; verify without mutation using `--check`. No network/build-time generation.
- Generated lookup preserves all names/scalar sequences. Reverse encoder chooses deterministic single-scalar names; basic escapes use explicit names. Scanner implements reference states only, without markup parsing.
- Copyright WHATWG (Apple, Google, Mozilla, Microsoft). Raw standard/data attribution under CC BY 4.0; portions incorporated into source code under BSD-3-Clause, according to the included upstream `LICENSE` and [WHATWG IPR policy](https://whatwg.org/ipr-policy).
- Upstream HTML repository `main` observed at `1ea5faabf97bb6735dadd7919425cffce0c75dba` when retrieving its LICENSE. This is provenance for the license, **not a claim** that the hosted generated JSON is a file at that commit. The JSON is pinned by its own digest.
- No application data or network operations are involved at runtime.

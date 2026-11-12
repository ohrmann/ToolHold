# M0 benchmark fixtures — safe test data

These are **deliberately malformed**, fake or public test inputs; not customer data.

- `01` and `02`: semantic JSON equality (object key order differs).
- `01` vs `03`: real JSON changes.
- `04`–`09` and `13`: syntax errors / duplicate keys.
- `10`: integer precision and decimal lexical preservation.
- `11`: repeated URL query keys, Unicode and absent value.
- `12`: JSON-like invalid input should still trigger Smart Input suggestion.
- `14`: intentionally unsigned/malformed demonstration JWT; never mark verified.
- `15`: certificate testing should use self-generated nonproduction certificates, not copied private keys.

See [representation and diagnostic contracts](../ARCHITECTURE.md#parsing-and-representations). The current assertions in `Tests/JSONCoreTests/JSONProcessorTests.swift` define the regression expectations; historical milestone specifications are not current guarantees.

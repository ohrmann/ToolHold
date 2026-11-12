# Unicode data provenance

Pinned Unicode 17.0.0 data, Unicode License v3. `manifest.json` records source URLs/SHA-256 and generated-resource SHA-256. Download those listed files into a local directory, then run:

```
python3 scripts/generate_text_unicode.py /path/to/downloaded/ucd-files
```

The script emits `MyApp/TextCore/Resources/text-unicode17.json`. No runtime download occurs. Unicode names/categories/scripts, case folding and confusable hints use this table. Foundation normalization and Apple grapheme/language segmentation use the OS implementation, explicitly labelled in UI. Confusable mappings are explanatory hints, not a UTS #39 security verdict. Update the source version, manifest, app notices and golden fixtures together.

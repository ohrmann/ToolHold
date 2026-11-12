#!/usr/bin/env python3
"""Verify committed offline snapshots and source hashes (optional local downloads argument)."""
import json,hashlib,pathlib,sys
root=pathlib.Path(__file__).resolve().parents[1]/'MyApp/NetworkReferenceCore/Resources'
m=json.loads((root/'reference-manifest.json').read_text())
for r in m['registries']+[dict(m['extensions'],id='mime-extensions')]:
 b=(root/(r['id']+'.json')).read_bytes(); rows=json.loads(b)
 assert hashlib.sha256(b).hexdigest()==r['generatedSHA256']
 assert len(rows)==r['count'] and len({x['id'] for x in rows})==len(rows)
 if len(sys.argv)>1:
  source=pathlib.Path(sys.argv[1])/('mime-db.json' if r['id']=='mime-extensions' else r['id']+'.xml')
  assert hashlib.sha256(source.read_bytes()).hexdigest()==r['rawSHA256']
http=json.loads((root/'http-status.json').read_text()); covered=[n for r in http for n in range(r['low'],r['high']+1)]
assert sorted(covered)==list(range(100,600))
print('Registry hashes, unique IDs, counts and HTTP 100–599 coverage passed.')

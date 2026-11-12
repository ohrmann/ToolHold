#!/usr/bin/env python3
"""Offline check of shipped bundles and pinned native source inventory."""
import pathlib,json,hashlib
root=pathlib.Path(__file__).resolve().parents[2]
resources=root/'MyApp/CodeMarkupCore/Resources'
manifest=json.loads((resources/'code-markup-manifest.json').read_text())
for name,expected in manifest['bundles'].items():
    data=(resources/name).read_bytes()
    assert len(data)==expected['bytes'],name
    assert hashlib.sha256(data).hexdigest()==expected['sha256'],name
native=root/'Vendor/ToolboxScriptRuntime'
for name,digest in json.loads((native/'SOURCE_MANIFEST.json').read_text())['files'].items():
    assert hashlib.sha256((native/name).read_bytes()).hexdigest()==digest,name
lock=json.loads((root/'scripts/code-markup/package-lock.json').read_text())
for package in manifest['packages']:
    expected=lock['packages'][package['path']]
    assert package['version']==expected['version']
    assert package['integrity']==expected.get('integrity')
    assert package['license']
print('Bundle hashes, QuickJS inventory, locked versions/integrities/licenses: OK')

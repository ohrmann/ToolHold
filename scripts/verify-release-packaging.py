#!/usr/bin/env python3
"""Validate built manifest and icon packaging. Empty icon scaffolds never count as PASS."""
import argparse, json, plistlib
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('app', type=Path)
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
mac = (a.app / 'Contents').is_dir()
resources = a.app / 'Contents/Resources' if mac else a.app
info_path = a.app / 'Contents/Info.plist' if mac else a.app / 'Info.plist'
manifest = resources / 'PrivacyInfo.xcprivacy'
expected = plistlib.loads((root / 'MyApp/PrivacyInfo.xcprivacy').read_bytes())
actual = plistlib.loads(manifest.read_bytes())
assert actual == expected, 'Bundled privacy manifest differs from reviewed source'
print('PASS: bundled privacy manifest, plist structure and reviewed declarations')
contents = json.loads((root / 'MyApp/Assets.xcassets/AppIcon.appiconset/Contents.json').read_text())
images = contents['images']
required = [entry for entry in images if (entry.get('idiom') == 'mac') == mac]
assets = root / 'MyApp/Assets.xcassets/AppIcon.appiconset'
if not required or any(not entry.get('filename') or not (assets / entry['filename']).is_file() for entry in required):
    print('BLOCKED: Approved Icon Assets Required. No release-ready icon is claimed.')
    raise SystemExit(2)
info = plistlib.loads(info_path.read_bytes())
if mac:
    filename = info.get('CFBundleIconFile', '')
    assert filename and ((resources / filename).exists() or (resources / (filename + '.icns')).exists()), 'Missing packaged macOS icon'
else:
    assert info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconName'), 'Missing packaged iOS primary icon metadata'
print('PASS: icon assets and primary icon metadata (owner approval must be recorded separately)')

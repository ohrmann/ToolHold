#!/usr/bin/env python3
"""Offline check that retained dependency notices also accompany the app.

Pass an app bundle to check its packaged copies as well as source resources.
This checks notice preservation, not ownership or legal clearance.
"""
import argparse
from pathlib import Path


def check(main_path, markup_path):
    main = main_path.read_text()
    markup = markup_path.read_text()
    combined = main + '\n' + markup
    required = [p for p in (root / 'ThirdPartyNotices').rglob('*')
                if p.is_file() and any(s in p.name.lower()
                                       for s in ('license', 'licence', 'notice'))
                and p.suffix not in ('.c', '.h') and p.name != 'README.md']
    required += [root / 'Vendor/ToolboxTOML/LICENSE',
                 root / 'Vendor/ToolboxScriptRuntime/LICENSE',
                 root / 'ThirdPartyNotices/ZXingCpp/Hoehrmann.txt']
    missing = [str(p.relative_to(root)) for p in required
               if p.read_text().strip() not in combined]
    notice = 'Required Notice: Copyright (c) 2026 Vitalii Kolosov.'
    if notice not in main or 'https://polyformproject.org/licenses/perimeter/1.0.1' not in main:
        missing.append('Project notice / license URL')
    if missing:
        raise SystemExit('Missing bundled notice(s):\n' + '\n'.join(missing))
    print(f'PASS: {len(required)} retained license/notice files and project notice in {main_path.parent}')


root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path, nargs='?')
args = parser.parse_args()
if args.app:
    resources = args.app / 'Contents/Resources' if (args.app / 'Contents').is_dir() else args.app
    check(resources / 'ThirdPartyNotices.txt', resources / 'code-markup-licenses.txt')
else:
    check(root / 'MyApp/Resources/ThirdPartyNotices.txt',
          root / 'MyApp/CodeMarkupCore/Resources/code-markup-licenses.txt')

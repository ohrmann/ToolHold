#!/usr/bin/env python3
"""Generate pinned Unicode17 inspection data. Argument: directory of upstream text files."""
import sys,json,hashlib,shutil
from pathlib import Path
src=Path(sys.argv[1]);out=Path('MyApp/TextCore/Resources')
def rows(name):
 for l in (src/name).read_text().splitlines():
  l=l.split('#',1)[0].strip()
  if l:yield [x.strip() for x in l.split(';')]
def interval(s):
 a=s.split('..');return [int(a[0],16),int(a[-1],16)]
fold={r[0]:r[2] for r in rows('CaseFolding.txt') if r[1] in ['C','F']}
conf={r[0]:r[1] for r in rows('confusables.txt')}
chars={};ranges=[];start=None
for r in rows('UnicodeData.txt'):
 code=int(r[0],16)
 if r[1].endswith(', First>'):start=(code,r);continue
 if r[1].endswith(', Last>'):
  ranges.append([start[0],code,start[1][1].replace(', First>','>'),r[2],r[4]]);continue
 chars[str(code)]=[r[1],r[2],r[4]]
for r in rows('NameAliases.txt'):
 if r[2]=='control' and str(int(r[0],16)) in chars:chars[str(int(r[0],16))][0]=r[1]
data={'version':'17.0.0','fold':fold,'confusables':conf,'characters':chars,'characterRanges':ranges,'scripts':sorted([interval(r[0])+[r[1]] for r in rows('Scripts.txt')]), 'scriptExtensions':[interval(r[0])+[r[1]] for r in rows('ScriptExtensions.txt')], 'properties':[interval(r[0])+[r[1]] for f in ['PropList.txt','DerivedCoreProperties.txt'] for r in rows(f) if r[1] in ['White_Space','Default_Ignorable_Code_Point','Bidi_Control']]}
out.mkdir(exist_ok=True,parents=True);target=out/'text-unicode17.json';target.write_text(json.dumps(data,separators=(',',':'),ensure_ascii=True)+'\n')
manifest={'version':'17.0.0','files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(src.iterdir())},'generatedSHA256':hashlib.sha256(target.read_bytes()).hexdigest(),'baseURL':'https://www.unicode.org/Public/17.0.0/ucd/','confusablesURL':'https://www.unicode.org/Public/17.0.0/security/confusables.txt'}
Path('ThirdPartyNotices/Unicode/manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');shutil.copyfile(src/'LICENSE.txt','ThirdPartyNotices/Unicode/LICENSE.txt')

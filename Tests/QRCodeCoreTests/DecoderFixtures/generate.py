"""Development only: PYTHONPATH=/tmp/t029-fixturedeps python3 generate.py (Segno 1.6.6)."""
from pathlib import Path
import hashlib, json
import segno
assert segno.__version__ == '1.6.6'
root = Path(__file__).parent
cases = [
 ('numeric', '0012345678901234567890', dict(mode='numeric'), b'0012345678901234567890'),
 ('alphanumeric', 'ABC 123 $%*+-./:', dict(mode='alphanumeric'), b'ABC 123 $%*+-./:'),
 ('utf8-eci', '👩🏽‍💻 e\u0301 中文', dict(encoding='utf-8', eci=True), '👩🏽‍💻 e\u0301 中文'.encode()),
 ('latin1-eci', 'café Straße', dict(encoding='iso-8859-1', eci=True), 'café Straße'.encode('iso-8859-1')),
 ('cyrillic-eci', 'Привет мир', dict(encoding='cp1251', eci=True), 'Привет мир'.encode('cp1251')),
 ('kanji', '漢字日本', dict(mode='kanji'), '漢字日本'.encode('shift_jis')),
 ('binary', bytes(range(256)), dict(mode='byte',encoding='iso-8859-1'), bytes(range(256))),
 ('nul', b'\0start\0end\0', dict(mode='byte'), b'\0start\0end\0'),
 ('empty', b'', dict(mode='byte'), b''),
]
manifest = []
for name, content, options, expected in cases:
 code = segno.make(content,micro=False,error='m',boost_error=False,**options)
 path = root/(name+'.png'); code.save(path,scale=8,border=4)
 manifest.append(dict(name=name,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytesHex=expected.hex(),text=content if isinstance(content,str) else None,eci=options.get('eci',False) and options.get('encoding') != 'iso-8859-1'))
seq = segno.make_sequence('structured append example for decoder',version=2,symbol_count=2,error='m',boost_error=False)
for i,code in enumerate(seq):
 path=root/('sequence-'+str(i)+'.png');code.save(path,scale=8,border=4)
 manifest.append(dict(name=path.stem,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
(root/'manifest.json').write_text(json.dumps(dict(encoder='Segno 1.6.6 (BSD-3-Clause), development fixture generator only',cases=manifest),ensure_ascii=False,indent=2)+'\n')
# Explicit multi-mode fixture: Segno owns all segment framing/ECC/matrix generation.
from segno import encoder, consts
extra = []
def save_extra(name, code, data, text=None):
 path=root/(name+'.png'); code.save(path,scale=8,border=4)
 extra.append(dict(name=name,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytesHex=data.hex(),text=text,eci=True))
save_extra('mixed-eci',segno.make([(b'prefix',consts.MODE_BYTE,'utf-8'),('00123',consts.MODE_NUMERIC),('Ж',consts.MODE_BYTE,'cp1251')],micro=False,error='m',eci=True),b'prefix00123'+ 'Ж'.encode('cp1251'),'prefix00123Ж')
# Deliberately unsupported ECI assignment, encoded by the independent encoder.
original_assignment=encoder.get_eci_assignment_number
encoder.get_eci_assignment_number=lambda encoding: 127
save_extra('unknown-eci',segno.make(b'unknown-marker',mode='byte',encoding='utf-8',eci=True,micro=False,error='m'),b'unknown-marker')
encoder.get_eci_assignment_number=original_assignment
# GS1 first-position FNC1 mode indicator (0101); all further encoding remains Segno.
original_write=encoder.write_segment
first=[True]
def gs1_segment(buffer,segment,version,version_range,eci=False):
 if first[0]:
  buffer.append_bits(5,4);first[0]=False
 return original_write(buffer,segment,version,version_range,eci=eci)
encoder.write_segment=gs1_segment
code=segno.make('0101234567890128%10ABC',mode='alphanumeric',version=3,micro=False,error='m',boost_error=False)
encoder.write_segment=original_write
path=root/'gs1.png';code.save(path,scale=8,border=4)
extra.append(dict(name='gs1',sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytesHex=b'0101234567890128\x1d10ABC'.hex(),text='0101234567890128\x1d10ABC',eci=False))
manifest += extra
(root/'manifest.json').write_text(json.dumps(dict(encoder='Segno 1.6.6 (BSD-3-Clause), development fixture generator only',cases=manifest),ensure_ascii=False,indent=2)+'\n')
# Metadata-only resource-budget fixtures; these are rejected before pixel decoding.
from PIL import Image
for name,size in [('side-too-large',(32769,1)),('pixels-too-large',(8000,5001))]:
 im=Image.new('L',size,255);im.save(root/(name+'.png'));im.close()
manifest_doc=json.loads((root/'manifest.json').read_text())
manifest_doc['imageBudgetFixtures']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in root.glob('*too-large.png')}
(root/'manifest.json').write_text(json.dumps(manifest_doc,ensure_ascii=False,indent=2)+'\n')

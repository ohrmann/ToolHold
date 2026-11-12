#!/usr/bin/env python3
"""Offline, deterministic generator. Usage: script path/to/local/downloads.
See manifest for pinned URLs. Never run as an application build phase.
"""
import sys,json,hashlib,pathlib,xml.etree.ElementTree as ET
src=pathlib.Path(sys.argv[1]); root=pathlib.Path(__file__).resolve().parents[1]
out=root/'MyApp/NetworkReferenceCore/Resources'; ns={'i':'http://www.iana.org/assignments'}
def txt(e,tag):
 x=e.find('i:'+tag,ns); return ' '.join(''.join(x.itertext()).split()) if x is not None else ''
def refs(e):
 return sorted(set('https://www.rfc-editor.org/rfc/'+x.attrib['data']+'.html' for x in e.findall('.//i:xref',ns) if x.get('type')=='rfc'))
def dump(name,data):
 b=(json.dumps(data,ensure_ascii=False,sort_keys=True,indent=2)+'\n').encode(); (out/name).write_bytes(b); return hashlib.sha256(b).hexdigest()
urls={'http-status':'https://www.iana.org/assignments/http-status-codes/http-status-codes.xml','media-types':'https://www.iana.org/assignments/media-types/media-types.xml','ipv4-special':'https://www.iana.org/assignments/iana-ipv4-special-registry/iana-ipv4-special-registry.xml','ipv6-special':'https://www.iana.org/assignments/iana-ipv6-special-registry/iana-ipv6-special-registry.xml'}
manifest={'schemaVersion':1,'retrievalDate':'2026-10-22','registries':[]}
for key,url in urls.items():
 raw=(src/(key+'.xml')).read_bytes(); doc=ET.fromstring(raw); rows=[]
 for e in doc.findall('.//i:record',ns):
  if key=='http-status':
   value=txt(e,'value'); bounds=value.split('-'); rows.append(dict(id=value,low=int(bounds[0]),high=int(bounds[-1]),name=txt(e,'description'),references=refs(e)))
  elif key=='media-types':
   value=txt(e,'file')
   if '/' in value: rows.append(dict(id=value.lower(),name=value,references=refs(e)))
  else:
   notes=[]
   for ref in e.findall('.//i:xref',ns):
    if ref.get('type')=='note':
     note=doc.find('.//i:footnote[@anchor="'+ref.get('data','')+'"]',ns)
     if note is not None: notes.append(' '.join(''.join(note.itertext()).split()))
   for block in txt(e,'address').split(','):
    block=block.strip()
    if block: rows.append(dict(id=block,name=txt(e,'name'),source=txt(e,'source'),destination=txt(e,'destination'),forwardable=txt(e,'forwardable'),globalReachable=txt(e,'global'),reserved=txt(e,'reserved'),termination=txt(e,'termination'),notes=notes,references=refs(e)))
 # MIME registry can repeat a registration spelling; retain one factual registration per case-insensitive type.
 merged={}
 for x in rows:
  if x['id'] in merged: x['references']=sorted(set(x['references']+merged[x['id']]['references']))
  merged[x['id']]=x
 rows=list(merged.values()); rows.sort(key=lambda x:x['id'])
 digest=dump(key+'.json',rows)
 manifest['registries'].append(dict(id=key,sourceURL=url,registryLastUpdated=txt(doc,'updated'),count=len(rows),rawSHA256=hashlib.sha256(raw).hexdigest(),generatedSHA256=digest))
# Curated common extensions, with all matching types retained from pinned mime-db (MIT).
exts=set('txt text html htm css csv tsv json map jsonld xml yaml yml toml js mjs cjs ts pdf zip gz tgz tar 7z rar png jpg jpeg gif webp avif svg svgz ico bmp tif tiff heic heif mp3 wav ogg mp4 mov webm woff woff2 ttf otf wasm md markdown pem crt cer der p12 pfx doc docx xls xlsx ppt pptx bin'.split())
db=json.loads((src/'mime-db.json').read_text()); maps=[]
for typ,meta in db.items():
 for ext in meta.get('extensions',[]):
  if ext in exts: maps.append(dict(id=ext+':'+typ,extension=ext,type=typ,source='mime-db 1.54.0 ('+meta.get('source','unspecified upstream')+') · https://github.com/jshttp/mime-db/tree/v1.54.0'))
# These two IANA template facts are absent from mime-db 1.54.0's extension metadata.
for ext,typ in [('toml','application/toml'),('yaml','application/yaml'),('yml','application/yaml')]:
 if not any(x['extension']==ext and x['type']==typ for x in maps): maps.append(dict(id=ext+':'+typ,extension=ext,type=typ,source='IANA registration template: https://www.iana.org/assignments/media-types/'+typ))
maps.sort(key=lambda x:x['id']); digest=dump('mime-extensions.json',maps)
manifest['extensions']=dict(sourceURL='https://github.com/jshttp/mime-db/tree/v1.54.0',license='MIT; additional IANA template mappings CC0',count=len(maps),rawSHA256=hashlib.sha256((src/'mime-db.json').read_bytes()).hexdigest(),generatedSHA256=digest)
dump('reference-manifest.json',manifest)
print([(x['id'],x['count']) for x in manifest['registries']],len(maps))

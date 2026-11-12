#!/usr/bin/env python3
"""Development-only public synthetic fixtures. Never run against personal keys."""
import pathlib, subprocess, tempfile, shutil
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'Tests/PKICoreTests/Fixtures';out.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='toolbox-public-pki-fixtures-') as td:
 d=pathlib.Path(td)
 def run(*args): subprocess.run(['/usr/bin/openssl',*args],cwd=d,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 (d/'root.cnf').write_text('[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=Toolbox PUBLIC TEST Root\n[ext]\nbasicConstraints=critical,CA:true,pathlen:2\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n')
 run('req','-new','-x509','-newkey','rsa:2048','-nodes','-sha256','-days','3650','-config','root.cnf','-keyout','root-key.pem','-out','root.pem')
 for name,ca,cn in [('intermediate','root','Toolbox PUBLIC TEST Intermediate'),('leaf','intermediate','localhost')]:
  run('req','-new','-newkey','rsa:2048','-nodes','-sha256','-subj','/CN='+cn,'-keyout',name+'-key.pem','-out',name+'.csr')
  ext='basicConstraints=critical,CA:true,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n' if name=='intermediate' else 'basicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\nauthorityInfoAccess=OCSP;URI:http://127.0.0.1:18992/ocsp,caIssuers;URI:http://127.0.0.1:18992/issuer\ncrlDistributionPoints=URI:http://127.0.0.1:18992/crl\n'
  (d/(name+'.ext')).write_text(ext+'subjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n')
  run('x509','-req','-in',name+'.csr','-CA',ca+'.pem','-CAkey',ca+'-key.pem','-CAcreateserial','-days','365','-sha256','-extfile',name+'.ext','-out',name+'.pem')
 run('pkcs12','-export','-inkey','leaf-key.pem','-in','leaf.pem','-certfile','intermediate.pem','-name','PUBLIC TEST','-passout','pass:fixture','-out','legacy.p12')
 run('pkcs12','-export','-inkey','leaf-key.pem','-in','leaf.pem','-passout','pass:','-out','empty-password.p12')
 for name in ['root.pem','intermediate.pem','leaf.pem','leaf.csr','leaf-key.pem','root-key.pem','legacy.p12','empty-password.p12']:shutil.copy2(d/name,out/name)
(out/'README.txt').write_text('PUBLIC SYNTHETIC TEST DATA. Keys have no confidentiality and must never be used outside tests. Generated with /usr/bin/openssl (LibreSSL 3.3.6) by scripts/generate-pki-fixtures.py. Network URLs point only to the test loopback listener. No production or employer material.\n')

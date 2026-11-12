#!/usr/bin/env python3
"""Public synthetic negative trust cases; development-only installed OpenSSL CLI."""
import pathlib,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1];fixtures=root/'Tests/PKICoreTests/Fixtures'
cli='/opt/homebrew/bin/openssl'
def run(*args):subprocess.run([cli,*map(str,args)],cwd=fixtures,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
with tempfile.TemporaryDirectory() as temporary:
 d=pathlib.Path(temporary);csr=d/'request.csr';ext=d/'extension.txt'
 run('req','-new','-key','leaf-key.pem','-subj','/CN=localhost','-out',csr)
 common='basicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature,keyEncipherment\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n'
 for name,extra,hash in [('cn-only','extendedKeyUsage=serverAuth\n','-sha256'),('critical','extendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost\n1.2.3.4=critical,DER:05:00\n','-sha256'),('sha1','extendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost\n','-sha1')]:
  ext.write_text(common+extra);run('x509','-req','-in',csr,'-CA','root.pem','-CAkey','root-key.pem','-set_serial','1234','-days','365',hash,'-extfile',ext,'-out',name+'.pem')
 for name,extra in [('pathlen-zero','basicConstraints=critical,CA:true,pathlen:0\n'),('name-constraints','basicConstraints=critical,CA:true,pathlen:2\nnameConstraints=critical,permitted;DNS:.example.com\n')]:
  ext.write_text(extra+'keyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n')
  run('req','-new','-key','root-key.pem','-subj','/CN=Toolbox PUBLIC TEST Root','-out',d/'root.csr')
  run('x509','-req','-in',d/'root.csr','-signkey','root-key.pem','-set_serial','4321','-days','3650','-sha256','-extfile',ext,'-out',name+'.pem')
print('PUBLIC_PKI_NEGATIVE_FIXTURES_GENERATED')

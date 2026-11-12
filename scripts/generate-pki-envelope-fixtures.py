#!/usr/bin/env python3
"""PUBLIC synthetic keys only. Rebuild legacy DER envelopes with system LibreSSL.
RSA reuses the existing public leaf-key fixture; EC keys are disposable generated test data.
"""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
fixtures = root / 'Tests/PKICoreTests/Fixtures'
def run(*args):
    subprocess.run(['/usr/bin/openssl', *map(str,args)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
run('rsa','-in',fixtures/'leaf-key.pem','-outform','DER','-out',fixtures/'legacy-rsa-private.der')
run('rsa','-in',fixtures/'leaf-key.pem','-RSAPublicKey_out','-outform','DER','-out',fixtures/'legacy-rsa-public.der')
with tempfile.TemporaryDirectory(prefix='dt-envelope-fixtures-') as temporary:
    for curve in ['prime256v1','secp384r1','secp521r1']:
        key=Path(temporary)/'public-synthetic-key.pem'
        run('ecparam','-name',curve,'-genkey','-noout','-out',key)
        run('ec','-in',key,'-outform','DER','-out',fixtures/f'legacy-{curve}.der')

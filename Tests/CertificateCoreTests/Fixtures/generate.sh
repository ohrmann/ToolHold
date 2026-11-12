#!/bin/sh
set -eu
TASK_CERT_DIR=$(mktemp -d)
trap 'rm -rf "$TASK_CERT_DIR"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TASK_CERT_DIR/key.pem" -out certificate.pem -days 30 -subj '/C=CZ/O=Toolbox Test/OU=One/OU=Two/CN=example.test' -addext 'subjectAltName=DNS:example.test,DNS:*.example.test,IP:127.0.0.1,IP:::1,email:test@example.test,URI:https://example.test' -addext 'keyUsage=critical,digitalSignature,keyEncipherment' -addext 'extendedKeyUsage=serverAuth,clientAuth' -addext 'basicConstraints=critical,CA:FALSE' -addext '1.2.3.4=critical,DER:04:02:01:02' 2>/dev/null
openssl x509 -in certificate.pem -outform DER -out certificate.der
openssl x509 -in certificate.pem -pubkey -noout > public.pem
openssl x509 -in certificate.pem -fingerprint -sha256 -noout > fingerprint.txt
openssl x509 -in certificate.pem -fingerprint -sha1 -noout >> fingerprint.txt
openssl pkey -pubin -in public.pem -outform DER | openssl dgst -sha256 >> fingerprint.txt

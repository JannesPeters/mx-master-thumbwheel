#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_DIR="$ROOT_DIR/build/local-signing"
SIGNING_IDENTITY="Thumbwheel Remapper Local Signing"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
PRIVATE_KEY="$SIGNING_DIR/private-key.pem"
CERTIFICATE="$SIGNING_DIR/certificate.pem"
IDENTITY_ARCHIVE="$SIGNING_DIR/identity.p12"
IMPORT_PASSWORD="thumbwheel-remapper-local-import"

cleanup() {
    rm -f "$PRIVATE_KEY" "$CERTIFICATE" "$IDENTITY_ARCHIVE"
    rmdir "$SIGNING_DIR" 2>/dev/null || true
}

trap cleanup EXIT

if security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" | grep -Fq "\"$SIGNING_IDENTITY\""; then
    echo "Code-signing identity already exists: $SIGNING_IDENTITY"
    exit 0
fi

mkdir -p "$SIGNING_DIR"

openssl req \
    -new \
    -newkey rsa:2048 \
    -x509 \
    -sha256 \
    -days 3650 \
    -nodes \
    -keyout "$PRIVATE_KEY" \
    -out "$CERTIFICATE" \
    -subj "/CN=$SIGNING_IDENTITY/O=Local Development" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,digitalSignature,keyCertSign" \
    -addext "extendedKeyUsage=critical,codeSigning"

openssl pkcs12 \
    -export \
    -out "$IDENTITY_ARCHIVE" \
    -inkey "$PRIVATE_KEY" \
    -in "$CERTIFICATE" \
    -name "$SIGNING_IDENTITY" \
    -passout "pass:$IMPORT_PASSWORD"

security import "$IDENTITY_ARCHIVE" \
    -k "$LOGIN_KEYCHAIN" \
    -f pkcs12 \
    -P "$IMPORT_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$LOGIN_KEYCHAIN" \
    "$CERTIFICATE"

echo "Created code-signing identity: $SIGNING_IDENTITY"

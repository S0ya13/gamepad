#!/usr/bin/env bash
# Creates a self-signed code-signing identity "Gamepad Local Signing" in the login keychain (once).
# Signing the Mac app with it keeps the same identity across rebuilds, so macOS keeps the
# key-press permission instead of asking again after every install.
set -euo pipefail
# /usr/bin/openssl (LibreSSL): its .p12 format is one the macOS keychain can import, unlike OpenSSL 3 defaults.

NAME="Gamepad Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "already there: $NAME"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" -extensions ext \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS="$(/usr/bin/openssl rand -hex 16)"  # only protects the temporary .p12 file
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -passout "pass:$PASS" -out "$TMP/id.p12"
# -T: codesign may use the key without a keychain prompt.
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign
echo "created: $NAME"

#!/bin/bash
# Creates (once, LOCALLY) a self-signed signing certificate named
# "Flubber Self-Signed" and imports it into the login keychain.
#
# Why? macOS anchors the Screen Recording permission (TCC) to the app's
# signature. With ad-hoc signing the fingerprint changes on every build → the
# permission resets. With this cert (stable fingerprint) the designated
# requirement does not change, so the permission PERSISTS across rebuilds. It
# only asks for an "Open Anyway" the first time (it is not notarized).
#
# After running it, build.sh detects the cert and signs with it automatically.
# In CI (without the cert) build.sh falls back to ad-hoc on its own.
set -e

CERT_NAME="Flubber Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "✅ Ya existe la identidad '$CERT_NAME':"
  security find-identity -p codesigning | grep "$CERT_NAME"
  exit 0
fi

echo "🔐 Generando certificado self-signed '$CERT_NAME'…"
CNF=$(mktemp); KEY=$(mktemp); CRT=$(mktemp); P12=$(mktemp)
trap 'rm -f "$CNF" "$KEY" "$CRT" "$P12"' EXIT

cat > "$CNF" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CERT_NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$KEY" -out "$CRT" -days 3650 -config "$CNF" >/dev/null 2>&1

openssl pkcs12 -export -inkey "$KEY" -in "$CRT" \
  -out "$P12" -passout pass:flubber -name "$CERT_NAME" >/dev/null 2>&1

# -T /usr/bin/codesign + -A => codesign can use the key without dialogs.
security import "$P12" -k "$KEYCHAIN" -P flubber -T /usr/bin/codesign -A

echo "✅ Listo. Identidad de firma:"
security find-identity -p codesigning | grep "$CERT_NAME"
echo ""
echo "Ahora corre ./build.sh — firmará con este cert automáticamente."

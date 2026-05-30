#!/bin/bash
# Crea (una vez, en LOCAL) un certificado de firma self-signed llamado
# "Flubber Self-Signed" y lo importa al llavero de login.
#
# ¿Para qué? macOS ancla el permiso de Grabación de pantalla (TCC) a la firma de
# la app. Con firma ad-hoc la huella cambia en cada build → el permiso se
# reinicia. Con este cert (huella estable) la designated requirement no cambia,
# así que el permiso PERSISTE entre rebuilds. Solo pide un "Abrir de todos modos"
# la primera vez (no está notarizada).
#
# Tras correrlo, build.sh detecta el cert y firma con él automáticamente.
# En CI (sin el cert) build.sh cae a ad-hoc solo.
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

# -T /usr/bin/codesign + -A => codesign puede usar la clave sin diálogos.
security import "$P12" -k "$KEYCHAIN" -P flubber -T /usr/bin/codesign -A

echo "✅ Listo. Identidad de firma:"
security find-identity -p codesigning | grep "$CERT_NAME"
echo ""
echo "Ahora corre ./build.sh — firmará con este cert automáticamente."

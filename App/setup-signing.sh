#!/bin/bash
# One-time: create a DEDICATED keychain holding a stable self-signed code-signing
# identity, so HeadmouseHelper's Input Monitoring grant PERSISTS across rebuilds
# (TCC keys off the stable designated requirement) AND the build can sign
# non-interactively over SSH.
#
# Safe to run over SSH. Re-runnable.
set -euo pipefail

KC="$HOME/Library/Keychains/headmousehelper.keychain-db"
KCPASS="headmousehelper"          # throwaway; only guards a local self-signed cert
IDENTITY="HeadmouseHelper Self-Signed"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
KEY="$WORK/key.pem"; CERT="$WORK/cert.pem"; P12="$WORK/id.p12"

echo "[1/5] Generating self-signed code-signing certificate..."
openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" -days 3650 -nodes \
    -subj "/CN=$IDENTITY" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
openssl pkcs12 -export -inkey "$KEY" -in "$CERT" -out "$P12" -passout "pass:$KCPASS" -name "$IDENTITY"

echo "[2/5] Creating dedicated keychain..."
security create-keychain -p "$KCPASS" "$KC" 2>/dev/null || echo "  (already exists)"

echo "[3/5] Unlocking + disabling auto-lock..."
security unlock-keychain -p "$KCPASS" "$KC"
security set-keychain-settings "$KC"

echo "[4/5] Importing identity (codesign-accessible)..."
security import "$P12" -k "$KC" -P "$KCPASS" -T /usr/bin/codesign 2>&1 | tail -1 || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KC" >/dev/null

echo "[5/5] Adding keychain to the search list..."
EXISTING="$(security list-keychains -d user | sed 's/[[:space:]]*"//; s/"$//')"
if ! echo "$EXISTING" | grep -q "headmousehelper.keychain"; then
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$KC" $EXISTING
fi

echo
echo "Done. Identity:"
security find-identity "$KC" | grep "$IDENTITY" || echo "  (not found — check import)"
echo
echo "Now rebuild:  ./App/build-app.sh"

#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-mustang}"
CN="${2:-WizeOS}"

KEY_DIR="keys/$TARGET"
TOOLS_DIR="tools"

APK_KEYS=(
  releasekey
  platform
  shared
  media
  networkstack
  bluetooth
  sdk_sandbox
  gmscompat_lib
  nfc
)

mkdir -p "$KEY_DIR" "$TOOLS_DIR"

echo "Creating GrapheneOS-style signing keys for target: $TARGET"
echo "Certificate CN: $CN"
echo

for KEY_NAME in "${APK_KEYS[@]}"; do
  echo "Generating $KEY_NAME..."

  openssl genrsa -out "$KEY_DIR/$KEY_NAME.pem" 4096

  openssl req \
    -new \
    -x509 \
    -sha256 \
    -key "$KEY_DIR/$KEY_NAME.pem" \
    -out "$KEY_DIR/$KEY_NAME.x509.pem" \
    -days 10000 \
    -subj "/CN=$CN/"

  openssl pkcs8 \
    -topk8 \
    -scrypt \
    -v2 aes-256-cbc \
    -inform PEM \
    -outform DER \
    -in "$KEY_DIR/$KEY_NAME.pem" \
    -out "$KEY_DIR/$KEY_NAME.pk8"

  rm -f "$KEY_DIR/$KEY_NAME.pem"
done

echo
echo "Generating AVB key..."
openssl genrsa 4096 | openssl pkcs8 -topk8 -scrypt -out "$KEY_DIR/avb.pem"

echo
echo "Downloading only avbtool.py, not GrapheneOS source..."
curl -L \
  "https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool.py?format=TEXT" \
  | base64 -d > "$TOOLS_DIR/avbtool.py"

chmod +x "$TOOLS_DIR/avbtool.py"

echo
echo "Generating avb_pkmd.bin..."
python3 "$TOOLS_DIR/avbtool.py" extract_public_key \
  --key "$KEY_DIR/avb.pem" \
  --output "$KEY_DIR/avb_pkmd.bin"

echo
echo "Generating factory image SSH signing key..."
ssh-keygen -t ed25519 -f "$KEY_DIR/id_ed25519" -C "$CN $TARGET factory image signing"

echo
echo "Done. Keys created in: $KEY_DIR"


#./create-grapheneos-keys.sh mustang WizeOS
#!/usr/bin/env bash
# 서명 키스토어 2개(upload, sideload)를 만들고 GPG 로 암호화해 android/keystores/ 에 둔다.
#
# 사용법 (패스프레이즈는 GitHub Secrets 에 넣을 값과 같아야 함):
#   ANDROID_UPLOAD_PASSPHRASE='...' SIDELOAD_PASSPHRASE='...' tool/make_keystores.sh
#
# 필요: keytool (JDK), gpg
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ANDROID_UPLOAD_PASSPHRASE:?ANDROID_UPLOAD_PASSPHRASE 필요}"
: "${SIDELOAD_PASSPHRASE:?SIDELOAD_PASSPHRASE 필요}"

out=android/keystores
backup="${KEYSTORE_BACKUP_DIR:-$HOME/mint-and-friends-keys}"
mkdir -p "$out" "$backup"

make_one() {
  local name=$1 pass=$2
  local jks="$backup/$name.jks"
  if [ -f "$jks" ]; then
    echo "이미 있음: $jks (기존 키를 다시 암호화만 함)"
  else
    keytool -genkeypair -v -keystore "$jks" -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
      -alias "$name" -storepass "$pass" -keypass "$pass" \
      -dname "CN=Mint and Friends ($name), O=graviton94, C=KR"
  fi
  gpg --batch --yes --pinentry-mode loopback --passphrase "$pass" --symmetric --cipher-algo AES256 \
    -o "$out/$name.jks.gpg" "$jks"
  echo "생성: $out/$name.jks.gpg  (원본: $jks — 안전한 곳에 백업하세요)"
}

make_one upload "$ANDROID_UPLOAD_PASSPHRASE"
make_one sideload "$SIDELOAD_PASSPHRASE"

echo
echo "업로드 키 인증서 SHA-1 / SHA-256 (Firebase 콘솔 Android 앱 · 카카오 키 해시 등록에 사용):"
keytool -list -v -keystore "$backup/upload.jks" -alias upload -storepass "$ANDROID_UPLOAD_PASSPHRASE" | grep -E "SHA1|SHA256"
echo "사이드로드 키:"
keytool -list -v -keystore "$backup/sideload.jks" -alias sideload -storepass "$SIDELOAD_PASSPHRASE" | grep -E "SHA1|SHA256"

#!/usr/bin/env bash
# 에뮬레이터에 APK 를 설치하고 실행한 뒤 30초 동안 살아 있는지 본다.
# 사용: tool/smoke_launch.sh <apk> <패키지>
set -u
APK="$1"; PKG="$2"
mkdir -p smoke
adb install -r "$APK" || exit 1
adb logcat -c
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
alive=0
for i in $(seq 1 30); do
  sleep 1
  if adb shell pidof "$PKG" >/dev/null 2>&1; then alive=$((alive + 1)); else alive=0; fi
done
adb logcat -d > smoke/logcat.txt
adb logcat -d -b crash > smoke/crash_buffer.txt || true
adb exec-out screencap -p > smoke/screen.png || true
{
  echo "## Launch smoke test"
  if adb shell pidof "$PKG" >/dev/null 2>&1; then echo "- app is running after 30s"; else echo "- **app is not running**"; fi
  echo '```'
  grep -E "FATAL EXCEPTION|AndroidRuntime|Caused by|E/flutter|Process: $PKG|ANR in" -A12 smoke/logcat.txt | head -120
  cat smoke/crash_buffer.txt | head -80
  echo '```'
} > smoke/crash.txt
cat smoke/crash.txt
adb shell pidof "$PKG" >/dev/null 2>&1

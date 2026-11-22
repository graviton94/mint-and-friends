#!/usr/bin/env bash
# 진단 빌드(SHARE_PROBE)를 설치 · 실행하고 공유 단계 로그를 모은다.
set -u
APK="$1"; PKG="$2"
mkdir -p probe
adb install -r "$APK" || exit 1
adb logcat -c
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 40
adb exec-out screencap -p > probe/screen.png || true
adb logcat -d > probe/logcat.txt
{
  echo "## Share probe"
  echo '```'
  grep -E "SHAREPROBE" probe/logcat.txt | sed 's/.*SHAREPROBE/SHAREPROBE/' | head -40
  echo '--- errors around share ---'
  grep -iE "share_plus|ShareFileProvider|FileProvider|ActivityNotFound|SecurityException|IllegalArgument|E/flutter|FATAL" -A4 probe/logcat.txt | head -80
  echo '```'
} > probe/summary.txt
cat probe/summary.txt

#!/usr/bin/env bash
# 진단 빌드(NOTIFY_PROBE)를 설치 · 실행하고 알림 단계 로그 · 예약 상태를 모은다.
set -u
APK="$1"; PKG="$2"
mkdir -p probe
adb install -r "$APK" || exit 1
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS || true
adb logcat -c
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 30
adb exec-out screencap -p > probe/screen1.png || true
adb shell dumpsys alarm | grep -A3 "$PKG" > probe/alarm.txt || true
adb shell dumpsys notification --noredact | grep -B2 -A12 "$PKG" > probe/notif_30s.txt || true
# 앱을 내리고 프로세스를 없앤 뒤(백그라운드 정리), 예약 알림이 앱 없이도 뜨는지 본다
adb shell input keyevent KEYCODE_HOME
sleep 5
adb shell am kill "$PKG" || true
sleep 150
adb shell dumpsys notification --noredact | grep -B2 -A12 "$PKG" > probe/notif_after_kill.txt || true
adb shell dumpsys alarm | grep -A3 "$PKG" > probe/alarm_after_home.txt || true
adb logcat -d > probe/logcat.txt
{
  echo "## Notify probe"
  echo '```'
  grep -E "NOTIFYPROBE" probe/logcat.txt | sed 's/.*NOTIFYPROBE/NOTIFYPROBE/' | head -40
  echo '--- posted notifications at 30s / after kill+150s (titles) ---'
  grep -E "android.title|probe now|probe scheduled" probe/notif_30s.txt | head -10
  echo '...'
  grep -E "android.title|probe now|probe scheduled" probe/notif_after_kill.txt | head -10
  echo '--- process alive? ---'; adb shell pidof "$PKG" || echo 'not running'
  echo '--- alarms (after home) ---'
  grep -cE "$PKG" probe/alarm_after_home.txt
  head -20 probe/alarm_after_home.txt
  echo '--- errors ---'
  grep -iE "flutterlocalnotifications|ScheduledNotification|E/flutter|FATAL|Missing type parameter" -A3 probe/logcat.txt | head -60
  echo '```'
} > probe/summary.txt
cat probe/summary.txt

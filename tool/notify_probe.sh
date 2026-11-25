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
adb shell dumpsys notification --noredact > probe/notif_all_30s.txt || true
grep -A25 "pkg=$PKG" probe/notif_all_30s.txt > probe/notif_30s.txt || true
# 앱을 내리고 프로세스를 없앤 뒤(백그라운드 정리), 예약 알림이 앱 없이도 뜨는지 본다
adb shell input keyevent KEYCODE_HOME
sleep 5
adb shell am kill "$PKG" || true
sleep 150
adb shell dumpsys notification --noredact > probe/notif_all_kill.txt || true
grep -A25 "pkg=$PKG" probe/notif_all_kill.txt > probe/notif_after_kill.txt || true
adb shell dumpsys alarm | grep -A3 "$PKG" > probe/alarm_after_home.txt || true
# 앱을 다시 열어(예약 정리가 도는 때) 이미 뜬 알림이 알림창에 남는지 본다 (D-070)
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 15
adb shell dumpsys notification --noredact > probe/notif_all_reopen.txt || true
grep -A25 "pkg=$PKG" probe/notif_all_reopen.txt > probe/notif_after_reopen.txt || true
adb shell cmd notification list 2>/dev/null | grep "$PKG" > probe/notif_list_reopen.txt || true
adb logcat -d > probe/logcat.txt
{
  echo "## Notify probe"
  echo '```'
  grep -E "NOTIFYPROBE" probe/logcat.txt | sed 's/.*NOTIFYPROBE/NOTIFYPROBE/' | head -40
  echo '--- posted notifications at 30s / after kill+150s (records) ---'
  grep -cE "NotificationRecord" probe/notif_30s.txt; grep -oE "(probe now|probe scheduled|tickerText=[^,]*)" probe/notif_30s.txt | head -5
  grep -cE "NotificationRecord" probe/notif_after_kill.txt; grep -oE "(probe now|probe scheduled|tickerText=[^,]*)" probe/notif_after_kill.txt | head -5
  grep -E "android.title|probe now|probe scheduled" probe/notif_30s.txt | head -10
  echo '...'
  grep -E "android.title|probe now|probe scheduled" probe/notif_after_kill.txt | head -10
  echo '--- after reopen (should still list probe scheduled) ---'
  grep -E "android.title|probe scheduled" probe/notif_after_reopen.txt | head -10
  cat probe/notif_list_reopen.txt | head -10
  echo '--- channel garden_alerts ---'
  grep -A6 "garden_alerts" probe/notif_all_reopen.txt | grep -E "mImportance|importance|mLockscreenVisibility|lockscreen" | head -4
  echo '--- process alive? ---'; adb shell pidof "$PKG" || echo 'not running'
  echo '--- alarms (after home) ---'
  grep -cE "$PKG" probe/alarm_after_home.txt
  head -20 probe/alarm_after_home.txt
  echo '--- Firebase Analytics (FA) ---'
  grep -E " FA  | FA-SVC|google_app_id|Analytics" probe/logcat.txt | head -15
  echo '--- errors ---'
  grep -iE "flutterlocalnotifications|ScheduledNotification|E/flutter|FATAL|Missing type parameter" -A3 probe/logcat.txt | head -60
  echo '```'
} > probe/summary.txt
cat probe/summary.txt

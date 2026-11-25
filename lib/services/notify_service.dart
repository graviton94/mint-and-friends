import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../game/config.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';

/// 게임 밖 알림 (기기 안에서 예약, 서버 없음).
/// 앱을 내릴 때 예약하고, 다시 켜면 모두 지운다. 09~21시에만 울린다 (규칙은 [arrange]).
/// - 아침 알림 (매일 09시, 들어오지 않으면 사흘까지): 출석 선물 · 친구가 보고 싶대요 · 친구들이 기다려요
/// - 소식 알림 (그 시각에): 에너지 가득 · 수입 주머니 가득 · 친구 선물 · 안 읽은 편지
class NotifyService extends ChangeNotifier {
  NotifyService._();
  static final NotifyService instance = NotifyService._();

  static const _key = 'notify_on';
  static const _askedKey = 'notify_asked';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _on = true;
  bool get on => _on;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<void> init() async {
    if (!_supported) return;
    try {
      tzdata.initializeTimeZones();
      final p = await SharedPreferences.getInstance();
      _on = p.getBool(_key) ?? true;
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_notify'),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('notify init failed: $e');
    }
  }

  /// 안드로이드 13+ 알림 권한: 처음 한 번만 묻는다.
  Future<void> askOnce() async {
    if (!_ready) return;
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_askedKey) ?? false) return;
    await p.setBool(_askedKey, true);
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  Future<void> setOn(bool v) async {
    _on = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_key, v);
    if (!v) await cancel();
    if (v) await askOnce();
  }

  /// 알림 채널: 화면 위로 잠깐 내려오는 중요도(높음). 채널 중요도는 만든 뒤 바꿀 수 없어
  /// 예전 'garden'(기본 중요도, 알림창에 조용히 쌓여 잘 안 보였음) 대신 새 채널을 쓴다 (1.0.9).
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'garden_alerts',
      'Garden',
      channelDescription: 'Energy, gifts and friends',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_notify',
      color: Color(0xFF5FA05A),
      // 잠금화면에도 내용까지 보이게 (기본은 '비공개'라 기기에 따라 아이콘만 남는다, D-069)
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.reminder,
      ticker: 'Mint & Friends',
    ),
  );

  /// 설정의 '알림 테스트': 지금 바로 하나 띄운다. 기기에서 알림이 막혀 있으면 false.
  Future<bool> sendTest(String title, String body, {String? lockBody}) async {
    if (!_ready) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      var on = await android?.areNotificationsEnabled() ?? true;
      if (!on) on = await android?.requestNotificationsPermission() ?? false;
      if (!on) return false;
      await _plugin.show(
        id: 99,
        title: title,
        body: body,
        notificationDetails: _details,
      );
      // 잠금화면 확인용: 10초 뒤 한 번 더 (그사이 화면을 끄면 잠금화면에서 보인다)
      Timer(const Duration(seconds: 10), () {
        _plugin
            .show(
              id: 98,
              title: title,
              body: lockBody ?? body,
              notificationDetails: _details,
            )
            .catchError((Object _) {});
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 예약 세대: 예약 도중 앱이 다시 켜져 cancel 되면 남은 예약을 버린다.
  int _gen = 0;

  Future<void> cancel() async {
    _gen++;
    await _cancelAll();
  }

  Future<void> _cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// 알림이 울리는 시간: 09시부터 21시 전까지.
  static const int dayStart = 9;
  static const int dayEnd = 21;

  /// 알림 사이 최소 간격 · 하루에 울리는 소식 알림(아침 알림 빼고) 최대 개수.
  static const minGap = Duration(minutes: 90);
  static const maxEventsPerDay = 3;

  /// 아침 알림을 며칠치 예약하는지 (하루 · 이틀 · 사흘 동안 안 들어오면).
  static const morningDays = 3;

  /// 첫 아침 알림 날: 오늘 09시가 3시간 넘게 남았으면 오늘(새벽에 잠깐 들어온 경우), 아니면 내일.
  static DateTime firstMorning(DateTime now) {
    final today = DateTime(now.year, now.month, now.day, dayStart);
    if (!now.add(const Duration(hours: 3)).isAfter(today)) return today;
    final d = now.add(const Duration(days: 1));
    return DateTime(d.year, d.month, d.day, dayStart);
  }

  static bool inDay(DateTime t) => t.hour >= dayStart && t.hour < dayEnd;

  /// 알림 일정 정하기 (순수 함수, 테스트용).
  /// - 아침 알림: 접속이 없으면 매일 09시(+0~14분)에 하나 (morning 의 순서대로 하루씩).
  /// - 소식 알림(에너지 · 수입 · 선물 · 편지): 그 시각이 09~21시일 때만. 밤에 생긴 것은 미루지 않고 버린다
  ///   (아침에 몰아서 울리지 않게, 다음 날은 아침 알림부터 다시).
  /// - 어떤 두 알림도 90분 안에 붙지 않고, 소식 알림은 하루 3개까지.
  static List<(DateTime, String, String)> arrange(
    DateTime now,
    List<(DateTime, String, String)> events,
    List<(String, String)> morning, [
    Random? rng,
  ]) {
    final kept = <(DateTime, String, String)>[];
    final m0 = firstMorning(now);
    for (var i = 0; i < morning.length; i++) {
      final d = m0.add(Duration(days: i));
      final t = DateTime(
        d.year,
        d.month,
        d.day,
        dayStart,
        rng?.nextInt(15) ?? 0,
      );
      kept.add((t, morning[i].$1, morning[i].$2));
    }
    final perDay = <int, int>{};
    int day(DateTime t) => t.year * 10000 + t.month * 100 + t.day;
    final sorted = [...events]..sort((x, y) => x.$1.compareTo(y.$1));
    for (final e in sorted) {
      final t = e.$1;
      if (t.isBefore(now.add(const Duration(minutes: 5)))) continue;
      if (!inDay(t)) continue; // 밤 · 새벽 소식은 버린다
      if ((perDay[day(t)] ?? 0) >= maxEventsPerDay) continue;
      if (kept.any((k) => k.$1.difference(t).abs() < minGap)) continue;
      kept.add(e);
      perDay[day(t)] = (perDay[day(t)] ?? 0) + 1;
    }
    kept.sort((x, y) => x.$1.compareTo(y.$1));
    return kept;
  }

  /// 앱을 내릴 때: 지금 상태로 다음 알림들을 예약한다.
  Future<void> schedule(GameState g) async {
    if (!_ready) return;
    // 세대는 기다리기 전에 잡는다: 지우는 사이 앱이 다시 켜지면(cancel) 예약하지 않게
    final gen = ++_gen;
    await _cancelAll();
    if (gen != _gen || !_on) return;
    final now = DateTime.now();
    final rng = Random();
    final events = <(DateTime, String, String)>[];
    String friend() {
      final fs = g.friends.toList();
      return fs.isEmpty
          ? friendName('bori')
          : friendName(fs[rng.nextInt(fs.length)]);
    }

    // 1) 에너지 가득
    if (g.energy < g.energyCap) {
      final left =
          g.energyNextIn +
          Duration(
            seconds: ((g.energyCap - g.energy - 1) * g.energyRegenSeconds)
                .round(),
          );
      events.add((
        now.add(left),
        tr('notify.energy.title'),
        tr('notify.energy.body', {'n': g.energyCap}),
      ));
    }
    // 2) 정원 수입 주머니 가득 (오프라인 한도)
    if (g.baseIncomePerSec > 0) {
      events.add((
        now.add(g.offlineCap),
        tr('notify.offline.title'),
        tr('notify.offline.body'),
      ));
    }
    // 3) 친구 선물
    final gift = g.nextFriendGiftAt;
    if (gift != null && g.friends.length >= 2 && gift.isAfter(now)) {
      events.add((
        gift,
        tr('notify.gift.title'),
        tr('notify.gift.body', {'name': friend()}),
      ));
    }
    // 4) 안 읽은 편지 (3시간 뒤): 친구 편지면 그 친구 이름으로, 여럿이면 개수로
    final unread = g.mail.where((m) => !m.claimed).toList();
    if (unread.isNotEmpty) {
      final fromFriend = unread
          .where((m) => Friends.all.any((f) => f.id == m.from))
          .firstOrNull;
      final v = rng.nextInt(2);
      events.add((
        now.add(const Duration(hours: 3)),
        unread.length > 1
            ? tr('notify.mailMany.title', {'n': unread.length})
            : fromFriend != null
            ? tr('notify.mailFrom.title', {'name': friendName(fromFriend.from)})
            : tr('notify.mail.title'),
        tr('notify.mail.body.$v'),
      ));
    }
    // 아침 알림: 첫날은 출석 선물(Lv3+) 또는 아침 인사, 이튿날은 친구가 보고 싶대요, 사흗날은 친구들이 기다려요
    final n1 = friend();
    final morning = <(String, String)>[
      g.level >= 3
          ? (tr('notify.checkIn.title'), tr('notify.checkIn.body'))
          : (tr('notify.morning.title'), tr('notify.morning.body')),
      (
        tr('notify.miss.title', {'name': n1}),
        tr('notify.miss.body', {'name': n1}),
      ),
      (tr('notify.miss3.title'), tr('notify.miss3.body')),
    ].take(morningDays).toList();

    final kept = arrange(now, events, morning, rng);
    for (var i = 0; i < kept.length; i++) {
      if (gen != _gen) return; // 그사이 앱이 다시 켜졌다
      final (t, title, body) = kept[i];
      try {
        await _plugin.zonedSchedule(
          id: 100 + i,
          scheduledDate: tz.TZDateTime.from(t.toUtc(), tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: title,
          body: body,
        );
      } catch (e) {
        debugPrint('notify schedule failed: $e');
      }
    }
  }

  /// 진단 (빌드 옵션 NOTIFY_PROBE, notify-probe.yml): 단계별 결과를 'NOTIFYPROBE' 로그로.
  Future<void> probe(GameState g) async {
    void log(String m) => debugPrint('NOTIFYPROBE $m');
    log('ready=$_ready on=$_on');
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      log('enabled=${await android?.areNotificationsEnabled()}');
      log('exactAllowed=${await android?.canScheduleExactNotifications()}');
    } catch (e) {
      log('status error $e');
    }
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'garden',
        'Garden',
        channelDescription: 'Energy, gifts and friends',
        icon: 'ic_stat_notify',
      ),
    );
    try {
      await _plugin.show(
        id: 900,
        title: 'probe now',
        body: 'immediate',
        notificationDetails: details,
      );
      log('show ok');
    } catch (e) {
      log('show error $e');
    }
    try {
      await schedule(g);
      final pending = await _plugin.pendingNotificationRequests();
      log(
        'after schedule pending=${pending.length} ids=${pending.map((p) => p.id).toList()}',
      );
    } catch (e) {
      log('schedule error $e');
    }
    try {
      await _plugin.zonedSchedule(
        id: 901,
        scheduledDate: tz.TZDateTime.now(tz.UTC)
            .add(const Duration(seconds: 90)),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'probe scheduled',
        body: '90s',
      );
      log('zonedSchedule ok');
    } catch (e) {
      log('zonedSchedule error $e');
    }
  }
}

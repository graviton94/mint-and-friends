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
/// 앱을 내릴 때 예약하고, 다시 켜면 모두 지운다. 08~21시에만 울린다 (그 밖이면 다음 08시로).
/// - 에너지가 가득 찼어요 · 정원 수입 주머니가 가득 찼어요
/// - 친구가 선물을 두고 갔어요 · 오늘의 출석 선물
/// - 친구가 보고 싶대요 (하루 · 사흘 동안 안 들어오면)
class NotifyService extends ChangeNotifier {
  NotifyService._();
  static final NotifyService instance = NotifyService._();

  static const _key = 'notify_on';
  static const _askedKey = 'notify_asked';
  static const int quietStart = 21; // 이 시각부터
  static const int quietEnd = 8; // 이 시각까지는 울리지 않는다

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
    ),
  );

  /// 설정의 '알림 테스트': 지금 바로 하나 띄운다. 기기에서 알림이 막혀 있으면 false.
  Future<bool> sendTest(String title, String body) async {
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

  /// 조용한 시간(21시~다음 날 08시)이면 다음 08시(+0~20분)로 미룬다.
  static DateTime quiet(DateTime t, [Random? rng]) {
    final jitter = Duration(minutes: rng?.nextInt(20) ?? 0);
    if (t.hour >= quietStart) {
      final d = t.add(const Duration(days: 1));
      return DateTime(d.year, d.month, d.day, quietEnd).add(jitter);
    }
    if (t.hour < quietEnd) {
      return DateTime(t.year, t.month, t.day, quietEnd).add(jitter);
    }
    return t;
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
    final plans = <(DateTime, String, String)>[];
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
      plans.add((
        now.add(left),
        tr('notify.energy.title'),
        tr('notify.energy.body', {'n': g.energyCap}),
      ));
    }
    // 2) 정원 수입 주머니 가득 (오프라인 한도)
    if (g.baseIncomePerSec > 0) {
      plans.add((
        now.add(g.offlineCap),
        tr('notify.offline.title'),
        tr('notify.offline.body'),
      ));
    }
    // 3) 친구 선물
    final gift = g.nextFriendGiftAt;
    if (gift != null && g.friends.length >= 2 && gift.isAfter(now)) {
      plans.add((
        gift,
        tr('notify.gift.title'),
        tr('notify.gift.body', {'name': friend()}),
      ));
    }
    // 3-1) 안 읽은 편지 (3시간 뒤): 친구 편지면 그 친구 이름으로, 여럿이면 개수로
    final unread = g.mail.where((m) => !m.claimed).toList();
    if (unread.isNotEmpty) {
      final fromFriend = unread
          .where((m) => Friends.all.any((f) => f.id == m.from))
          .firstOrNull;
      final v = rng.nextInt(2);
      plans.add((
        now.add(const Duration(hours: 3)),
        unread.length > 1
            ? tr('notify.mailMany.title', {'n': unread.length})
            : fromFriend != null
            ? tr('notify.mailFrom.title', {'name': friendName(fromFriend.from)})
            : tr('notify.mail.title'),
        tr('notify.mail.body.$v'),
      ));
    }
    // 4) 내일 출석 선물 (09시 무렵)
    if (g.level >= 3) {
      final d = now.add(const Duration(days: 1));
      plans.add((
        DateTime(d.year, d.month, d.day, 9, rng.nextInt(30)),
        tr('notify.checkIn.title'),
        tr('notify.checkIn.body'),
      ));
    }
    // 5) 돌아오세요 (하루 · 사흘)
    final n1 = friend();
    plans.add((
      now.add(const Duration(hours: 24)),
      tr('notify.miss.title', {'name': n1}),
      tr('notify.miss.body', {'name': n1}),
    ));
    plans.add((
      now.add(const Duration(days: 3)),
      tr('notify.miss3.title'),
      tr('notify.miss3.body'),
    ));

    // 조용한 시간 피하기 · 30분 안에 겹치는 알림은 하나만
    final fixed = [for (final (t, a, b) in plans) (quiet(t, rng), a, b)]
      ..sort((x, y) => x.$1.compareTo(y.$1));
    final kept = <(DateTime, String, String)>[];
    for (final p in fixed) {
      if (p.$1.isBefore(now.add(const Duration(minutes: 5)))) continue;
      if (kept.isNotEmpty &&
          p.$1.difference(kept.last.$1) < const Duration(minutes: 30)) {
        continue;
      }
      kept.add(p);
    }
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

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';

/// 비정상 종료 · 오류 수집 (Firebase Crashlytics). 비공개 테스트부터 켠다.
/// Firebase 가 준비된 뒤 한 번 [install]. 디버그 · 웹 · 테스트에서는 아무것도 안 한다.
/// 개인 정보는 보내지 않는다 (계정 id · 이름 없음, 앱 버전 · 레벨 같은 게임 상태만).
class CrashService {
  CrashService._();
  static bool _on = false;
  static bool get on => _on;

  static Future<void> install({required String version}) async {
    if (_on || kIsWeb || kDebugMode || Firebase.apps.isEmpty) return;
    try {
      final c = FirebaseCrashlytics.instance;
      await c.setCrashlyticsCollectionEnabled(true);
      await c.setCustomKey('app_version', version);
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        prev?.call(d);
        c.recordFlutterError(d);
      };
      PlatformDispatcher.instance.onError = (e, st) {
        c.recordError(e, st, fatal: true);
        return true;
      };
      _on = true;
    } catch (e) {
      debugPrint('crashlytics: $e');
    }
  }

  /// 게임 상태 꼬리표 (오류가 날 때 함께 보인다).
  static void state({int? level, int? area}) {
    if (!_on) return;
    final c = FirebaseCrashlytics.instance;
    if (level != null) c.setCustomKey('level', level);
    if (area != null) c.setCustomKey('area', area);
  }

  /// 잡았지만 알아야 하는 오류 (저장 실패 등).
  static void report(Object e, StackTrace? st, {String? why}) {
    if (!_on) return;
    FirebaseCrashlytics.instance.recordError(e, st, reason: why);
  }

  static void log(String msg) {
    if (_on) FirebaseCrashlytics.instance.log(msg);
  }

  // ---------------------------------------------------------------- 사용자가 겪은 문제 (로그인 실패 등)

  static const _pendingKey = 'pending_issues';

  /// 사용자가 겪은 문제를 우리에게 남긴다: Crashlytics(오류 아님 · 기록) + Analytics 이벤트.
  /// Firebase 가 아직 없으면(로그인 자체가 막힌 경우) 기기에 모아 두었다가 다음에 연결되면 보낸다.
  static Future<void> issue(String kind, Map<String, String> info) async {
    final line =
        '$kind ${info.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    debugPrint('issue: $line');
    if (_on && Firebase.apps.isNotEmpty) {
      _send(kind, info);
      return;
    }
    try {
      final p = await SharedPreferences.getInstance();
      final list = p.getStringList(_pendingKey) ?? [];
      list.add('${DateTime.now().toUtc().toIso8601String()} $line');
      await p.setStringList(
        _pendingKey,
        list.length > 20 ? list.sublist(list.length - 20) : list,
      );
    } catch (_) {}
  }

  static void _send(String kind, Map<String, String> info) {
    try {
      final c = FirebaseCrashlytics.instance;
      c.recordError(
        Exception('issue $kind'),
        StackTrace.current,
        reason: kind,
        information: [for (final e in info.entries) '${e.key}: ${e.value}'],
      );
    } catch (_) {}
    Analytics.instance.log('issue', {
      'kind': kind,
      for (final e in info.entries.take(8))
        e.key: e.value.length > 95 ? e.value.substring(0, 95) : e.value,
    });
  }

  /// 연결되지 않았을 때 모아 둔 문제를 보낸다 (Firebase 준비 뒤 한 번).
  static Future<void> flushPending() async {
    if (!_on || Firebase.apps.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final list = p.getStringList(_pendingKey) ?? [];
      if (list.isEmpty) return;
      await p.remove(_pendingKey);
      for (final l in list) {
        _send('pending', {'line': l.length > 300 ? l.substring(0, 300) : l});
      }
    } catch (_) {}
  }
}

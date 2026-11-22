
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

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
}

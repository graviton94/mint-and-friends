import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/tuning.dart';
import 'analytics_service.dart';

/// 업데이트 진행 상태.
enum UpdatePhase { none, available, downloading, downloaded, failed }

/// Play 인앱 업데이트 (D-049): 새 버전 알림 → 게임 안에서 받기(진행률) → 다 받으면 다시 열기.
/// 원격 설정 min_version_code 보다 낮은 앱은 필수 업데이트(전체 화면).
/// Play 에서 설치한 앱에서만 동작한다 (사이드로드 · 웹 · 테스트에서는 조용히 아무것도 안 함).
class UpdateService extends ChangeNotifier {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _ch = MethodChannel('mint/update');
  static const _progress = EventChannel('mint/update/progress');
  static const _kSnooze = 'update_snooze';

  // Play 설치 상태 코드 (com.google.android.play.core.install.model.InstallStatus)
  static const int _downloading = 2, _downloaded = 11, _failed = 5;
  static const int _canceled = 6, _flowCanceled = -2;

  UpdatePhase phase = UpdatePhase.none;
  int availableVersion = 0;
  int bytes = 0, total = 0;
  StreamSubscription<dynamic>? _sub;

  double get progress => total > 0 ? (bytes / total).clamp(0.0, 1.0) : 0;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _listen() {
    if (_sub != null || !_supported) return;
    _sub = _progress.receiveBroadcastStream().listen((e) {
      if (e is! Map) return;
      final st = (e['status'] as num?)?.toInt() ?? 0;
      bytes = (e['bytes'] as num?)?.toInt() ?? bytes;
      total = (e['total'] as num?)?.toInt() ?? total;
      if (st == _downloading) {
        phase = UpdatePhase.downloading;
      } else if (st == _downloaded) {
        phase = UpdatePhase.downloaded;
        Analytics.instance.log('update_downloaded', {'to': availableVersion});
      } else if (st == _failed) {
        phase = UpdatePhase.failed;
      } else if (st == _canceled || st == _flowCanceled) {
        if (phase != UpdatePhase.downloaded) phase = UpdatePhase.available;
      }
      notifyListeners();
    }, onError: (_) {});
  }

  /// 새 버전이 있는지 본다. 필수 업데이트면 바로 전체 화면 업데이트를 시작하고 true.
  /// 돌려주는 값: 알림 창을 띄워야 하면 true.
  Future<bool> check({required int myVersionCode}) async {
    if (!_supported) return false;
    _listen();
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('check');
      if (r == null) return false;
      final status = (r['status'] as num?)?.toInt() ?? 0;
      if (status == _downloaded) {
        phase = UpdatePhase.downloaded;
        notifyListeners();
        return false;
      }
      if (r['available'] != true) return false;
      availableVersion = (r['versionCode'] as num?)?.toInt() ?? 0;
      phase = UpdatePhase.available;
      notifyListeners();
      // 필수 업데이트 (원격 설정)
      if (Tuning.minVersionCode > myVersionCode && r['immediate'] == true) {
        Analytics.instance.log('update_forced', {'to': availableVersion});
        await _ch.invokeMethod('start', {'immediate': true});
        return false;
      }
      if (r['flexible'] != true) return false;
      // '나중에' 를 누른 버전은 하루 동안 다시 묻지 않는다
      final prefs = await SharedPreferences.getInstance();
      final snooze = prefs.getString(_kSnooze) ?? '';
      final today = DateTime.now().toIso8601String().substring(0, 10);
      return snooze != '$availableVersion@$today';
    } catch (e) {
      debugPrint('update check: $e');
      return false;
    }
  }

  /// '업데이트' → 게임하는 동안 뒤에서 받는다.
  Future<void> start() async {
    _listen();
    try {
      Analytics.instance.log('update_start', {'to': availableVersion});
      final ok = await _ch.invokeMethod<bool>('start', {'immediate': false});
      if (ok == true) {
        phase = UpdatePhase.downloading;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('update start: $e');
    }
  }

  Future<void> snooze() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await prefs.setString(_kSnooze, '$availableVersion@$today');
    Analytics.instance.log('update_later', {'to': availableVersion});
  }

  /// 다 받은 업데이트 적용 (앱이 다시 열린다).
  Future<void> complete() async {
    try {
      Analytics.instance.log('update_restart', {'to': availableVersion});
      await _ch.invokeMethod('complete');
    } catch (e) {
      debugPrint('update complete: $e');
    }
  }
}

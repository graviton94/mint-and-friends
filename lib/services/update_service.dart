import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/tuning.dart';
import 'analytics_service.dart';

/// 업데이트 진행 상태.
enum UpdatePhase { none, available, downloading, downloaded, failed }

/// 알림 창을 어떻게 띄울지: 없음 · 게임 안에서 받기 · 스토어 열기 (Play 가 늦게 알려 줄 때).
enum UpdateAsk { none, inApp, store }

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

  DateTime? _lastCheck;

  /// 앱으로 돌아올 때 다시 확인해도 되나 (30분에 한 번).
  bool get checkDue =>
      _lastCheck == null ||
      DateTime.now().difference(_lastCheck!) > const Duration(minutes: 30);

  /// 새 버전이 있는지 본다. 필수 업데이트면 바로 전체 화면 업데이트를 시작한다.
  /// Play 가 아직 새 버전을 모르면(배포 직후 하루 정도 늦는 일이 흔하다) 원격 설정
  /// latest_version_code 로 판단해 스토어 페이지를 열게 한다.
  Future<UpdateAsk> check({required int myVersionCode}) async {
    if (!_supported) return UpdateAsk.none;
    _lastCheck = DateTime.now();
    _listen();
    Map<String, dynamic>? r;
    String err = '';
    try {
      r = await _ch.invokeMapMethod<String, dynamic>('check');
    } catch (e) {
      err = '$e';
      debugPrint('update check: $e');
    }
    final playHas = r != null && r['available'] == true;
    Analytics.instance.log('update_check', {
      'mine': myVersionCode,
      'play': playHas ? ((r['versionCode'] as num?)?.toInt() ?? 0) : 0,
      'latest': Tuning.latestVersionCode,
      if (err.isNotEmpty) 'err': err.length > 90 ? err.substring(0, 90) : err,
    });
    if (r != null && ((r['status'] as num?)?.toInt() ?? 0) == _downloaded) {
      phase = UpdatePhase.downloaded;
      notifyListeners();
      return UpdateAsk.none;
    }
    if (playHas) {
      availableVersion = (r['versionCode'] as num?)?.toInt() ?? 0;
      phase = UpdatePhase.available;
      notifyListeners();
      // 필수 업데이트 (원격 설정)
      if (Tuning.minVersionCode > myVersionCode && r['immediate'] == true) {
        Analytics.instance.log('update_forced', {'to': availableVersion});
        try {
          await _ch.invokeMethod('start', {'immediate': true});
        } catch (_) {}
        return UpdateAsk.none;
      }
      if (r['flexible'] == true) {
        return await _snoozed(availableVersion)
            ? UpdateAsk.none
            : UpdateAsk.inApp;
      }
    }
    // Play 가 아직 모르거나 확인에 실패: 원격 설정의 최신 버전이 더 높으면 스토어로
    if (Tuning.latestVersionCode > myVersionCode) {
      availableVersion = Tuning.latestVersionCode;
      return await _snoozed(availableVersion)
          ? UpdateAsk.none
          : UpdateAsk.store;
    }
    return UpdateAsk.none;
  }

  /// '나중에' 를 누른 버전은 하루 동안 다시 묻지 않는다.
  Future<bool> _snoozed(int v) async {
    final prefs = await SharedPreferences.getInstance();
    final snooze = prefs.getString(_kSnooze) ?? '';
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return snooze == '$v@$today';
  }

  /// 스토어의 앱 페이지 열기.
  Future<void> openStore() async {
    Analytics.instance.log('update_store', {'to': availableVersion});
    try {
      await _ch.invokeMethod('openStore');
    } catch (e) {
      debugPrint('update store: $e');
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

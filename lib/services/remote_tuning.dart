import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../game/tuning.dart';

/// Firebase Remote Config 의 경제 변수를 Tuning 에 적용한다 (바이블 D-014).
/// 실패하면(오프라인 · 미설정) 기본값 그대로 — 게임은 멈추지 않는다.
class RemoteTuning {
  static Future<void> load() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 8),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      await rc.setDefaults(Tuning.defaults);
      await rc.fetchAndActivate().timeout(const Duration(seconds: 10));
      for (final key in Tuning.keys.keys) {
        final v = rc.getValue(key);
        if (v.source == ValueSource.valueRemote)
          Tuning.apply(key, v.asDouble());
      }
    } catch (_) {
      // 기본값 유지
    }
  }
}

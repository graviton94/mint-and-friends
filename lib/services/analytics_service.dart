import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';

import '../game/game_state.dart';

/// 출시 판단 지표(바이블 §10: D1 · D7 · 1구역 완료율 · 에너지 소진 · 광고)를 Firebase Analytics 로 보낸다.
/// D1 · D7 리텐션은 Firebase 가 자동으로 잰다(first_open · user_engagement).
/// Firebase 가 없거나(테스트 · 미설정) 실패해도 게임은 그대로 돈다.
class Analytics {
  Analytics._();
  static final Analytics instance = Analytics._();

  bool get _on => Firebase.apps.isNotEmpty;
  FirebaseAnalytics get _fa => FirebaseAnalytics.instance;
  StreamSubscription<GameEvent>? _sub;

  void log(String name, [Map<String, Object>? params]) {
    if (!_on) return;
    unawaited(
      _fa.logEvent(name: name, parameters: params).catchError((Object _) {}),
    );
  }

  void _prop(String name, String value) {
    if (!_on) return;
    unawaited(
      _fa.setUserProperty(name: name, value: value).catchError((Object _) {}),
    );
  }

  /// 게임 이벤트를 지표로 옮긴다. 게임 상태가 바뀌면(계정 전환) 다시 붙인다.
  void attach(GameState game) {
    _sub?.cancel();
    _sub = game.events.listen((e) {
      switch (e) {
        case LevelUpEvent():
          if (_on) {
            unawaited(_fa.logLevelUp(level: e.level).catchError((Object _) {}));
          }
          _prop('player_level', '${e.level}');
        case AreaCompletedEvent():
          log('area_complete', {'area': e.area, 'level': game.level});
          _prop('area', '${e.area + 1}');
        case FriendJoinedEvent():
          log('friend_joined', {'friend': e.friendId});
        case MaxMergeEvent():
          log('max_merge');
        case EnergyEmptyEvent():
          log('energy_empty', {'level': game.level});
        case AdRewardEvent():
          log('ad_reward', {'kind': e.kind, 'level': game.level});
        default:
          break;
      }
    });
  }

  void tutorialBegin() {
    if (_on) unawaited(_fa.logTutorialBegin().catchError((Object _) {}));
  }

  void tutorialComplete() {
    if (_on) unawaited(_fa.logTutorialComplete().catchError((Object _) {}));
  }

  void purchase(String productId) =>
      log('iap_purchase', {'product': productId});
}

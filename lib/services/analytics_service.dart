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
        case GemsSpentEvent():
          // 다이아 소비처: Firebase 표준 이벤트 + 우리 이름
          if (_on) {
            unawaited(
              _fa
                  .logSpendVirtualCurrency(
                    itemName: e.what,
                    virtualCurrencyName: 'diamond',
                    value: e.amount,
                  )
                  .catchError((Object _) {}),
            );
          }
          log('gems_spend', {
            'what': e.what,
            'amount': e.amount,
            'left': game.gems,
            'level': game.level,
          });
        case OrdersDoneEvent():
          // 하루 별 부탁 한도를 다 쓴 시각 · 그날 부탁 수 (한도가 빡빡한지)
          log('orders_done', {
            'orders': e.ordersToday,
            'hour': DateTime.now().hour,
            'level': game.level,
            'area': game.currentArea + 1,
          });
        case OrderMilestoneEvent():
          log('order_milestone', {'count': e.count, 'level': game.level});
        case RenewEvent():
          log('renew', {
            'round': e.round,
            'seeds': e.seeds,
            'level': game.level,
          });
        case LandmarkEvent():
          if (e.level == 1 || e.newStage) {
            log('landmark', {'area': e.area + 1, 'lv': e.level});
          }
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

  // ---- 상점 · 결제 퍼널 (D-044): 상점 열기 → 상품 누르기 → 결제 성공 · 취소 · 오류
  void shopOpen(GameState g, {required bool starter}) => log('shop_open', {
    'gems': g.gems,
    'level': g.level,
    'starter': starter ? 1 : 0,
  });
  void starterView(GameState g, String from) => log('starter_view', {
    'from': from,
    'level': g.level,
    'shows': g.starterShows,
  });
  void iapBegin(String productId) => log('iap_begin', {'product': productId});
  void iapCancel(String productId) => log('iap_cancel', {'product': productId});
  void iapError(String productId, String code) =>
      log('iap_error', {'product': productId, 'code': code});

  /// 보상형 광고를 보려 했지만 준비된 광고가 없었다 (광고 채움률 확인용).
  void adUnavailable() => log('ad_unavailable');

  // ---- 공유 · 초대 (D-045): 자랑하기 누름 → 공유창에서 보냄 · 초대 적용 · 초대 보상
  void shareOpen(String kind) => log('share_open', {'kind': kind});
  void shareDone(String kind, String to) =>
      log('share_done', {'kind': kind, 'to': to});
  void inviteApplied(String via) => log('invite_applied', {'via': via});
  void inviteReward(int n) => log('invite_reward', {'n': n});
}

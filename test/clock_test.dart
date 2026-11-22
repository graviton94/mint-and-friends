import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';

/// 기기 시계 조작: 앞으로 돌렸다 되돌려도 방치 수익 · 하루 한도를 되풀이해 받지 못한다.
void main() {
  late DateTime t;
  GameState make() => GameState(random: Random(1), clock: () => t);

  setUp(() => t = DateTime(2026, 3, 2, 12));

  test('뒤로 돌린 시계: 게임 시각은 멈추고, 광고 하루 횟수도 다시 차지 않는다', () {
    final g = make();
    while (g.canWatchAd(AdKind.gems)) {
      g.recordAd(AdKind.gems);
    }
    t = t.add(const Duration(days: 1)); // 하루 앞으로
    expect(g.canWatchAd(AdKind.gems), isTrue);
    while (g.canWatchAd(AdKind.gems)) {
      g.recordAd(AdKind.gems);
    }
    t = t.subtract(const Duration(days: 1)); // 되돌림
    expect(g.now, DateTime(2026, 3, 3, 12)); // 게임 시각은 그대로
    expect(g.canWatchAd(AdKind.gems), isFalse); // 어제로 돌아가 다시 받지 못함
    expect(g.computeOffline(), isNull);
  });

  test('앞으로 갔다 되돌리고 다시 앞으로: 방치 수익은 실제로 흐른 만큼만', () {
    final g = make();
    t = t.add(const Duration(hours: 10));
    g.computeOffline(); // 새 게임은 수입이 없어 보상은 없지만 '받은 시각'은 앞으로
    expect(g.lastSeen, t);
    final e0 = g.energy;
    t = t.subtract(const Duration(hours: 10)); // 되돌림
    expect(g.computeOffline(), isNull);
    t = t.add(const Duration(hours: 10)); // 다시 같은 시각으로
    expect(g.computeOffline(), isNull); // 이미 받은 시간
    expect(g.energy, e0); // 에너지도 다시 차지 않는다
  });

  test('3일 넘게 뒤로 (시계를 바로잡은 경우): 시계를 믿되 방치 수익 없음 · 지난 날 다시 초기화 안 함', () {
    final g = make();
    t = t.add(const Duration(days: 10)); // 잘못 맞춘 미래
    while (g.canWatchAd(AdKind.gems)) {
      g.recordAd(AdKind.gems);
    }
    t = DateTime(2026, 3, 2, 13); // 바로잡음
    expect(g.now, t);
    expect(g.computeOffline(), isNull);
    expect(g.canWatchAd(AdKind.gems), isFalse);
  });

  test('저장 · 불러오기 뒤에도 같은 규칙', () {
    final g = make();
    t = t.add(const Duration(days: 1));
    while (g.canWatchAd(AdKind.gems)) {
      g.recordAd(AdKind.gems);
    }
    final saved = g.toJson();
    t = t.subtract(const Duration(days: 1));
    final h = make()..loadJson(saved);
    expect(h.canWatchAd(AdKind.gems), isFalse);
    expect(h.computeOffline(), isNull);
  });
}

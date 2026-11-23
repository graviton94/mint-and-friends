import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';
import 'package:mint_and_friends/game/reward_hold.dart';

void main() {
  late DateTime now;
  GameState make() => GameState(random: Random(1), clock: () => now);
  final open = GameConfig.startCells.toList()..sort();

  setUp(() => now = DateTime(2026, 1, 1, 12));

  test('손님 창이 떠 있는 동안 시간이 지나도 선물을 받는다', () {
    final g = make();
    g.visitorUntil = now.add(const Duration(seconds: 5));
    final release = RewardHold.visitor(g);
    now = now.add(const Duration(seconds: 40)); // 광고를 보는 사이 원래 시간이 지났다
    g.tick(0.01);
    expect(g.claimVisitor(withAd: true), isNotNull);
    release();
    expect(g.visitorVisible, isFalse);
  });

  test('손님 창을 그냥 닫으면 원래 시간대로 떠난다', () {
    final g = make();
    final until = now.add(const Duration(seconds: 5));
    g.visitorUntil = until;
    final release = RewardHold.visitor(g);
    release();
    expect(g.visitorUntil, until);
    now = now.add(const Duration(seconds: 6));
    expect(g.visitorVisible, isFalse);
  });

  test('비눗방울 창 · 광고 중에는 터지지 않고, 광고 뒤 꺼낼 수 있다', () {
    final g = make();
    g.board[open[0]] = Item(
      1,
      Chain.flower,
      5,
      bubbleUntil: now.add(const Duration(seconds: 3)),
    );
    final release = RewardHold.bubble(g, open[0]);
    now = now.add(const Duration(seconds: 40));
    g.tick(0.01);
    expect(g.board[open[0]]?.isBubble, isTrue);
    expect(g.popBubble(open[0]), isTrue);
    release();
    expect(g.board[open[0]]!.isBubble, isFalse);
  });

  test('다이아로 꺼낼 때는 원래 남은 시간으로 값을 매기고, 시간이 지났어도 꺼내진다', () {
    final g = make();
    g.gems = 100;
    g.board[open[0]] = Item(
      1,
      Chain.flower,
      5,
      bubbleUntil: now.add(const Duration(seconds: 3)),
    );
    final cost = g.bubbleGemCost(open[0]);
    final release = RewardHold.bubble(g, open[0]);
    now = now.add(const Duration(seconds: 40));
    g.tick(0.01);
    release();
    expect(g.bubbleGemCost(open[0]), lessThanOrEqualTo(cost));
    expect(g.popBubbleWithGems(open[0]), isTrue);
    expect(g.gems, greaterThanOrEqualTo(100 - cost));
    // 꺼내지 않고 닫았으면 다음 tick 에 원래대로 터진다
    g.board[open[1]] = Item(
      2,
      Chain.flower,
      5,
      bubbleUntil: now.add(const Duration(seconds: 3)),
    );
    final r2 = RewardHold.bubble(g, open[1]);
    now = now.add(const Duration(seconds: 10));
    g.tick(0.01);
    expect(g.board[open[1]], isNotNull);
    r2();
    g.tick(0.01);
    expect(g.board[open[1]], isNull);
  });
}

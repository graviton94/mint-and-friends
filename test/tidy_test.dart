import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';
import 'package:mint_and_friends/game/tuning.dart';

/// D-054: 바구니보다 낮은 아이템 쓸 곳 (정리 부탁 · 모두 합치기 · 모두 팔기).
void main() {
  final now = DateTime(2026, 1, 1, 12);
  GameState make() => GameState(random: Random(7), clock: () => now);

  GameState withLow() {
    final g = make();
    g.upgrades[UpgradeType.basketTier] = 3; // 꽃 4단계부터
    g.orders.clear();
    for (var i = 0; i < g.board.length; i++) {
      if (!GameConfig.isVault(i)) g.board[i] = null;
    }
    final c = g.unlockedCells.where((i) => !GameConfig.isVault(i)).toList();
    g.board[c[0]] = Item(900, Chain.flower, 2);
    g.board[c[1]] = Item(901, Chain.flower, 2);
    g.board[c[2]] = Item(902, Chain.flower, 3);
    g.board[c[3]] = Item(903, Chain.flower, 1);
    g.board[c[4]] = Item(904, Chain.flower, 5); // 바구니 이상: 건드리지 않음
    return g;
  }

  test('낮은 아이템만 고르고, 모두 합치면 바구니 단계까지 이어서 합친다', () {
    final g = withLow();
    expect(g.lowCells.length, 4);
    expect(g.lowMergeCount, 1);
    expect(g.mergeAllLow(), 2); // 2+2 → 3, 3+3 → 4
    final lv = [
      for (final it in g.board)
        if (it != null && !it.isBubble) it.level,
    ]..sort();
    expect(lv, [1, 4, 5]);
    expect(g.lowCells.length, 1);
  });

  test('모두 팔기: 낮은 것만 팔고 되돌리기는 없다', () {
    final g = withLow();
    final c0 = g.coins;
    final expected = g.lowSellTotal;
    expect(g.sellAllLow(), closeTo(expected, 1e-6));
    expect(g.coins, greaterThan(c0));
    expect(g.lowCells, isEmpty);
    expect(g.board.where((it) => it?.level == 5).length, 1);
    expect(g.canUndoSell, isFalse);
  });

  test('부탁에 쓰일 낮은 아이템은 정리하지 않는다', () {
    final g = withLow();
    g.orders.add(Order(1, g.friends.first, Chain.flower, 3, 1));
    expect(g.lowCells.length, 3);
  });

  test('정리 부탁: 낮은 아이템이 있으면 가끔 그것을 원하고, 한 번에 하나만', () {
    final old = Tuning.cleanupChance;
    Tuning.cleanupChance = 1;
    try {
      final g = withLow();
      g.fillOrdersForTest();
      final low = g.orders
          .where((o) => o.level < g.spawnLevelOf(o.chain))
          .toList();
      expect(low.length, 1);
      expect(g.canDeliverOrder(low.first), isTrue);
    } finally {
      Tuning.cleanupChance = old;
    }
  });
}

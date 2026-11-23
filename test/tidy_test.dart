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

  test('판이 막히지 않았으면 팔 아이템을 고르지 않는다', () {
    final g = withLow();
    expect(g.boardStuck, isFalse);
    expect(g.cheapestSellCell, isNull);
  });

  test('꽉 막혔을 때만 가장 싼 낮은 아이템 하나를 고른다', () {
    final g = withLow();
    // 빈 칸을 서로 다른 아이템으로 채워 합칠 쌍이 없게
    var l = 4;
    for (final i in g.unlockedCells) {
      if (GameConfig.isVault(i)) continue;
      if (g.board[i] == null) {
        // 최고 단계(선물 가능)는 만들지 않는다: 그러면 팔라고 하지 않는다
        final c = l < 29 ? Chain.snack : Chain.tea;
        g.board[i] = Item(1000 + i, c, l < 29 ? l : l - 26);
        l++;
      }
    }
    g.board[g.unlockedCells.firstWhere((i) => g.board[i]?.level == 2)] = Item(
      990,
      Chain.tea,
      20,
    );
    expect(g.boardStuck, isTrue);
    final c = g.cheapestSellCell!;
    expect(g.board[c]!.level, 1); // 꽃 1단계 (바구니보다 낮고 가장 쌈)
    // 최고 단계 아이템이 있으면 선물할 수 있으니 팔라고 하지 않는다
    g.board[c] = Item(991, Chain.flower, Chains.maxLevel(Chain.flower));
    expect(g.boardStuck, isTrue);
    expect(g.cheapestSellCell, isNull);
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

  test('정리 부탁은 하루 별 부탁 한도를 쓰지 않고, 아이템이 없어지면 거둔다', () {
    final g = withLow();
    final f = g.friends.first;
    final cell = g.board.indexWhere((it) => it?.level == 1);
    g.orders.add(Order(77, f, Chain.flower, 1, 1, cleanup: true));
    final used = g.starOrdersUsed[f] ?? 0;
    expect(g.deliver(g.orders.indexWhere((o) => o.id == 77)), isTrue);
    expect(g.starOrdersUsed[f] ?? 0, used);
    // 다시 정리 부탁을 걸고, 그 아이템을 팔면 부탁이 사라진다
    g.board[cell] = Item(905, Chain.flower, 1);
    g.orders.add(Order(78, f, Chain.flower, 1, 1, cleanup: true));
    g.sell(cell);
    g.fillOrdersForTest();
    expect(g.orders.any((o) => o.id == 78), isFalse);
    // 저장해도 정리 부탁 표시가 남는다
    g.board[cell] = Item(906, Chain.flower, 1);
    g.orders.add(Order(79, f, Chain.flower, 1, 1, cleanup: true));
    final g2 = make()..loadJson(g.toJson());
    expect(g2.orders.firstWhere((o) => o.id == 79).cleanup, isTrue);
  });
}

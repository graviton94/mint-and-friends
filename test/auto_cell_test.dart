import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';

/// D-107: 직접 놓기는 자동 놓기 칸을 마지막에, 끄는 동안 자동 합치기는 기다린다.
void main() {
  late DateTime now;
  setUp(() => now = DateTime(2026, 11, 27, 12));

  GameState autoGame() {
    final g = GameState(random: Random(5), clock: () => now);
    g.level = 60;
    g.renewCount = 8;
    g.coins = 1e30;
    for (final t in Upgrades.autoLines) {
      while (g.buyUpgrade(t)) {}
    }
    g.energy = 100;
    return g;
  }

  test('직접 놓기는 차오르는 자동 놓기 칸을 피하고, 마지막 한 칸일 때만 쓴다', () {
    final g = autoGame();
    final auto = g.nextAutoSpawnCell!;
    while (true) {
      final empties = [
        for (var i = 0; i < GameConfig.coinCells; i++)
          if (g.board[i] == null && g.isCellOpen(i)) i,
      ];
      if (empties.length <= 1) break;
      expect(g.tapSpawner(), TapResult.spawned);
      expect(g.board[auto], isNull, reason: '빈 칸 ${empties.length}');
      expect(g.nextAutoSpawnCell, auto);
      g.energy = 100;
      for (var b = 0; b < g.basketCharge.length; b++) {
        g.basketCharge[b] = 99;
      }
    }
    expect(g.tapSpawner(), TapResult.spawned);
    expect(g.board[auto], isNotNull);
  });

  test('끌고 있는 아이템이 자동 합치기 차례면 놓을 때까지 가득 찬 채 기다린다', () {
    final g = autoGame();
    for (final c in Chain.values) {
      g.highest[c] = 20;
    }
    g.orders.clear();
    while (g.nextAutoMergePair == null) {
      g.energy = 100;
      expect(g.tapSpawner(), TapResult.spawned);
    }
    final pair = g.nextAutoMergePair!;
    final held = g.board[pair.$2]!.id;
    g.holdCell = pair.$2;
    g.autoSpawnOn = false;
    for (var s = 0; s < 600; s++) {
      g.tick(1);
    }
    expect(g.board[pair.$2]?.id, held);
    expect(g.autoMergeFrac, 1.0);
    g.holdCell = null;
    g.tick(1);
    expect(g.autoMergeFrac, lessThan(1.0));
  });
}

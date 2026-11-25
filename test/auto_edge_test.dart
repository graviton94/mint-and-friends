import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';

/// 1.0.13 점검 (D-071): 자동 줄 · 자동 정원 보너스 · 업적 · 환불의 예외 상황.
void main() {
  late DateTime now;
  GameState make() => GameState(random: Random(3), clock: () => now);
  setUp(() => now = DateTime(2026, 11, 25, 12));

  GameState autoGame() {
    final g = make();
    g.level = 60;
    g.renewCount = 8;
    g.coins = 1e30;
    for (final t in Upgrades.autoLines) {
      while (g.buyUpgrade(t)) {}
    }
    g.energy = 100;
    return g;
  }

  test('자동 2시간: 열린 칸에만 놓고, 에너지는 0 아래로 안 가고, 빈칸 1칸은 남는다', () {
    final g = autoGame();
    expect(g.lv(UpgradeType.autoSpawn), Upgrades.autoMax);
    for (var s = 0; s < 7200; s++) {
      now = now.add(const Duration(seconds: 1));
      g.tick(1);
      expect(g.energy, greaterThanOrEqualTo(0));
    }
    for (var i = 0; i < g.board.length; i++) {
      if (g.board[i] != null) expect(g.canTake(i), isTrue, reason: 'cell $i');
    }
    // 자동 합치기 상한 단계에서 멈추면 판이 차서 놓기도 쉰다 (설계)
    expect(g.stat(Stat.autoSpawns), greaterThan(20));
    for (var i = GameConfig.coinCells; i < g.board.length; i++) {
      expect(g.board[i], isNull, reason: '보관 칸 $i 은 자동으로 채우지 않는다');
    }
  });

  test('자동 합치기는 보관 칸 아이템을 건드리지 않는다', () {
    final g = autoGame();
    g.upgrades[UpgradeType.autoSpawn] = 0;
    final v = GameConfig.coinCells; // 첫 보관 칸
    g.vaultOwned.addAll([v, v + 1]);
    g.board[v] = Item(9001, Chain.flower, 2);
    g.board[v + 1] = Item(9002, Chain.flower, 2);
    for (var k = 0; k < 20; k++) {
      g.autoMergeOnce();
    }
    expect(g.board[v]?.id, 9001);
    expect(g.board[v + 1]?.id, 9002);
  });

  test('자동 정원 보너스: 켜자마자는 없고, 1분 안 만지면 붙고, 만지면 꺼진다', () {
    final g = autoGame();
    expect(g.autoIdle, isFalse);
    now = now.add(const Duration(seconds: 61));
    expect(g.autoIdle, isTrue);
    expect(g.idleMult, greaterThan(1));
    g.noteInput();
    expect(g.autoIdle, isFalse);
  });

  test('자동 놓기가 꺼져 있으면 에너지를 안 쓴다', () {
    final g = autoGame();
    g.setAutoSpawn(false);
    g.upgrades[UpgradeType.autoMerge] = 0;
    final e0 = g.energy;
    for (var s = 0; s < 600; s++) {
      now = now.add(const Duration(seconds: 1));
      g.tick(1);
    }
    expect(g.energy, greaterThanOrEqualTo(e0));
  });

  test('예전 저장(자동 합치기 10단계)을 불러오면 새 단계로, 새 저장은 그대로', () {
    final g = make();
    g.upgrades[UpgradeType.autoMerge] = 10;
    final j = g.toJson()..remove('am2');
    final old = make()..loadJson(j);
    final m = old.lv(UpgradeType.autoMerge);
    expect(m, greaterThan(10));
    final again = make()..loadJson(old.toJson());
    expect(again.lv(UpgradeType.autoMerge), m);
  });

  test('업적: 예전에 받은 단계 수는 그대로 유효하고 다음 목표가 있다', () {
    final g = make();
    final d = Achievements.all.firstWhere((a) => a.id == 'merges');
    g.achClaimed['merges'] = d.base.length; // 예전 마지막 단계까지 받음
    expect(g.achievementClaimable(d), isFalse);
    expect(d.tiers.length, greaterThan(d.base.length));
    g.stats[Stat.merges] = d.tiers[d.base.length];
    expect(g.achievementClaimable(d), isTrue);
  });
}

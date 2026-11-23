import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';

/// D-053: 늦게 열리는 체인(찻잎 · 별가루)은 1단계부터 나오고, 가치는 예전 그 등급만큼.
void main() {
  final now = DateTime(2026, 1, 1, 12);
  GameState make() => GameState(random: Random(3), clock: () => now);

  test('바구니 등급 3에서 찻잎은 1단계, 꽃은 4단계', () {
    final g = make();
    g.upgrades[UpgradeType.basketTier] = 3;
    expect(g.spawnLevelOf(Chain.flower), 4);
    expect(g.spawnLevelOf(Chain.tea), 1);
    expect(g.spawnLevelOf(Chain.stardust), 1);
    g.upgrades[UpgradeType.basketTier] = 8;
    expect(g.spawnLevelOf(Chain.tea), 6);
    expect(g.spawnLevelOf(Chain.stardust), 4);
    // 같은 등급에서 바구니가 낸 아이템끼리는 별 · 경험치가 같다
    expect(g.relLevel(Chain.tea, 6), g.relLevel(Chain.flower, 9));
  });

  test('찻잎 1단계 가치 = 꽃 4단계 가치의 3배 (예전 찻잎 4단계와 같음)', () {
    expect(
      GameConfig.valueOf(Chain.tea, 1),
      closeTo(3 * GameConfig.valueOf(Chain.flower, 4), 1e-6),
    );
    expect(
      GameConfig.valueOf(Chain.stardust, 1),
      closeTo(8 * GameConfig.valueOf(Chain.flower, 6), 1e-6),
    );
  });

  test('예전 저장의 찻잎 · 별가루는 보정만큼 낮아지고 한 번만 옮긴다', () {
    final g = make();
    g.upgrades[UpgradeType.basketTier] = 3;
    final cells = g.unlockedCells.toList();
    g.board[cells[0]] = Item(900, Chain.tea, 8);
    g.board[cells[1]] = Item(901, Chain.flower, 8);
    g.board[cells[2]] = Item(902, Chain.stardust, 3);
    g.highest[Chain.tea] = 8;
    final j = g.toJson()
      ..remove('lvOff')
      ..['tips'] = <String>[];
    final g2 = make();
    expect(g2.loadJson(j), isTrue);
    expect(g2.board[cells[0]]!.level, 5);
    expect(g2.board[cells[1]]!.level, 8);
    expect(g2.board[cells[2]]!.level, 1);
    expect(g2.highest[Chain.tea], 5);
    final g3 = make();
    expect(g3.loadJson(g2.toJson()), isTrue);
    expect(g3.board[cells[0]]!.level, 5);
    // 1.0.6 앱이 열었다 저장하면 'lvOff' 는 빠지지만 tips 표시는 남는다: 다시 낮추지 않는다
    final j106 = g2.toJson()..remove('lvOff');
    final g4 = make();
    expect(g4.loadJson(j106), isTrue);
    expect(g4.board[cells[0]]!.level, 5);
  });
}

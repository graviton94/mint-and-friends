import 'dart:math';

import 'package:bloom_merge/game/config.dart';
import 'package:bloom_merge/game/format.dart';
import 'package:bloom_merge/game/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  GameState make() => GameState(random: Random(1), clock: () => now);

  setUp(() => now = DateTime(2026, 1, 1, 12));

  test('씨앗은 시간이 지나면 자동 생성된다', () {
    final g = make();
    g.tick(Upgrades.spawnInterval(0) * 3 + 0.01);
    expect(g.board.whereType<Item>().length, 3);
  });

  test('같은 레벨끼리 합치면 레벨업, 다르면 교환, 빈칸이면 이동', () {
    final g = make();
    g.board[0] = Item(1, 1);
    g.board[1] = Item(2, 1);
    g.board[2] = Item(3, 3);
    expect(g.move(0, 1), MoveResult.merged);
    expect(g.board[0], isNull);
    expect(g.board[1]!.level, 2);
    expect(g.move(1, 2), MoveResult.swapped);
    expect(g.board[1]!.level, 3);
    expect(g.move(2, 10), MoveResult.moved);
    expect(g.board[10]!.level, 2);
  });

  test('최고 레벨 두 개를 합치면 사라지고 코인 지급', () {
    final g = make();
    final m = GameConfig.maxLevel;
    g.board[0] = Item(1, m);
    g.board[1] = Item(2, m);
    final before = g.coins;
    expect(g.move(0, 1), MoveResult.maxMerged);
    expect(g.board[0], isNull);
    expect(g.board[1], isNull);
    expect(g.coins, greaterThan(before));
  });

  test('새 레벨 발견 시 보너스 이벤트', () async {
    final g = make();
    g.board[0] = Item(1, 1);
    g.board[1] = Item(2, 1);
    final events = <GameEvent>[];
    g.events.listen(events.add);
    g.move(0, 1);
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<DiscoveryEvent>().single.level, 2);
    expect(g.highestLevel, 2);
  });

  test('자동 합치기는 가장 낮은 레벨 쌍부터', () {
    final g = make();
    g.board[0] = Item(1, 3);
    g.board[1] = Item(2, 3);
    g.board[5] = Item(3, 1);
    g.board[9] = Item(4, 1);
    expect(g.autoMergeOnce(), isTrue);
    expect(g.board[5]!.level, 2);
    expect(g.board[9], isNull);
    expect(g.board[0]!.level, 3);
  });

  test('보드가 꽉 차면 생성이 멈춘다', () {
    final g = make();
    for (var i = 0; i < GameConfig.cellCount; i++) {
      g.board[i] = Item(i + 1, (i % GameConfig.maxLevel) + 1);
    }
    g.tick(100);
    expect(g.boardFull, isTrue);
  });

  test('업그레이드 구매는 코인을 차감하고 레벨을 올린다', () {
    final g = make();
    g.coins = 1000;
    final cost = g.upgradeCost(UpgradeType.spawnSpeed);
    expect(g.buyUpgrade(UpgradeType.spawnSpeed), isTrue);
    expect(g.lv(UpgradeType.spawnSpeed), 1);
    expect(g.coins, closeTo(1000 - cost, 1e-9));
    g.coins = 0;
    expect(g.buyUpgrade(UpgradeType.spawnSpeed), isFalse);
  });

  test('정원 작업 완료는 수익 배율을 올린다', () {
    final g = make();
    g.board[0] = Item(1, 3);
    final base = g.incomePerSec;
    g.coins = 1e12;
    for (var i = 0; i < Garden.tasksPerArea; i++) {
      expect(g.buyGardenTask(), isTrue);
    }
    expect(g.currentArea, 1);
    expect(g.incomePerSec, greaterThan(base * 1.9));
  });

  test('부스트는 2배이고 최대 60분까지 누적', () {
    final g = make();
    g.board[0] = Item(1, 2);
    final base = g.incomePerSec;
    for (var i = 0; i < 10; i++) {
      g.grantBoost();
    }
    expect(g.incomePerSec, closeTo(base * 2, 1e-9));
    expect(g.boostRemaining, GameConfig.boostMax);
    now = now.add(const Duration(minutes: 61));
    expect(g.boostActive, isFalse);
  });

  test('오프라인 보상은 상한 시간과 효율이 적용된다', () {
    final g = make();
    g.board[0] = Item(1, 1);
    final rate = g.baseIncomePerSec;
    now = now.add(const Duration(hours: 10));
    final r = g.computeOffline()!;
    expect(r.away, g.offlineCap);
    expect(r.coins, closeTo(rate * g.offlineCap.inSeconds * GameConfig.offlineEfficiency, 1e-6));
    expect(g.computeOffline(), isNull);
  });

  test('저장/불러오기 왕복', () {
    final g = make();
    g.coins = 1234.5;
    g.board[3] = Item(7, 4);
    g.upgrades[UpgradeType.income] = 5;
    g.gardenProgress = 7;
    g.grantBoost();
    final g2 = make()..load(g.encode());
    expect(g2.coins, g.coins);
    expect(g2.board[3]!.level, 4);
    expect(g2.lv(UpgradeType.income), 5);
    expect(g2.gardenProgress, 7);
    expect(g2.boostActive, isTrue);
  });

  test('숫자 포맷', () {
    expect(fmt(999), '999');
    expect(fmt(1500), '1.50K');
    expect(fmt(2.5e6), '2.50M');
    expect(fmt(1e15), '1.00aa');
  });
}

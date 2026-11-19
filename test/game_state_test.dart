import 'dart:math';

import 'package:bloom_merge/game/config.dart';
import 'package:bloom_merge/game/format.dart';
import 'package:bloom_merge/game/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  GameState make() => GameState(random: Random(1), clock: () => now);
  Item flower(int id, int lv) => Item(id, Chain.flower, lv);
  Item snack(int id, int lv) => Item(id, Chain.snack, lv);
  final open = GameConfig.startCells.toList()..sort();

  setUp(() => now = DateTime(2026, 1, 1, 12));

  test('처음에는 가운데 4x3 칸만 열려 있다', () {
    final g = make();
    expect(g.unlockedCells.length, 12);
    expect(g.isCellOpen(0), isFalse);
    expect(g.isCellOpen(7), isTrue);
  });

  test('바구니는 열린 칸에만 아이템을 만든다', () {
    final g = make();
    g.tick(g.spawnInterval * 20 + 0.01);
    expect(g.board.whereType<Item>().length, 12);
    for (var i = 0; i < g.board.length; i++) {
      if (g.board[i] != null) expect(g.isCellOpen(i), isTrue);
    }
    expect(g.boardFull, isTrue);
  });

  test('간식은 레벨 3부터 나온다', () {
    final g = make();
    g.tick(g.spawnInterval * 12 + 0.01);
    expect(
      g.board.whereType<Item>().every((it) => it.chain == Chain.flower),
      isTrue,
    );
    expect(g.orders.every((o) => o.chain == Chain.flower), isTrue);
    g.level = 3;
    expect(g.availableChains, contains(Chain.snack));
  });

  test('같은 종류·같은 레벨만 합쳐지고, 잠긴 칸으로는 못 옮긴다', () {
    final g = make();
    g.board[open[0]] = flower(1, 1);
    g.board[open[1]] = flower(2, 1);
    g.board[open[2]] = snack(3, 2);
    expect(g.move(open[0], open[1]), MoveResult.merged);
    expect(g.board[open[1]]!.level, 2);
    expect(g.move(open[1], open[2]), MoveResult.swapped);
    expect(g.move(open[2], 0), MoveResult.none); // 0번은 잠긴 칸
    expect(g.move(open[2], open[5]), MoveResult.moved);
  });

  test('합치면 경험치를 얻고 레벨업하면 보상과 해금 이벤트', () async {
    final g = make();
    final events = <GameEvent>[];
    g.events.listen(events.add);
    g.xp = g.xpToNext - 1;
    g.board[open[0]] = flower(1, 1);
    g.board[open[1]] = flower(2, 1);
    g.move(open[0], open[1]);
    await Future<void>.delayed(Duration.zero);
    expect(g.level, 2);
    final up = events.whereType<LevelUpEvent>().single;
    expect(up.unlocked, containsAll([Feature.upgrades, Feature.boost]));
    expect(g.stars, Leveling.levelUpStars);
  });

  test('칸 구매: 레벨과 코인이 필요하고 살수록 비싸진다', () {
    final g = make();
    g.coins = 1e9;
    expect(g.canBuyCell(0), isFalse); // 레벨 부족
    g.level = 10;
    final c0 = g.nextCellCost;
    expect(g.buyCell(0), isTrue);
    expect(g.isCellOpen(0), isTrue);
    expect(g.nextCellCost, greaterThan(c0));
    expect(g.buyCell(0), isFalse); // 이미 열림
    expect(g.buyCell(7), isFalse); // 원래 열린 칸
  });

  test('판매하면 코인을 받고, 잠깐 동안 되돌릴 수 있다', () {
    final g = make();
    g.board[open[0]] = flower(1, 5);
    final price = g.sell(open[0])!;
    expect(price, greaterThan(0));
    expect(g.board[open[0]], isNull);
    expect(g.coins, price);
    expect(g.undoSell(), isTrue);
    expect(g.board[open[0]]!.level, 5);
    expect(g.coins, 0);
    g.sell(open[0]);
    now = now.add(GameConfig.sellUndoWindow);
    expect(g.undoSell(), isFalse);
  });

  test('꽉 차고 합칠 게 없으면 boardStuck', () {
    final g = make();
    var lv = 1;
    for (final c in open) {
      g.board[c] = flower(c, lv++);
    }
    expect(g.boardStuck, isTrue);
    g.board[open[0]] = flower(99, 2);
    expect(g.boardStuck, isFalse);
  });

  test('비눗방울은 움직일 수 없고, 꺼내면 보통 아이템, 시간이 지나면 사라진다', () {
    final g = make();
    g.board[open[0]] = Item(
      1,
      Chain.flower,
      5,
      bubbleUntil: now.add(GameConfig.bubbleLife),
    );
    g.board[open[1]] = Item(
      2,
      Chain.flower,
      5,
      bubbleUntil: now.add(GameConfig.bubbleLife),
    );
    g.board[open[2]] = flower(3, 5);
    expect(g.move(open[0], open[3]), MoveResult.none);
    expect(g.move(open[2], open[0]), MoveResult.none);
    expect(g.baseIncomePerSec, closeTo(GameConfig.incomeOf(5), 1e-9));
    expect(g.popBubble(open[0]), isTrue);
    expect(g.board[open[0]]!.isBubble, isFalse);
    now = now.add(GameConfig.bubbleLife);
    g.tick(0.01);
    expect(g.board[open[1]], isNull);
  });

  test('부탁: 아이템을 전달하면 별·코인·호감도·경험치', () {
    final g = make();
    expect(g.orders.length, GameConfig.orderSlots);
    final o = g.orders[0];
    expect(g.canDeliver(0), isFalse);
    g.board[open[4]] = Item(99, o.chain, o.level);
    expect(g.deliver(0), isTrue);
    expect(g.board[open[4]], isNull);
    expect(g.stars, greaterThanOrEqualTo(o.stars));
    expect(g.deliveries[o.friendId], 1);
    expect(g.xp + g.level, greaterThan(1));
    expect(g.orders[0].id, isNot(o.id));
  });

  test('자동 합치기는 부탁 아이템을 남기고 가장 낮은 쌍부터', () {
    final g = make();
    g.orders = [
      for (var i = 0; i < 3; i++) Order(900 + i, 'bori', Chain.flower, 3, 1),
    ];
    g.board[open[0]] = flower(1, 3);
    g.board[open[1]] = flower(2, 3);
    expect(g.autoMergeOnce(), isFalse);
    g.board[open[2]] = flower(3, 1);
    g.board[open[3]] = flower(4, 1);
    expect(g.autoMergeOnce(), isTrue);
    expect(g.board[open[2]]!.level, 2);
    expect(g.board[open[3]], isNull);
  });

  test('장식: 별 필요, 친구 합류, 다음 구역은 레벨 제한', () {
    final g = make();
    final friendSlot = Garden.areas[0].decor.indexWhere(
      (d) => d.bringsFriend != null,
    );
    final friendId = Garden.areas[0].decor[friendSlot].bringsFriend!;
    expect(g.canPlace(friendSlot), isFalse);
    g.stars = 1000;
    expect(g.placeDecor(friendSlot), isTrue);
    expect(g.friends, contains(friendId));
    for (var s = 0; s < Garden.slotsPerArea; s++) {
      g.placeDecor(s);
    }
    expect(g.currentArea, 1);
    g.level = 1;
    expect(g.areaLocked, isTrue);
    expect(g.canPlace(0), isFalse);
    g.level = Leveling.areaLevel(1);
    expect(g.canPlace(0), isTrue);
  });

  test('강화는 기능 해금과 레벨 상한을 따른다', () {
    final g = make();
    g.coins = 1e12;
    expect(g.canBuyUpgrade(UpgradeType.spawnSpeed), isFalse); // 강화 메뉴 잠김
    g.level = 2;
    expect(g.canBuyUpgrade(UpgradeType.spawnSpeed), isTrue);
    expect(g.canBuyUpgrade(UpgradeType.autoMerge), isFalse);
    while (g.buyUpgrade(UpgradeType.spawnSpeed)) {}
    expect(g.lv(UpgradeType.spawnSpeed), Leveling.upgradeCap(2));
    expect(g.upgradeCapped(UpgradeType.spawnSpeed), isTrue);
  });

  test('친구 호감도는 버프가 된다', () {
    final g = make();
    final base = g.spawnInterval;
    g.deliveries['bori'] = Friends.deliveriesPerAffection * 5;
    expect(g.affection('bori'), 5);
    expect(g.spawnInterval, lessThan(base));
  });

  test('깜짝 손님은 레벨 6부터, 받으면 사라진다', () {
    final g = make();
    now = now.add(GameConfig.visitorMinGap);
    g.tick(0.1);
    expect(g.visitorVisible, isFalse);
    g.level = Leveling.unlockLevel[Feature.visitor]!;
    g.tick(0.1);
    expect(g.visitorVisible, isTrue);
    expect(g.claimVisitor(withAd: true)!.stars, GameConfig.visitorAdStars);
    expect(g.visitorVisible, isFalse);
  });

  test('부스트는 2배이고 최대 60분까지 누적', () {
    final g = make();
    g.board[open[0]] = flower(1, 2);
    final base = g.incomePerSec;
    for (var i = 0; i < 10; i++) {
      g.grantBoost();
    }
    expect(g.incomePerSec, closeTo(base * 2, 1e-9));
    expect(g.boostRemaining, GameConfig.boostMax);
  });

  test('오프라인 보상은 상한 시간과 효율이 적용된다', () {
    final g = make();
    g.board[open[0]] = flower(1, 1);
    final rate = g.baseIncomePerSec;
    now = now.add(const Duration(hours: 10));
    final r = g.computeOffline()!;
    expect(r.away, g.offlineCap);
    expect(
      r.coins,
      closeTo(
        rate * g.offlineCap.inSeconds * GameConfig.offlineEfficiency,
        1e-6,
      ),
    );
    expect(g.computeOffline(), isNull);
  });

  test('저장/불러오기 왕복', () {
    final g = make();
    g.coins = 1234.5;
    g.stars = 7;
    g.level = 5;
    g.xp = 3;
    g.unlockedCells.add(0);
    g.board[0] = snack(50, 4);
    g.board[open[0]] = Item(
      51,
      Chain.flower,
      6,
      bubbleUntil: now.add(const Duration(seconds: 30)),
    );
    g.upgrades[UpgradeType.income] = 5;
    g.currentArea = 1;
    g.placed = {2, 5};
    g.friends.add('kwak');
    g.deliveries['bori'] = 3;
    final g2 = make();
    expect(g2.load(g.encode()), isTrue);
    expect(g2.coins, g.coins);
    expect(g2.level, 5);
    expect(g2.xp, 3);
    expect(g2.isCellOpen(0), isTrue);
    expect(g2.board[0]!.chain, Chain.snack);
    expect(g2.board[open[0]]!.isBubble, isTrue);
    expect(g2.lv(UpgradeType.income), 5);
    expect(g2.placed, {2, 5});
    expect(g2.friends, containsAll(['bori', 'kwak']));
    expect(g2.savedAt, isNotNull);
    expect([for (final o in g2.orders) o.id], [for (final o in g.orders) o.id]);
  });

  test('예전 버전 저장은 무시한다', () {
    expect(make().load('{"v":2,"coins":5}'), isFalse);
  });

  test('숫자 포맷', () {
    expect(fmt(999), '999');
    expect(fmt(1500), '1.50K');
    expect(fmt(2.5e6), '2.50M');
    expect(fmt(1e15), '1.00aa');
  });
}

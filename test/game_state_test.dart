import 'dart:math';

import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/format.dart';
import 'package:mint_and_friends/game/game_state.dart';
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

  test('바구니는 탭(에너지)으로만, 열린 칸에만 아이템을 만든다', () {
    final g = make();
    g.tick(600); // 시간이 흘러도 저절로 생기지 않는다
    expect(g.board.whereType<Item>(), isEmpty);
    for (var i = 0; i < 20; i++) {
      g.tapSpawner();
    }
    expect(g.board.whereType<Item>().length, 12);
    for (var i = 0; i < g.board.length; i++) {
      if (g.board[i] != null) expect(g.isCellOpen(i), isTrue);
    }
    expect(g.boardFull, isTrue);
  });

  test('간식은 레벨 3부터 나온다', () {
    final g = make();
    for (var i = 0; i < 12; i++) {
      g.tapSpawner();
    }
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
    expect(up.unlocked, containsAll([Feature.energyAd, Feature.upgrades]));
    expect(g.stars, Leveling.levelUpStars);
    expect(up.energy, Leveling.levelUpEnergy(2, 0));
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
    expect(g.canBuyUpgrade(UpgradeType.energyRegen), isFalse); // 강화 메뉴 잠김
    g.level = 2;
    expect(g.canBuyUpgrade(UpgradeType.energyRegen), isFalse); // Lv8 부터
    g.level = 8;
    expect(g.canBuyUpgrade(UpgradeType.spawnLevel), isFalse); // Lv10 기능
    while (g.buyUpgrade(UpgradeType.energyRegen)) {}
    expect(g.lv(UpgradeType.energyRegen), 1); // 다음 단계는 Lv14
    expect(g.upgradeCapped(UpgradeType.energyRegen), isTrue);
    expect(g.upgradeLevelNeeded(UpgradeType.energyRegen), 14);
  });

  test('친구 호감도는 버프가 된다', () {
    final g = make();
    final base = g.energyRegenSeconds;
    g.deliveries['bori'] = Friends.deliveriesPerAffection * 5;
    expect(g.affection('bori'), 5);
    expect(g.energyRegenSeconds, base); // 하트만으로는 효과 없음, 레벨을 올려야
    g.coins = 1e9;
    for (var k = 0; k < 7; k++) {
      g.levelFriend('bori');
    }
    expect(g.friendLevel('bori'), 5); // 하트 5개까지
    expect(g.energyRegenSeconds, lessThan(base));
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
    expect(g.boostRemaining, Boosts.max);
  });

  test('오프라인 보상: 최소 시간, 상한 시간, 시간이 길수록 감쇄', () {
    final g = make();
    g.board[open[0]] = flower(1, 1);
    final rate = g.baseIncomePerSec;
    // 10분만 비우면 보상 없음
    now = now.add(const Duration(minutes: 10));
    expect(g.computeOffline(), isNull);
    // 10시간 비우면 상한까지만, 감쇄 적용 (1시간 50% + 2시간 25% + 나머지 10%)
    now = now.add(const Duration(hours: 10));
    final r = g.computeOffline()!;
    expect(r.away, g.offlineCap);
    final cap = g.offlineCap.inSeconds.toDouble();
    expect(r.coins, closeTo(GameConfig.offlineEarnings(rate, cap), 1e-9));
    // 구간별 효율: 1시간 50%, 다음 2시간 25%, 그 뒤 10%
    expect(GameConfig.offlineEarnings(1, 3600), closeTo(1800, 1e-9));
    expect(GameConfig.offlineEarnings(1, 3 * 3600), closeTo(1800 + 1800, 1e-9));
    expect(GameConfig.offlineEarnings(1, 4 * 3600), closeTo(3600 + 360, 1e-9));
    expect(r.coins, lessThan(rate * cap * 0.5)); // 평균 효율 50% 미만
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

  test('에너지: 탭 1회에 1 소모, 2분에 1 회복, 상한 100', () {
    final g = make();
    expect(g.energy, GameConfig.energyStart);
    expect(g.tapSpawner(), TapResult.spawned);
    expect(g.energy, GameConfig.energyStart - 1);
    g.energy = 0;
    expect(g.tapSpawner(), TapResult.noEnergy);
    g.tick(GameConfig.energyRegenSeconds.toDouble());
    expect(g.energy, 1);
    g.energy = GameConfig.energyCap;
    g.tick(1000);
    expect(g.energy, GameConfig.energyCap);
  });

  test('에너지는 오프라인 동안에도 찬다', () {
    final g = make();
    g.energy = 0;
    now = now.add(const Duration(minutes: 60));
    g.computeOffline();
    expect(g.energy, 3600 ~/ GameConfig.energyRegenSeconds); // 2분 30초에 1
  });

  test('보상형 광고는 종류별 하루 상한이 있고 날짜가 바뀌면 초기화', () {
    final g = make();
    final cap = GameConfig.adDailyCap[AdKind.energy]!;
    for (var i = 0; i < cap; i++) {
      expect(g.canWatchAd(AdKind.energy), isTrue);
      g.recordAd(AdKind.energy);
      g.grantEnergyAd();
    }
    expect(g.canWatchAd(AdKind.energy), isFalse);
    expect(g.energy, GameConfig.energyStart + cap * GameConfig.energyAdAmount);
    now = now.add(const Duration(days: 1));
    expect(g.canWatchAd(AdKind.energy), isTrue);
  });

  test('레벨업은 에너지를 준다', () {
    final g = make();
    g.energy = 3;
    g.xp = g.xpToNext - 1;
    g.board[open[0]] = Item(1, Chain.flower, 1);
    g.board[open[1]] = Item(2, Chain.flower, 1);
    g.orders = [
      Order(1, 'bori', Chain.flower, 2, 1),
      Order(2, 'bori', Chain.flower, 9, 1),
      Order(3, 'bori', Chain.flower, 10, 1),
    ];
    g.move(open[0], open[1]);
    expect(g.deliver(0), isTrue);
    expect(g.level, 2);
    expect(g.energy, 3 + Leveling.levelUpEnergy(2, 3));
  });

  test('수익 강화: 단계마다 +10%, 최대 10단계 ×2', () {
    expect(Upgrades.incomeMultiplier(0), 1);
    expect(Upgrades.incomeMultiplier(10), closeTo(2.0, 1e-9));
    expect(Upgrades.of(UpgradeType.income).maxLevel, 10);
  });

  test(
    '경험치 곡선: 누적 Lv5≈116, Lv10≈770, Lv20≈5.2K, Lv30≈15.5K (장르 조사 곡선 × 1.3)',
    () {
      int cum(int to) =>
          [for (var l = 1; l < to; l++) Leveling.xpToNext(l)]
              .fold(0, (a, b) => a + b);
      expect(cum(5), inInclusiveRange(105, 125));
      expect(cum(10), inInclusiveRange(720, 820));
      expect(cum(20), inInclusiveRange(4900, 5500));
      expect(cum(30), inInclusiveRange(14800, 16200));
    },
  );

  test('숫자 포맷', () {
    expect(fmt(999), '999');
    expect(fmt(1500), '1.50K');
    expect(fmt(2.5e6), '2.50M');
    expect(fmt(1e15), '1.00aa');
  });

  test('방금 전달한 부탁 · 판에 이미 있는 아이템은 새 부탁으로 바로 나오지 않는다', () {
    final g = make();
    for (var round = 0; round < 30; round++) {
      final o = g.orders[0];
      final cell = g.board.indexWhere((it) => it == null);
      if (cell < 0) break;
      g.board[cell] = Item(9000 + round, o.chain, o.level);
      expect(g.deliver(0), isTrue);
      final n = g.orders.last; // 새 부탁은 끝에 붙는다
      expect(n.chain == o.chain && n.level == o.level, isFalse);
      expect(
        g.board.any(
          (it) =>
              it != null &&
              !it.isBubble &&
              it.chain == n.chain &&
              it.level == n.level,
        ),
        isFalse,
        reason: '판에 이미 있는 아이템을 새 부탁으로 내면 안 됨',
      );
    }
  });

  test('에너지 절약 부스트: 대략 절반만 에너지를 쓴다', () {
    final g = GameState(random: Random(7));
    g.board.fillRange(0, g.board.length, null);
    g.energy = 1000;
    g.grantBoostAd(BoostKind.energy);
    var taps = 0;
    for (var i = 0; i < 200; i++) {
      if (g.boardFull) g.board.fillRange(0, g.board.length, null);
      if (g.tapSpawner() == TapResult.spawned) taps++;
    }
    final spent = 1000 - g.energy;
    expect(taps, 200);
    expect(spent, inInclusiveRange(70, 130));
  });

  test('최고 단계 아이템 선물: 하트 +1 · 코인, 하트가 차면 별', () {
    final g = GameState(random: Random(1));
    g.friends.add('dubu');
    final max = Chains.maxLevel(Chain.tea);
    g.board[0] = Item(900, Chain.tea, max);
    final h = g.affection('dubu');
    final c = g.coins;
    expect(g.giftMaxItem(0, 'dubu'), isTrue);
    expect(g.board[0], isNull);
    expect(g.affection('dubu'), h + 1);
    expect(g.coins, greaterThan(c));
    g.board[1] = Item(901, Chain.tea, max - 1);
    expect(g.giftMaxItem(1, 'dubu'), isFalse);
    g.deliveries['dubu'] = 100;
    final st = g.stars;
    g.board[2] = Item(902, Chain.tea, max);
    expect(g.giftMaxItem(2, 'dubu'), isTrue);
    expect(g.stars, st + GameConfig.maxGiftStars);
  });

  test('한 화면 단위 통일: 가장 큰 값 기준', () {
    final u = UnitFmt.of([800, 2000, 12500]);
    expect(u(800), '0.80K');
    expect(u(2000), '2.00K');
    expect(u(12500), '12.5K');
    expect(u(125000), '125K');
    expect(UnitFmt.of([300, 800])(300), '300');
    expect(UnitFmt.of([300, 2.5e6])(2.5e6), '2.50M');
  });
}

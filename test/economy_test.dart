import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';
import 'package:mint_and_friends/game/tuning.dart';

void main() {
  late DateTime now;
  GameState make() => GameState(random: Random(5), clock: () => now);
  setUp(() => now = DateTime(2026, 1, 1, 12));

  test('부탁 별은 에너지에 비례하고, 높은 단계일수록 에너지당 별이 같거나 조금 더 많다', () {
    double perStar(int l) => pow(2, l - 1) / Garden.orderStars(l);
    expect(Garden.orderStars(3), 1);
    expect(Garden.orderStars(4), 2);
    expect(Garden.orderStars(5), 4);
    for (var l = 4; l <= 12; l++) {
      expect(
        perStar(l),
        lessThanOrEqualTo(perStar(l - 1) + 0.01),
        reason: 'Lv$l',
      );
      expect(perStar(l), inInclusiveRange(2.5, 4.1), reason: 'Lv$l');
    }
  });

  test('구역 꾸미기 별: 구역 합계를 따르고 뒤 구역일수록 비싸다', () {
    for (var a = 0; a < 8; a++) {
      final total = [
        for (var s = 0; s < Garden.slotsPerArea; s++) Garden.decorCost(a, s),
      ].reduce((x, y) => x + y);
      expect(total, closeTo(Garden.areaStars(a), Garden.areaStars(a) * 0.1));
      if (a > 0) {
        expect(Garden.areaStars(a), greaterThan(Garden.areaStars(a - 1)));
      }
    }
  });

  test('예전 경제 저장: 남은 별은 4배, 부탁 별은 새 규칙으로', () {
    final g = make();
    g.stars = 10;
    g.orders = [Order(900, 'bori', Chain.flower, 6, 3)];
    final j = g.toJson()..remove('econ');
    final g2 = make();
    expect(g2.loadJson(j), isTrue);
    expect(g2.stars, 40);
    expect(g2.orders.first.stars, Garden.orderStars(6));
    // 새 저장은 다시 곱하지 않는다
    final g3 = make();
    expect(g3.loadJson(g2.toJson()), isTrue);
    expect(g3.stars, 40);
  });

  test('구조 부탁: 판에 막힌 고단계 아이템을 언젠가 원한다 (10분 간격)', () {
    final g = make();
    final cell = g.unlockedCells.first;
    g.board[cell] = Item(777, Chain.flower, 9);
    expect(g.stuckItem?.level, 9);
    var asked = false;
    for (var i = 0; i < 40 && !asked; i++) {
      now = now.add(const Duration(minutes: 11));
      g.refreshOrder(0);
      asked = g.orders.any((o) => o.chain == Chain.flower && o.level == 9);
    }
    expect(asked, isTrue);
    expect(g.stuckItem, isNull); // 이미 부탁에 걸려 있으면 다시 고르지 않는다
  });

  test('다이아: 레벨업 지급, 에너지 충전은 하루 안에 비싸지고 날이 바뀌면 원래대로', () {
    final g = make();
    g.gems = 200;
    expect(g.refillCost, 40);
    final e0 = g.energy;
    expect(g.buyEnergyRefill(), isTrue);
    expect(g.energy, e0 + Gems.refillEnergy);
    expect(g.gems, 160);
    expect(g.refillCost, 60);
    now = now.add(const Duration(days: 1));
    expect(g.adsLeft(AdKind.energy), greaterThan(0)); // 날짜 갱신
    expect(g.refillCost, 40);
    g.gems = 10;
    expect(g.buyEnergyRefill(), isFalse);
  });

  test('다이아: 비눗방울 바로 열기는 남은 시간에 비례', () {
    final g = make();
    final cell = g.unlockedCells.first;
    g.board[cell] = Item(
      1,
      Chain.flower,
      5,
      bubbleUntil: now.add(const Duration(seconds: 60)),
    );
    expect(g.bubbleGemCost(cell), 3);
    g.gems = 2;
    expect(g.popBubbleWithGems(cell), isFalse);
    g.gems = 5;
    expect(g.popBubbleWithGems(cell), isTrue);
    expect(g.gems, 2);
    expect(g.board[cell]!.isBubble, isFalse);
  });

  test('다이아 팩: 큰 팩일수록 보너스가 크고, 저장 후에도 다이아가 남는다', () {
    for (var i = 1; i < Gems.packs.length; i++) {
      expect(Gems.packs[i].bonusPct, greaterThan(Gems.packs[i - 1].bonusPct));
    }
    final g = make()..grantGems(330);
    final g2 = make();
    expect(g2.loadJson(g.toJson()), isTrue);
    expect(g2.gems, 330);
  });

  test('출석: 하루 한 번, 7일 한 바퀴, 빠진 날이 있어도 이어서', () {
    final g = make();
    expect(g.checkInReady, isTrue);
    final e0 = g.energy;
    expect(g.claimCheckIn()!.energy, 20);
    expect(g.energy, e0 + 20);
    expect(g.claimCheckIn(), isNull);
    now = now.add(const Duration(days: 3)); // 이틀 빠짐
    expect(g.checkInToday, 1);
    expect(g.claimCheckIn()!.coins, greaterThan(0));
    var gems = 0;
    for (var d = 2; d < CheckIn.days; d++) {
      now = now.add(const Duration(days: 1));
      gems += g.claimCheckIn()!.gems;
    }
    expect(gems, 35); // 한 주 무료 다이아 = 하루 5개
    expect(g.checkInToday, 0);
    final g2 = make();
    expect(g2.loadJson(g.toJson()), isTrue);
    expect(g2.checkInReady, isFalse);
  });

  test('오늘의 시장: Lv4부터, 하루 4칸, 한 번씩, 판에 놓인다, 다음 날 새로', () {
    final g = make();
    g.level = 6;
    expect(g.dailyShopOpen, isTrue);
    expect(g.offers.length, DailyShop.slots);
    g.coins = 0;
    expect(g.buyOffer(0), BuyResult.noCoins);
    g.coins = 100000;
    final before = g.board.whereType<Item>().length;
    expect(g.buyOffer(0), BuyResult.ok);
    expect(g.board.whereType<Item>().length, before + 1);
    expect(g.buyOffer(0), BuyResult.sold);
    final first = g.offers.map((o) => '${o.chain}${o.level}${o.sold}').join();
    now = now.add(const Duration(days: 1));
    expect(g.offers.every((o) => !o.sold), isTrue);
    expect(first, isNotEmpty);
  });

  test('원격 조정: 범위 안 값만 적용되고 실제 계산에 반영된다', () {
    expect(Tuning.apply('refill_base', 1000), isFalse);
    expect(Tuning.apply('unknown', 1), isFalse);
    expect(Tuning.apply('refill_base', 50), isTrue);
    expect(Gems.refillCost(0), 50);
    expect(Tuning.apply('area_star_scale', 2), isTrue);
    expect(Garden.areaStars(0), 48);
    Tuning.apply('refill_base', 40);
    Tuning.apply('area_star_scale', 1);
    expect(Tuning.defaults.keys.toSet(), Tuning.keys.keys.toSet());
  });

  test('장식 디자인: 놓은 자리만, 고급은 코인 · 특별은 다이아, 산 것은 무료로 바꾼다', () {
    final g = make();
    expect(g.setStyle(0, 0, 1), StyleResult.notPlaced);
    g.stars = 1000;
    expect(g.placeDecor(0), isTrue);
    g.coins = 0;
    expect(g.setStyle(0, 0, 1), StyleResult.noCoins);
    g.coins = Garden.styleCoins(0, 0).toDouble();
    expect(g.setStyle(0, 0, 1), StyleResult.ok);
    expect(g.coins, 0);
    expect(g.styleOf(0, 0), 1);
    expect(g.setStyle(0, 0, 2), StyleResult.noGems);
    g.gems = Garden.styleGems(0);
    expect(g.setStyle(0, 0, 2), StyleResult.ok);
    expect(g.gems, 0);
    expect(g.setStyle(0, 0, 1), StyleResult.ok); // 이미 산 것: 무료
    expect(g.setStyle(0, 0, 0), StyleResult.ok);
    expect(g.styleOf(0, 0), 0);
    final g2 = make();
    expect(g2.loadJson(g.toJson()), isTrue);
    expect(g2.ownsStyle(0, 0, 2), isTrue);
  });

  test('장식 경험치는 별 가격이 아니라 구역 · 자리 기준', () {
    expect(Leveling.xpForDecor(0, 0), 2);
    expect(Leveling.xpForDecor(3, 7), 20);
  });

  test('바구니: 그림 · 구역이 준비되면 찻잎 바구니가 열리고, 찻잎은 10단계가 끝', () {
    final g = make();
    expect(g.openBaskets, [0]); // 테스트에는 새 체인 그림이 없다
    final keep = Chains.ready;
    Chains.ready = (_) => true;
    addTearDown(() => Chains.ready = keep);
    expect(g.basketOpen(1), isFalse); // 아직 온실 구역 전
    g.currentArea = 2;
    expect(g.openBaskets, [0, 1]);
    g.selectBasket(1);
    g.tapSpawner();
    final made = g.board.whereType<Item>().toList();
    expect(made.single.chain, Chain.tea);
    expect(g.availableChains, contains(Chain.tea));
    expect(Chains.maxLevel(Chain.tea), 10);
    expect(Chains.item(Chain.tea, 15).level, 10);
    final cells = g.unlockedCells.toList()..sort();
    for (final c in cells) {
      g.board[c] = null;
    }
    g.board[cells[0]] = Item(901, Chain.tea, 10);
    g.board[cells[1]] = Item(902, Chain.tea, 10);
    final c0 = g.coins;
    g.move(cells[0], cells[1]);
    expect(g.coins, greaterThan(c0)); // 최고 단계 합치기 = 코인 보상
    expect(g.board[cells[1]], isNull);
  });

  test('5 · 6구역: 그림이 없으면 1~4구역 순환, 그림이 들어오면 바닷가 · 눈꽃 마을이 열린다', () {
    expect(Garden.live.length, Garden.coreAreas);
    expect(Garden.areaAt(4).id, 'yard');
    final keep = Garden.ready;
    Garden.ready = (_) => true;
    addTearDown(() => Garden.ready = keep);
    expect(Garden.areaAt(4).id, 'seaside');
    expect(Garden.areaAt(5).id, 'snow_village');
    expect(Garden.areaAt(6).id, 'yard');
    expect(
      Garden.areaAt(4).decor.any((d) => d.bringsFriend == 'bogeul'),
      isTrue,
    );
  });
}

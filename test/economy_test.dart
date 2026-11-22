import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/services/notify_service.dart';
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
    expect(g.refillCost, 60);
    final e0 = g.energy;
    expect(g.buyEnergyRefill(), isTrue);
    expect(g.energy, e0 + Gems.refillEnergy);
    expect(g.gems, 140);
    expect(g.refillCost, 90);
    now = now.add(const Duration(days: 1));
    expect(g.adsLeft(AdKind.energy), greaterThan(0)); // 날짜 갱신
    expect(g.refillCost, 60);
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

  test('오늘의 시장: Lv4부터, 코인 4칸 + 다이아 · 광고 칸, 한 번씩, 판에 놓인다, 다음 날 새로', () {
    final g = make();
    g.level = 6;
    expect(g.dailyShopOpen, isTrue);
    expect(g.offers.length, DailyShop.slots + 2);
    expect(g.offers[DailyShop.slots].kind, 3); // 다이아로 사는 고단계
    expect(g.offers[DailyShop.slots + 1].kind, 4); // 광고 보고 받는 고단계
    expect(g.buyOffer(DailyShop.slots + 1), BuyResult.needAd);
    expect(g.offers.first.kind, 1); // 첫 칸은 무료 선물
    expect(g.offers.first.price, 0);
    expect(g.freeOfferReady, isTrue);
    g.coins = 0;
    expect(g.buyOffer(DailyShop.slots - 1), BuyResult.noCoins);
    g.coins = 100000;
    final before = g.board.whereType<Item>().length;
    expect(g.buyOffer(0), BuyResult.ok);
    expect(g.board.whereType<Item>().length, before + 1);
    expect(g.buyOffer(0), BuyResult.sold);
    expect(g.freeOfferReady, isFalse);
    // 판이 가득하면 사지 못한다 (화면은 '판이 가득'을 보여 준다)
    for (final c in g.unlockedCells) {
      g.board[c] ??= Item(5000 + c, Chain.flower, 1);
    }
    expect(g.buyOffer(1), BuyResult.noSpace);
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
    Tuning.apply('refill_base', 60);
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

  test('바구니: 그림 · 구역이 준비되면 찻잎 바구니가 열리고, 찻잎은 30단계가 끝', () {
    final g = make();
    expect(g.openBaskets, [0]); // 테스트에는 새 체인 그림이 없다
    final keep = Chains.ready;
    Chains.ready = (_) => true;
    addTearDown(() => Chains.ready = keep);
    expect(g.basketOpen(1), isFalse); // 아직 온실 구역 전
    g.currentArea = 2;
    g.level = Leveling.areaLevel(2) - 1;
    expect(g.basketOpen(1), isFalse); // 구역에 왔어도 그 구역 레벨 전에는 닫힘
    g.level = Leveling.areaLevel(2);
    expect(g.openBaskets, [0, 1]);
    g.selectBasket(1);
    g.tapSpawner();
    final made = g.board.whereType<Item>().toList();
    expect(made.single.chain, Chain.tea);
    expect(g.availableChains, contains(Chain.tea));
    expect(Chains.maxLevel(Chain.tea), 30);
    expect(Chains.item(Chain.tea, 40).level, 30);
    final cells = g.unlockedCells.toList()..sort();
    for (final c in cells) {
      g.board[c] = null;
    }
    g.board[cells[0]] = Item(901, Chain.tea, 30);
    g.board[cells[1]] = Item(902, Chain.tea, 30);
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

  test('재단장 씨앗은 누적 코인 몫 − 이미 받은 몫 (같은 지점에서 다시 하면 0)', () {
    final g = make();
    g.upgrades[UpgradeType.basketTier] = Renewal.needBasketTier;
    g.lifetimeCoins = Renewal.coinsForSeeds(8);
    expect(g.renewSeedsPreview, 8);
    expect(g.renew(), 8);
    g.upgrades[UpgradeType.basketTier] = Renewal.needBasketTier;
    expect(g.renewSeedsPreview, 0);
    expect(g.canRenew, isFalse);
    g.lifetimeCoins = Renewal.coinsForSeeds(10);
    expect(g.renewSeedsPreview, 2);
    // 광고 1.5배로 더 받은 씨앗은 다음 몫을 깎지 않는다
    expect(g.renew(withAd: true), 3);
    expect(g.seedsTotal, 11);
    expect(g.seedsClaimed, 10);
  });

  test('바구니 등급을 올리면 만들 수 없는 낮은 부탁은 새 부탁으로 바뀐다', () {
    final g = make();
    g.orders
      ..clear()
      ..add(const Order(901, 'bori', Chain.flower, 2, 1));
    g.upgrades[UpgradeType.basketTier] = 4;
    g.level = 40;
    g.coins = 1e12;
    expect(g.buyUpgrade(UpgradeType.basketTier), isTrue);
    expect(g.orders.first.friendId, 'bori');
    expect(g.orders.first.level, greaterThan(g.spawnLevel));
  });

  test('끝없는 강화 값은 바구니 물가를 따라간다', () {
    final g = make();
    final c1 = g.upgradeCost(UpgradeType.income);
    g.upgrades[UpgradeType.basketTier] = 3;
    expect(g.upgradeCost(UpgradeType.income), closeTo(c1 * g.inflation, 1e-6));
    expect(g.inflation, greaterThan(10));
  });

  test('리뷰 수정: 예전 저장 씨앗 이전 · 추천 아이템 상한/재단장 · 날 바뀜 · 끝난 패스', () {
    // 예전 저장 (seedsC 없음): 이번 회차 시작 때까지 번 코인의 몫만 받은 것으로
    final g = make();
    g.seedsTotal = 5;
    g.runStartCoins = Renewal.coinsForSeeds(3);
    g.lifetimeCoins = Renewal.coinsForSeeds(4);
    final j = g.toJson()..remove('seedsC');
    final g2 = make();
    expect(g2.loadJson(j), isTrue);
    expect(g2.seedsClaimed, 3);
    expect(g2.renewSeedsPreview, 1);
    // 추천 아이템은 바구니 +8 까지, 재단장하면 새로
    final g3 = make();
    g3.board[g3.board.indexWhere((x) => x == null)] = Item(
      9002,
      Chain.flower,
      g3.spawnLevel + 20,
    );
    expect(
      g3.featuredItem.$2,
      lessThanOrEqualTo(g3.spawnLevel + Gems.featuredMaxAbove),
    );
    // 보여 준 상품과 다르면 사지 않는다
    g3.gems = 9999;
    final other = (g3.featuredItem.$1, g3.featuredItem.$2 - 1);
    expect(g3.buySurprise(shown: other), isFalse);
    expect(g3.gems, 9999);
    // 이미 끝난 패스가 있는 예전 저장은 '끝났어요' 창을 띄우지 않는다
    final g4 = make();
    g4.passUntil = now.subtract(const Duration(days: 40));
    final j4 = g4.toJson()..remove('passNoticeSeen');
    final g5 = make();
    expect(g5.loadJson(j4), isTrue);
    expect(g5.passNoticeDue, isNull);
  });

  test('다이아 팩: 팩마다 첫 구매는 2배, 두 번째부터는 그대로, 저장돼도 유지', () {
    final g = make();
    final p = Gems.packs[1];
    final g0 = g.gems;
    expect(g.firstPackBonus(p), isTrue);
    expect(g.grantGemPack(p), p.gems * 2);
    expect(g.gems, g0 + p.gems * 2);
    expect(g.firstPackBonus(p), isFalse);
    expect(g.grantGemPack(p), p.gems);
    expect(g.firstPackBonus(Gems.packs[0]), isTrue);
    final g2 = make();
    expect(g2.loadJson(g.toJson()), isTrue);
    expect(g2.firstPackBonus(p), isFalse);
    expect(g2.firstPackBonus(Gems.packs[0]), isTrue);
  });

  test('새싹 정원 패키지: 처음 보여 준 뒤 7일만 상점에, 지나면 사라진다', () {
    final g = make();
    expect(g.starterVisible, isTrue); // 아직 보여 주기 전
    expect(g.showStarterOffer(), isTrue);
    expect(g.starterVisible, isTrue);
    now = now.add(const Duration(days: 6, hours: 23));
    expect(g.starterVisible, isTrue);
    now = now.add(const Duration(hours: 2));
    expect(g.starterVisible, isFalse);
  });

  test('추천 아이템: 사기 전에 보여 준 아이템을 그대로 준다 (무작위 상품 아님)', () {
    final g = make();
    final s = g.spawnLevel;
    expect(g.featuredItem.$2, s + 1);
    expect(g.surpriseGems, Gems.surpriseMinGems);
    g.board[g.board.indexWhere((x) => x == null)] = Item(
      9001,
      Chain.flower,
      s + 7,
    );
    // 이미 정해진 상품은 판이 바뀌어도 그대로 (다시 뽑기 없음)
    final shown = g.featuredItem;
    expect(g.featuredItem, shown);
    g.gems = 999;
    final before = g.board.whereType<Item>().length;
    expect(g.buySurprise(), isTrue);
    expect(g.board.whereType<Item>().length, before + 1);
    expect(
      g.board.whereType<Item>().any(
        (it) => it.id != 9001 && it.chain == shown.$1 && it.level == shown.$2,
      ),
      isTrue,
    );
    // 산 뒤 다음 상품은 판 최고 단계 -2~-1, 값은 그 아이템의 에너지값 × 0.7
    final next = g.featuredItem;
    expect(next.$2, inInclusiveRange(s + 5, s + 6));
    expect(
      g.surpriseGems,
      (pow(2, next.$2 - s) * Gems.surpriseGemPerEnergy).round(),
    );
    // 저장 · 불러오기 뒤에도 같은 상품
    final g2 = make();
    expect(g2.loadJson(g.toJson()), isTrue);
    expect(g2.featuredItem, next);
  });

  test('패키지 패스 끝 알림: 사흘 전 · 하루 전 · 끝남, 한 번씩', () {
    final g = make();
    expect(g.passNoticeDue, isNull);
    g.passUntil = now.add(const Duration(days: 5));
    expect(g.passNoticeDue, isNull);
    g.passUntil = now.add(const Duration(days: 2));
    expect(g.passNoticeDue, 1);
    g.markPassNotice(1);
    expect(g.passNoticeDue, isNull);
    g.passUntil = now.add(const Duration(hours: 5));
    expect(g.passNoticeDue, 2);
    g.markPassNotice(2);
    g.passUntil = now.subtract(const Duration(hours: 1));
    expect(g.passNoticeDue, 3);
    g.markPassNotice(3);
    expect(g.passNoticeDue, isNull);
    g.adFree = true;
    g.passNoticeSeen = 0;
    expect(g.passNoticeDue, isNull); // 구독 중이면 없음
  });

  test('친구 의상: 데려온 친구만, 그 계절에만 다이아로 사고, 산 옷은 무료로 갈아입힌다', () {
    final g = make();
    expect(g.wearOutfit('dubu', 'winter'), StyleResult.notPlaced);
    expect(g.wearOutfit(Friends.starter, 'winter'), StyleResult.noGems);
    g.gems = 999;
    expect(
      g.wearOutfit(Friends.starter, 'picnic'),
      StyleResult.notPlaced,
    ); // 1월엔 봄 옷을 안 판다
    g.gems = Outfits.byId('winter')!.gems;
    expect(g.wearOutfit(Friends.starter, 'winter'), StyleResult.ok);
    expect(g.gems, 0);
    expect(g.outfitOf(Friends.starter), 'winter');
    expect(g.wearOutfit(Friends.starter, null), StyleResult.ok);
    now = DateTime(2026, 7, 1);
    expect(
      g.wearOutfit(Friends.starter, 'winter'),
      StyleResult.ok,
    ); // 계절이 지나도 산 옷은 무료
    final g2 = make();
    expect(g2.loadJson(g.toJson()), isTrue);
    expect(g2.outfitOf(Friends.starter), 'winter');
  });

  test('비눗방울: 판에 하나만, 5분 간격', () {
    final g = make();
    final cells = g.unlockedCells.toList()..sort();
    var bubbles = 0;
    for (var round = 0; round < 400; round++) {
      for (final c in cells) {
        g.board[c] = null;
      }
      g.board[cells[0]] = Item(9000 + round * 2, Chain.flower, 5);
      g.board[cells[1]] = Item(9001 + round * 2, Chain.flower, 5);
      g.move(cells[0], cells[1]);
      final n = g.board.where((it) => it != null && it.isBubble).length;
      expect(n, lessThanOrEqualTo(1));
      bubbles += n;
      now = now.add(const Duration(seconds: 30));
    }
    // 200분 동안 5분 간격이면 많아야 40번
    expect(bubbles, lessThanOrEqualTo(40));
  });

  test('업적 모두 받기: 쌓인 단계를 한 번에', () {
    final g = make();
    g.stats[Stat.merges] = 600;
    g.stats[Stat.spawns] = 300;
    final before = g.claimableAchievements;
    expect(before, greaterThan(0));
    final r = g.claimAllAchievements();
    expect(r.coins, greaterThan(0));
    expect(g.claimableAchievements, 0);
  });

  test('친구별 하루 별 부탁 한도: 4번 뒤엔 그 친구 부탁 없음, 광고 +2, 다음 날 초기화, 첫 구역은 한도 없음', () {
    final g = make();
    final o = g.orders[0];
    expect(g.quotaActive, isFalse);
    expect(g.starOrdersLeft(o.friendId), greaterThan(10));
    g.currentArea = 1;
    expect(g.starOrdersLeft(o.friendId), OrderQuota.perFriend);
    for (var k = 0; k < OrderQuota.perFriend; k++) {
      g.orders[0] = Order(900 + k, o.friendId, Chain.flower, 3, 1);
      g.board[7] = Item(800 + k, Chain.flower, 3);
      final before = g.stars;
      expect(g.deliver(0), isTrue);
      expect(g.stars, greaterThan(before));
    }
    expect(g.starOrdersLeft(o.friendId), 0);
    // 한도를 다 쓴 친구는 오늘 더 부탁하지 않는다
    g.tick(1);
    expect(g.orders.any((x) => x.friendId == o.friendId), isFalse);
    // (예전 저장에 남은 부탁은 전달하면 코인만)
    g.orders.insert(0, Order(950, o.friendId, Chain.flower, 3, 1));
    g.board[7] = Item(850, Chain.flower, 3);
    final stars = g.stars, coins = g.coins;
    expect(g.deliver(0), isTrue);
    expect(g.stars, stars);
    expect(g.coins, greaterThan(coins));
    g.grantQuotaAd(o.friendId);
    expect(g.starOrdersLeft(o.friendId), OrderQuota.perAd);
    g.adFree = true;
    expect(g.starOrdersLeft(o.friendId), OrderQuota.perAd + OrderQuota.pass);
    now = now.add(const Duration(days: 1));
    expect(
      g.starOrdersLeft(o.friendId),
      OrderQuota.perFriend + OrderQuota.pass,
    );
    final g2 = make()..loadJson(g.toJson());
    expect(g2.starOrdersUsed, g.starOrdersUsed);
  });

  test('첫 구역에서도 부탁 20번 뒤부터는 하루 한도 (별을 쓰지 않고 머물며 무한히 모으지 못하게)', () {
    final g = make();
    expect(g.currentArea, 0);
    expect(g.quotaActive, isFalse);
    g.stats[Stat.orders] = OrderQuota.freeOrders;
    expect(g.quotaActive, isTrue);
    final f = g.orders[0].friendId;
    expect(g.starOrdersLeft(f), lessThanOrEqualTo(OrderQuota.perFriend + 1));
  });

  test('꾸밈 세트 (D-046): 고급 세트 = 특별 세트의 40%, 높은 쪽 하나만, 꾸밈 점수 수입', () {
    final g = make();
    g.currentArea = 6;
    final cap0 = g.energyCap, regen0 = g.energyRegenSeconds;
    final off0 = g.offlineCap, luck0 = g.luckyChance, gm0 = g.gardenMultiplier;
    // 앞마당 고급 세트 (8자리 모두 고급)
    for (var i = 0; i < Garden.slotsPerArea; i++) {
      g.ownedStyles.add('0:$i:1');
    }
    expect(g.setTier(0), 1);
    expect(g.energyCap - cap0, 2);
    expect(g.decorScore, closeTo(8 * 0.4, 1e-9));
    // 특별로 다 바꾸면 효과는 특별 하나만 (+5, 겹치지 않음)
    for (var i = 0; i < Garden.slotsPerArea; i++) {
      g.ownedStyles.add('0:$i:2');
    }
    expect(g.setTier(0), 2);
    expect(g.energyCap - cap0, 5);
    expect(g.decorScore, closeTo(8.0, 1e-9));
    // 한 자리라도 빠지면 세트가 아니다
    g.ownedStyles.remove('0:7:2');
    expect(g.setTier(0), 1);
    g.ownedStyles.add('0:7:2');
    // 6구역 특별 세트 전부
    for (var a = 1; a < DecorSets.areas; a++) {
      for (var i = 0; i < Garden.slotsPerArea; i++) {
        g.ownedStyles.add('$a:$i:2');
      }
    }
    expect(g.energyRegenSeconds, lessThan(regen0));
    expect(g.offlineCap - off0, const Duration(minutes: 60));
    expect(g.luckyChance - luck0, closeTo(0.02, 1e-9));
    expect(g.decorScore, 48);
    expect(g.gardenMultiplier - gm0, closeTo(48 * 0.0025, 1e-9));
    // 7번째 구역(순환)은 세지 않는다
    for (var i = 0; i < Garden.slotsPerArea; i++) {
      g.ownedStyles.add('6:$i:2');
    }
    expect(g.decorScore, 48);
    // 가격: 80 + 40 × 구역, 6구역 전부 8,640
    var total = 0;
    for (var a = 0; a < DecorSets.areas; a++) {
      total += Garden.styleGems(a) * Garden.slotsPerArea;
    }
    expect(total, 8640);
  });

  test('일괄 강화 (D-048): 살 수 있는 만큼 한 번에, 25단계마다 ×2 알림, 바구니 등급은 한 단계씩', () {
    final g = make();
    g.level = 99;
    g.coins = 1e12;
    final t = UpgradeType.flowerPower;
    final n = g.affordableUpgrades(t);
    expect(n, greaterThan(25));
    final events = <GameEvent>[];
    final sub = g.events.listen(events.add);
    final before = g.coins;
    expect(g.buyUpgradeMax(t), n);
    expect(g.lv(t), n);
    expect(g.coins, lessThan(before));
    expect(g.canBuyUpgrade(t), isFalse);
    expect(g.bulkUpgradable(UpgradeType.basketTier), isFalse);
    return Future.delayed(Duration.zero, () {
      sub.cancel();
      expect(events.whereType<UpgradeMilestoneEvent>().length, n ~/ 25);
    });
  });

  test('랜드마크 (D-048): 다 꾸민 구역만, 가격은 지금 수입 × 시간, 매력 · 재단장 유지 · 저장', () {
    final g = make();
    g.level = 30;
    expect(g.landmarkOpen(0), isTrue); // 지금 구역에서도
    expect(g.landmarkOpen(1), isFalse);
    g.currentArea = 2;
    expect(g.landmarkOpen(0), isTrue);
    expect(g.landmarkOpen(2), isTrue);
    expect(g.landmarkOpen(3), isFalse);
    expect(
      g.landmarkCost(0),
      closeTo(g.hourlyIncome * Landmarks.hoursAt(0), 1e-6),
    );
    g.coins = 1e15;
    final gm0 = g.gardenMultiplier;
    expect(g.upgradeLandmark(0), isFalse); // 세우기는 별로 먼저
    g.stars = g.landmarkBuildStars(0);
    expect(g.buildLandmark(0), isTrue);
    expect(g.stars, 0);
    expect(g.landmarkLevel(0), 1);
    expect(g.gardenMultiplier, greaterThan(gm0));
    final n = g.upgradeLandmarkMax(0);
    expect(n, greaterThan(5));
    expect(g.landmarkLevel(0), g.landmarkCap); // 플레이어 레벨 − 5 상한
    expect(g.landmarkLevel(0), lessThanOrEqualTo(Landmarks.maxLevel));
    expect(Landmarks.stageOf(1), 1);
    expect(Landmarks.stageOf(10), 2);
    expect(Landmarks.stageOf(29), 3);
    expect(Landmarks.stageOf(50), 4);
    // 재단장해도 남는다
    final lv = g.landmarkLevel(0);
    g.upgrades[UpgradeType.basketTier] = 10;
    g.lifetimeCoins = 1e13;
    if (g.canRenew) g.renew();
    expect(g.landmarkLevel(0), lv);
    final g2 = make()..loadJson(g.toJson());
    expect(g2.landmarkLevel(0), lv);
  });

  test('쪽지: 업데이트 안내(한 번) · 읽음 · 선택 삭제(받은 것만) · 읽은 지 14일 뒤 자동 삭제', () {
    final g = make();
    // 처음 설치: 안내 없음
    expect(g.addUpdateMail(1019, '1.0.4'), isFalse);
    g.level = 10;
    expect(g.addUpdateMail(1020, '1.0.5'), isTrue);
    expect(g.addUpdateMail(1020, '1.0.5'), isFalse);
    final m = g.mail.firstWhere((x) => x.id == 'update-1020');
    expect(m.bodyKey, 'patch.1.0.5');
    expect(m.reward.energy, MailConfig.updateGiftEnergy);
    // 안 받은 보상 쪽지는 지워지지 않는다
    expect(g.deleteMail([m.id]), 0);
    g.claimMail(m.id);
    expect(m.readAt, isNotNull);
    expect(g.deleteMail([m.id]), 1);
    // 보상 없는 쪽지: 열면 읽음
    g.addMail(
      Mail(
        id: 'n1',
        kind: MailKind.notice,
        from: 'team',
        titleKey: '',
        text: 'hi',
        body: 'body',
        at: now,
      ),
    );
    g.readMail('n1');
    expect(g.mail.firstWhere((x) => x.id == 'n1').claimed, isTrue);
    // 14일 뒤 다음 날 첫 tick 에 지워진다
    now = now.add(MailConfig.keepRead + const Duration(days: 1));
    g.tick(1);
    expect(g.mail.any((x) => x.id == 'n1'), isFalse);
    // 저장 · 불러오기
    final g2 = make()..loadJson(g.toJson());
    expect(g2.addUpdateMail(1020, '1.0.5'), isFalse);
  });

  test('부탁 바꾸기: 하루 3번 무료', () {
    final g = make();
    for (var k = 0; k < OrderQuota.freeRerolls; k++) {
      g.refreshOrder(0);
    }
    expect(g.freeRerollsLeft, 0);
    now = now.add(const Duration(days: 1));
    expect(g.freeRerollsLeft, OrderQuota.freeRerolls);
  });

  test('부스트: 다이아로 사면 시간이 쌓이고 60분을 넘지 않는다', () {
    final g = make();
    g.gems = 500;
    expect(g.buyBoost(BoostKind.energy), isTrue);
    expect(g.buyBoost(BoostKind.energy), isTrue);
    expect(g.boostLeft(BoostKind.energy), const Duration(minutes: 30));
    expect(g.buyBoost(BoostKind.energy), isTrue);
    expect(g.buyBoost(BoostKind.energy), isTrue);
    expect(g.boostLeft(BoostKind.energy), Boosts.max);
    expect(g.buyBoost(BoostKind.energy), isFalse);
    final l = g.luckyChance;
    g.grantBoostAd(BoostKind.lucky);
    expect(g.luckyChance, closeTo(l + Boosts.luckyBonus, 1e-9));
    final g2 = make()..loadJson(g.toJson());
    expect(g2.boostLeft(BoostKind.energy), Boosts.max);
  });

  test('보관 칸: 다이아로 영구 해금, 패스는 2칸, 패스가 끝나도 아이템은 꺼낼 수 있다', () {
    final g = make();
    expect(g.isCellOpen(30), isFalse);
    expect(g.canBuyCell(30), isFalse);
    g.gems = 100;
    expect(g.buyVault(33), isTrue);
    expect(g.gems, 70);
    expect(g.isCellOpen(33), isTrue);
    expect(g.vaultCostNext, 60);
    g.adFree = true;
    expect(g.isCellOpen(30), isTrue);
    g.board[30] = Item(700, Chain.flower, 4);
    g.adFree = false;
    expect(g.isCellOpen(30), isFalse);
    expect(g.vaultHeld(30), isTrue);
    final empty = [
      for (final c in GameConfig.startCells)
        if (g.board[c] == null) c,
    ].first;
    expect(g.move(30, empty), MoveResult.moved);
    expect(g.board[30], isNull);
    final g2 = make()..loadJson(g.toJson());
    expect(g2.vaultOwned, {33});
  });

  test('새싹 정원 패키지: 한 번만 지급, 기간제 패스 혜택, 보관 부스트, 한정 의상 · 효과', () {
    final g = make();
    g.currentArea = 1;
    final gems = g.gems, energy = g.energy;
    expect(g.passActive, isFalse);
    expect(g.showStarterOffer(), isTrue);
    expect(g.starterOfferActive, isTrue);
    expect(g.grantStarter(), isTrue);
    expect(g.grantStarter(), isFalse);
    expect(g.gems, gems + Starter.gems);
    expect(g.energy, energy + Starter.energy);
    expect(g.passActive, isTrue);
    expect(g.isCellOpen(30), isTrue);
    final f = g.friends.first;
    expect(g.starOrderLimit(f), OrderQuota.perFriend + OrderQuota.pass);
    expect(g.ownsOutfit(Starter.outfitFriend, Starter.outfit), isTrue);
    expect(g.effectOn, Starter.effect);
    expect(g.useBoostToken(BoostKind.coins), isTrue);
    expect(g.boostLeft(BoostKind.coins), Starter.boostUse); // 30분씩 꺼내 쓴다
    expect(
      g.boostTokens[BoostKind.coins],
      Starter.boosts[BoostKind.coins]!.inMinutes - Starter.boostUse.inMinutes,
    );
    final g2 = make()..loadJson(g.toJson());
    expect(g2.starterBought, isTrue);
    expect(g2.passActive, isTrue);
    expect(
      g2.boostTokens[BoostKind.energy],
      Starter.boosts[BoostKind.energy]!.inMinutes,
    );
    now = now.add(const Duration(days: 31));
    expect(g.passActive, isFalse);
    // 한정 의상은 다이아로 살 수 없다
    final h = make();
    h.gems = 999;
    h.friends.add('bori');
    expect(h.wearOutfit('bori', 'starlight'), StyleResult.notPlaced);
    expect(h.gems, 999);
  });

  test('경제 v3: 옛 버전의 수백만 코인은 레벨 상한으로 줄인다 (별 · 부탁은 다시 곱하지 않음)', () {
    final g = make();
    g.level = 9;
    g.coins = 9167228;
    g.stars = 80;
    final j = g.toJson()..['econ'] = 2;
    final h = make()..loadJson(j);
    expect(h.coins, GameState.coinCapFor(9));
    expect(h.stars, 80);
    final k = make()..loadJson(h.toJson());
    expect(k.coins, h.coins);
  });

  test('시즌 장식: 지금 시즌 것만 다이아로 사고, 세트는 할인, 산 것은 시즌이 지나도 쓴다', () {
    final g = make(); // 1월 = 겨울
    g.placed = {0, 1};
    g.gems = 1000;
    expect(g.seasonStyleNow, 3);
    expect(g.setStyle(0, 0, 4), StyleResult.notPlaced); // 봄은 지금 못 산다
    expect(g.setStyle(0, 0, 3), StyleResult.ok);
    expect(g.gems, 1000 - Garden.seasonGems);
    final slots = List.generate(Garden.slotsPerArea, (i) => i);
    expect(g.buySeasonSet(0, slots), StyleResult.ok);
    expect(g.gems, 1000 - Garden.seasonGems - Garden.seasonSetGems);
    expect(g.styleOf(0, 1), 3);
    expect(g.ownsSeasonSet(0, slots), isTrue);
    now = DateTime(2026, 4, 1);
    expect(g.setStyle(0, 0, 0), StyleResult.ok);
    expect(g.setStyle(0, 0, 3), StyleResult.ok); // 지난 시즌 것도 산 것은 무료로
  });

  test('계절 세트: 8종을 모으면 완성 이벤트 · 정원 매력 +5%, 8자리 모두 입히면 풍경이 켜진다', () async {
    final g = make(); // 1월 = 겨울
    g.placed = {0, 1, 2, 3, 4, 5, 6, 7};
    g.gems = 1000;
    final events = <GameEvent>[];
    g.events.listen(events.add);
    final m0 = g.gardenMultiplier;
    expect(g.landscapeOf(0), isNull);
    final slots = List.generate(Garden.slotsPerArea, (i) => i);
    expect(g.buySeasonSet(0, slots), StyleResult.ok);
    expect(g.seasonSetComplete(0, 3), isTrue);
    expect(g.completedSeasonSets, 1);
    expect(g.gardenMultiplier, closeTo(m0 + Garden.seasonSetBonus, 1e-9));
    expect(g.landscapeOf(0), 3);
    g.setStyle(0, 2, 0); // 하나를 기본으로 바꾸면 풍경은 꺼지고 보너스는 남는다
    expect(g.landscapeOf(0), isNull);
    expect(g.completedSeasonSets, 1);
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<SeasonSetEvent>().length, 1);
  });

  test('구역 바구니는 충전 없이 에너지만 쓴다 (D-031)', () {
    final g = make();
    for (var b = 0; b < Chains.baskets.length; b++) {
      expect(g.basketReady(b), isTrue);
      expect(Chains.basketCharges[b], 0);
    }
  });

  test('정원 재단장: 조건 · 씨앗 · 초기화 · 유지 · 저장', () {
    final g = make();
    g.friends.add('dubu');
    g.placed = {0, 1};
    g.gems = 77;
    g.upgrades[UpgradeType.basketTier] = Renewal.needBasketTier - 1;
    g.lifetimeCoins = 8e12;
    expect(g.canRenew, isFalse); // 바구니 등급 부족
    g.upgrades[UpgradeType.basketTier] = Renewal.needBasketTier;
    g.upgrades[UpgradeType.flowerPower] = 40;
    g.upgrades[UpgradeType.energyRegen] = 5;
    g.board[8] = Item(1, Chain.flower, 12);
    g.coins = 5e9;
    expect(g.canRenew, isTrue);
    expect(g.renewSeedsPreview, 20); // (8e12 / 1e9)^(1/3) = 20
    final got = g.renew();
    expect(got, 20);
    expect(g.renewCount, 2);
    expect(g.seeds, 20);
    expect(g.seedMultiplier, closeTo(3.0, 1e-9));
    // 초기화
    expect(g.board.whereType<Item>(), isEmpty);
    expect(g.coins, 0);
    expect(g.lv(UpgradeType.basketTier), 0);
    expect(g.lv(UpgradeType.flowerPower), 0);
    expect(g.runCoins, 0);
    // 유지
    expect(g.lv(UpgradeType.energyRegen), 5);
    expect(g.placed, {0, 1});
    expect(g.friends, contains('dubu'));
    expect(g.gems, 77);
    // 씨앗 강화: 출발 바구니
    expect(g.buyPerk(SeedPerk.startBasket), isTrue);
    expect(g.seeds, 15);
    expect(g.seedMultiplier, closeTo(3.0, 1e-9)); // 써도 배율은 그대로
    final g2 = make()..loadJson(g.toJson());
    expect(g2.renewCount, 2);
    expect(g2.seedsTotal, 20);
    expect(g2.perkLv(SeedPerk.startBasket), 1);
    expect(g2.energyCap, GameConfig.energyCap);
  });

  test('하루 부탁 단계 보상: 10 · 20 · 30번째에 다이아 2 · 3 · 5, 다음 날 다시', () {
    final g = make();
    g.friends.add('dubu');
    g.currentArea = 1; // 하루 한도가 걸리는 때부터 센다
    final g0 = g.gems;
    final l0 = g.level;
    void deliverOne() {
      g.starOrderLimit('dubu'); // 날짜를 먼저 넘기고
      g.starOrdersUsed['dubu'] = 0; // 별 부탁 한도 안에서
      g.orders = [Order(900 + g.ordersToday, 'dubu', Chain.flower, 3, 1)];
      g.board[8] = Item(990 + g.ordersToday, Chain.flower, 3);
      expect(g.deliver(0), isTrue);
    }

    for (var i = 0; i < 30; i++) {
      deliverOne();
    }
    // 레벨업 다이아는 빼고
    expect(g.gems - g0 - (g.level - l0) * Gems.levelUp, 10);
    expect(g.nextOrderMilestone, isNull);
    now = now.add(const Duration(days: 1));
    expect(g.ordersToday, 0);
    expect(g.nextOrderMilestone, (10, 2));
  });

  test('광고 다이아: 하루 3번 · 3개씩', () {
    final g = make();
    final g0 = g.gems;
    var n = 0;
    while (g.gemAdAvailable) {
      g.recordAd(AdKind.gems);
      g.grantGemAd();
      n++;
    }
    expect(n, 3);
    expect(g.gems - g0, 9);
  });

  test('회차 별 보너스: 2회차부터 회차당 +5%, 최대 +50%', () {
    expect(GameConfig.roundStarBonus(1), 0);
    expect(GameConfig.roundStarBonus(3), closeTo(0.10, 1e-9));
    expect(GameConfig.roundStarBonus(30), 0.5);
  });

  test('알림 조용한 시간: 21시~08시는 다음 08시로', () {
    expect(
      NotifyService.quiet(DateTime(2026, 11, 21, 14, 30)),
      DateTime(2026, 11, 21, 14, 30),
    );
    expect(
      NotifyService.quiet(DateTime(2026, 11, 21, 21, 0)),
      DateTime(2026, 11, 22, 8),
    );
    expect(
      NotifyService.quiet(DateTime(2026, 11, 21, 23, 40)),
      DateTime(2026, 11, 22, 8),
    );
    expect(
      NotifyService.quiet(DateTime(2026, 11, 22, 3, 10)),
      DateTime(2026, 11, 22, 8),
    );
    expect(
      NotifyService.quiet(DateTime(2026, 11, 22, 7, 59)),
      DateTime(2026, 11, 22, 8),
    );
    expect(
      NotifyService.quiet(DateTime(2026, 11, 22, 8, 0)),
      DateTime(2026, 11, 22, 8),
    );
  });

  test('출시 전 점검: 친구당 부탁 하나 · 예전 저장 씨앗 · 시장 최고 단계', () {
    // 한 친구만 별 한도가 남아도 부탁은 그 친구 하나만
    final g = make();
    g.friends.addAll(['dubu', 'kwak']);
    g.currentArea = 1;
    g.starOrderLimit('bori');
    for (final f in ['dubu', 'kwak']) {
      g.starOrdersUsed[f] = 99;
    }
    g.orders.clear();
    g.tick(1);
    final ids = [for (final o in g.orders) o.friendId];
    expect(ids.toSet().length, ids.length, reason: '$ids');

    // 재단장 키가 없는 예전 저장: 지금까지 번 코인은 이번 회차로 치지 않는다
    final j = g.toJson()
      ..remove('runStart')
      ..['life'] = 1e13;
    final g2 = make()..loadJson(j);
    expect(g2.runCoins, 0);

    // 시장 칸 단계는 체인 최고 단계를 넘지 않는다
    final g3 = make();
    g3.level = 60;
    g3.upgrades[UpgradeType.basketTier] = 24;
    for (final o in g3.offers) {
      expect(o.level, lessThanOrEqualTo(Chains.maxLevel(o.chain)));
    }
  });
}

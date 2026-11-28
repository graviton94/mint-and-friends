import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';
import 'package:mint_and_friends/services/billing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'billing_test.dart' show buy;

/// D-110: 다이아 저금통 · 에너지 묶음 · 단계 묶음.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  setUp(() {
    now = DateTime(2026, 11, 28, 12);
    SharedPreferences.setMockInitialValues({});
  });
  GameState make() => GameState(random: Random(4), clock: () => now);

  /// 첫 부탁을 바로 끝낸다 (그 아이템을 판에 놓고 전달).
  bool deliverOne(GameState g) {
    final o = g.orders.first;
    final cell = g.board.indexWhere((x) => x == null);
    g.board[cell] = Item(80000 + cell, o.chain, o.level);
    return g.deliver(0);
  }

  test('저금통: 첫 구역 뒤부터 부탁마다 쌓이고, 가득 차면 멈추고, 깨면 다이아로', () {
    final g = make();
    expect(g.piggyOpen, isFalse);
    expect(deliverOne(g), isTrue);
    expect(g.piggyGems, 0, reason: '첫 구역 전에는 쌓지 않는다');
    g.currentArea = 1;
    expect(deliverOne(g), isTrue);
    expect(g.piggyGems, Piggy.perOrder);
    g.piggyGems = Piggy.cap - 1;
    deliverOne(g);
    expect(g.piggyGems, Piggy.cap);
    expect(g.piggyFull, isTrue);
    deliverOne(g);
    expect(g.piggyGems, Piggy.cap, reason: '가득 차면 더 쌓이지 않는다');
    final before = g.gems;
    expect(g.grantPiggy(), Piggy.cap);
    expect(g.gems, before + Piggy.cap);
    expect(g.piggyGems, 0);
  });

  test('저금통: 깰 수 있게 될 때 · 가득 찰 때 한 번씩 알린다', () async {
    final g = make()..currentArea = 1;
    final got = <PiggyEvent>[];
    final sub = g.events.listen((e) {
      if (e is PiggyEvent) got.add(e);
    });
    g.piggyGems = Piggy.minBreak - 1;
    deliverOne(g);
    deliverOne(g);
    g.piggyGems = Piggy.cap - 1;
    deliverOne(g);
    deliverOne(g);
    await Future<void>.delayed(Duration.zero);
    expect(got.map((e) => e.full), [false, true]);
    await sub.cancel();
  });

  test('에너지 묶음은 하루 한 번', () {
    final g = make()..currentArea = 1;
    expect(g.energyBundleAvailable, isTrue);
    final e0 = g.energy;
    g.grantEnergyBundle();
    expect(g.energy, e0 + EnergyBundle.energy);
    expect(g.energyBundleAvailable, isFalse);
    now = now.add(const Duration(days: 1));
    expect(g.energyBundleAvailable, isTrue);
  });

  test('단계 묶음: 레벨 10 에 24시간 열리고, 같은 단계는 다시 안 열린다', () {
    final g = make();
    g.level = 9;
    g.xp = 0;
    g.debugGainXp(g.xpToNext);
    expect(g.level, 10);
    expect(g.milestoneActive, isTrue);
    expect(g.milestoneKey, 'lv:10');
    now = now.add(const Duration(hours: 25));
    expect(g.milestoneActive, isFalse);
    final j = g.toJson();
    final h = make()..loadJson(j);
    expect(h.milestoneSeen, contains('lv:10'));
  });

  test('저장 · 불러오기에 저금통 · 묶음 상태가 남는다', () {
    final g = make()
      ..piggyGems = 321
      ..piggyNotified = 1;
    g.grantEnergyBundle();
    final h = make()..loadJson(g.toJson());
    expect(h.piggyGems, 321);
    expect(h.piggyNotified, 1);
    expect(h.energyBundleAvailable, isFalse);
  });

  test('결제: 묶음 상품은 onOffer 로 한 번만 지급하고 소비한다', () async {
    final consumed = <String>[];
    final got = <String>[];
    final b = BillingService(
      complete: (_) async {},
      consume: (p) async => consumed.add(p.purchaseID!),
    );
    await b.handlePurchases([
      buy(Offers.piggy, 'p1', PurchaseStatus.purchased),
    ]);
    expect(got, isEmpty, reason: '연결 전에는 기다린다');
    b.onOffer = got.add;
    await Future<void>.delayed(Duration.zero);
    await b.handlePurchases([
      buy(Offers.piggy, 'p1', PurchaseStatus.restored),
      buy(Offers.energy, 'p2', PurchaseStatus.purchased),
    ]);
    expect(got, [Offers.piggy, Offers.energy]);
    expect(consumed.toSet(), {'p1', 'p2'});
  });

  test('특별 디자인 구역 세트: 안 산 자리만 25% 할인, 놓은 장식에 바로 입힌다', () {
    final g = make()
      ..currentArea = 1
      ..gems = 100000;
    g.placed = {0, 1};
    g.ownedStyles.add('1:3:2');
    final missing = g.specialSetMissing(1);
    expect(missing, isNot(contains(3)));
    final cost = g.specialSetGems(1);
    expect(
      cost,
      (Garden.styleGems(1) * missing.length * Garden.setDiscount).round(),
    );
    expect(g.buySpecialSet(1), StyleResult.ok);
    expect(g.gems, 100000 - cost);
    expect(g.specialSetMissing(1), isEmpty);
    expect(g.styleOf(1, 0), 2);
    expect(g.specialSetGems(1), 0);
    expect(g.buySpecialSet(2), StyleResult.notPlaced, reason: '아직 안 연 구역');
  });

  test('의상 세트: 계절에만, 둘 이상일 때만, 산 친구는 빼고 할인', () {
    final g = make()..gems = 100000;
    g.friends.addAll(['dubu', 'kwak', 'nabi']);
    final o = Outfits.all.firstWhere(
      (x) => !x.limited && x.onSaleIn(Season.month),
    );
    g.ownedOutfits.add('dubu:${o.id}');
    bool all(String _) => true;
    final missing = g.outfitSetMissing(o.id, all);
    expect(missing, isNot(contains('dubu')));
    final cost = g.outfitSetGems(o.id, all);
    expect(cost, (o.gems * missing.length * Garden.setDiscount).round());
    expect(g.buyOutfitSet(o.id, all), StyleResult.ok);
    expect(g.gems, 100000 - cost);
    expect(g.outfitSetMissing(o.id, all), isEmpty);
  });
}

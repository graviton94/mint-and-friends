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

  setUp(() => now = DateTime(2026, 1, 1, 12));

  test('바구니는 시간이 지나면 아이템을 자동 생성한다', () {
    final g = make();
    g.tick(g.spawnInterval * 3 + 0.01);
    expect(g.board.whereType<Item>().length, 3);
  });

  test('같은 종류·같은 레벨만 합쳐진다', () {
    final g = make();
    g.board[0] = flower(1, 1);
    g.board[1] = flower(2, 1);
    g.board[2] = snack(3, 2);
    expect(g.move(0, 1), MoveResult.merged);
    expect(g.board[1]!.level, 2);
    // 꽃 Lv2 와 간식 Lv2 는 합쳐지지 않고 자리만 바뀐다
    expect(g.move(1, 2), MoveResult.swapped);
    expect(g.board[1]!.chain, Chain.snack);
    expect(g.move(2, 10), MoveResult.moved);
    expect(g.board[10]!.chain, Chain.flower);
  });

  test('최고 레벨 두 개를 합치면 사라지고 코인을 준다', () {
    final g = make();
    g.board[0] = flower(1, GameConfig.maxLevel);
    g.board[1] = flower(2, GameConfig.maxLevel);
    expect(g.move(0, 1), MoveResult.maxMerged);
    expect(g.board[0], isNull);
    expect(g.board[1], isNull);
    expect(g.coins, greaterThan(0));
  });

  test('새 레벨 발견 시 보너스 이벤트', () async {
    final g = make();
    g.board[0] = snack(1, 1);
    g.board[1] = snack(2, 1);
    final events = <GameEvent>[];
    g.events.listen(events.add);
    g.move(0, 1);
    await Future<void>.delayed(Duration.zero);
    final d = events.whereType<DiscoveryEvent>().single;
    expect(d.chain, Chain.snack);
    expect(d.level, 2);
  });

  test('부탁은 항상 3개 유지되고, 아이템을 전달하면 별·코인·호감도를 얻는다', () {
    final g = make();
    expect(g.orders.length, GameConfig.orderSlots);
    final o = g.orders[0];
    expect(g.canDeliver(0), isFalse);
    g.board[7] = Item(99, o.chain, o.level);
    expect(g.canDeliver(0), isTrue);
    expect(g.deliver(0), isTrue);
    expect(g.board[7], isNull);
    expect(g.stars, greaterThanOrEqualTo(o.stars));
    expect(g.coins, greaterThan(0));
    expect(g.deliveries[o.friendId], 1);
    expect(g.orders.length, GameConfig.orderSlots);
    expect(g.orders[0].id, isNot(o.id));
  });

  test('자동 합치기는 부탁에 필요한 아이템을 남겨둔다', () {
    final g = make();
    final o = g.orders[0];
    g.board[0] = Item(1, o.chain, o.level);
    g.board[1] = Item(2, o.chain, o.level);
    // 부탁 대상만 있으면 합치지 않는다
    final others = g.orders
        .where((x) => x.chain == o.chain && x.level == o.level)
        .length;
    expect(others, greaterThan(0));
    expect(g.autoMergeOnce(), isFalse);
  });

  test('자동 합치기는 가장 낮은 레벨 쌍부터', () {
    final g = make();
    g.orders = [
      for (var i = 0; i < 3; i++) Order(900 + i, 'bori', Chain.flower, 15, 1),
    ];
    g.board[0] = flower(1, 3);
    g.board[1] = flower(2, 3);
    g.board[5] = snack(3, 1);
    g.board[9] = snack(4, 1);
    expect(g.autoMergeOnce(), isTrue);
    expect(g.board[5]!.level, 2);
    expect(g.board[9], isNull);
    expect(g.board[0]!.level, 3);
  });

  test('별로 장식을 설치하고, 특정 장식은 친구를 데려온다', () async {
    final g = make();
    final events = <GameEvent>[];
    g.events.listen(events.add);
    final friendSlot = Garden.areas[0].decor.indexWhere(
      (d) => d.bringsFriend != null,
    );
    final friendId = Garden.areas[0].decor[friendSlot].bringsFriend!;
    expect(g.canPlace(friendSlot), isFalse);
    g.stars = 100;
    expect(g.placeDecor(friendSlot), isTrue);
    expect(g.stars, 100 - Garden.decorCost(0, friendSlot));
    expect(g.friends, contains(friendId));
    expect(g.placeDecor(friendSlot), isFalse); // 이미 설치됨
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<FriendJoinedEvent>().single.friendId, friendId);
  });

  test('구역의 장식 8개를 모두 설치하면 다음 구역으로', () {
    final g = make();
    g.stars = 1000;
    g.board[0] = flower(1, 3);
    final before = g.incomePerSec;
    for (var s = 0; s < Garden.slotsPerArea; s++) {
      expect(g.placeDecor(s), isTrue);
    }
    expect(g.currentArea, 1);
    expect(g.placed, isEmpty);
    expect(g.isPlaced(0, 7), isTrue);
    expect(g.incomePerSec, greaterThan(before * 2));
  });

  test('친구 호감도는 버프가 된다', () {
    final g = make();
    final base = g.spawnInterval;
    g.deliveries['bori'] = Friends.deliveriesPerAffection * 5;
    expect(g.affection('bori'), 5);
    expect(g.spawnInterval, lessThan(base));
  });

  test('친구 탭은 쿨다운이 있다', () {
    final g = make();
    expect(g.tapFriend('bori'), isNotNull);
    expect(g.tapFriend('bori'), isNull);
    now = now.add(GameConfig.friendTapCooldown);
    expect(g.tapFriend('bori'), isNotNull);
    expect(g.tapFriend('dubu'), isNull); // 아직 없는 친구
  });

  test('깜짝 손님은 때가 되면 나타나고, 받으면 사라진다', () {
    final g = make();
    expect(g.visitorVisible, isFalse);
    now = now.add(GameConfig.visitorMinGap);
    g.tick(0.1);
    expect(g.visitorVisible, isTrue);
    final r = g.claimVisitor(withAd: true)!;
    expect(r.stars, GameConfig.visitorAdStars);
    expect(g.visitorVisible, isFalse);
    expect(g.claimVisitor(withAd: false), isNull);
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

  test('부스트는 2배이고 최대 60분까지 누적', () {
    final g = make();
    g.board[0] = flower(1, 2);
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
    g.board[0] = flower(1, 1);
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
    g.board[3] = snack(50, 4);
    g.upgrades[UpgradeType.income] = 5;
    g.currentArea = 1;
    g.placed = {2, 5};
    g.friends.add('kwak');
    g.deliveries['bori'] = 3;
    g.grantBoost();
    final g2 = make();
    expect(g2.load(g.encode()), isTrue);
    expect(g2.coins, g.coins);
    expect(g2.stars, 7);
    expect(g2.board[3]!.chain, Chain.snack);
    expect(g2.board[3]!.level, 4);
    expect(g2.lv(UpgradeType.income), 5);
    expect(g2.currentArea, 1);
    expect(g2.placed, {2, 5});
    expect(g2.friends, containsAll(['bori', 'kwak']));
    expect(g2.deliveries['bori'], 3);
    expect([for (final o in g2.orders) o.id], [for (final o in g.orders) o.id]);
    expect(g2.boostActive, isTrue);
  });

  test('예전 버전 저장은 무시한다', () {
    expect(make().load('{"v":1,"coins":5}'), isFalse);
  });

  test('숫자 포맷', () {
    expect(fmt(999), '999');
    expect(fmt(1500), '1.50K');
    expect(fmt(2.5e6), '2.50M');
    expect(fmt(1e15), '1.00aa');
  });
}

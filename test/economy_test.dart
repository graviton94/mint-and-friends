import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';

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
}

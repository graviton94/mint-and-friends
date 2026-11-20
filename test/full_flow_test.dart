// ignore_for_file: avoid_print
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';

/// 비공개 테스트 전 전체 흐름 검증: 처음 실행 → 6구역까지, 모든 기능을 써 보며
/// 매 세션 저장 · 다시 불러오기를 하고, 값이 망가지거나 막히는 곳이 없는지 확인한다.
void main() {
  test('처음부터 6구역까지: 모든 기능 · 저장/불러오기 · 불변 조건', () {
    final keepChains = Chains.ready;
    final keepAreas = Garden.ready;
    Chains.ready = (_) => true; // 새 체인 · 구역 그림이 다 있다고 보고 끝까지 간다
    Garden.ready = (_) => true;
    addTearDown(() {
      Chains.ready = keepChains;
      Garden.ready = keepAreas;
    });

    final start = DateTime(2026, 3, 1);
    var now = start;
    var g = GameState(random: Random(11), clock: () => now);
    final rng = Random(5);
    final used = <String>{};
    var stuckDays = 0;
    var gAch = 0, gCheck = 0, gMail = 0, gLevel = 0;
    var dayOrders = 0;

    void check(String where) {
      final r = '$where (Lv${g.level}, 구역 ${g.currentArea})';
      expect(g.coins.isFinite && g.coins >= 0, isTrue, reason: '코인 $r');
      expect(g.stars >= 0, isTrue, reason: '별 $r');
      expect(g.gems >= 0, isTrue, reason: '다이아 $r');
      expect(g.energy >= 0, isTrue, reason: '에너지 $r');
      expect(g.level >= 1 && g.xp >= 0, isTrue, reason: '레벨 $r');
      // 부탁은 늘 3개, 단 첫 구역 뒤에는 오늘 별 부탁을 다 쓴 친구가 부탁하지 않아 줄 수 있다
      expect(
        g.orders.length == GameConfig.orderSlots ||
            (g.quotaActive && g.orders.length < GameConfig.orderSlots),
        isTrue,
        reason: '부탁 수 $r',
      );
      for (final o in g.orders) {
        expect(
          !g.quotaActive ||
              g.starOrdersLeft(o.friendId) > 0 ||
              g.canDeliverOrder(o),
          isTrue,
          reason: '한도 끝난 친구 부탁 $r',
        );
      }
      for (var i = 0; i < g.board.length; i++) {
        final it = g.board[i];
        if (it == null) continue;
        expect(g.isCellOpen(i), isTrue, reason: '잠긴 칸에 아이템 $r');
        expect(
          it.level >= 1 && it.level <= Chains.maxLevel(it.chain),
          isTrue,
          reason: '아이템 단계 $r',
        );
      }
      expect(g.incomePerHour.isFinite, isTrue, reason: '수익 $r');
    }

    GameState reload() {
      final raw = g.encode();
      final g2 = GameState(
        random: Random(rng.nextInt(1 << 30)),
        clock: () => now,
      );
      expect(g2.load(raw), isTrue, reason: '불러오기 실패');
      expect(g2.coins, closeTo(g.coins, 0.01));
      expect(g2.stars, g.stars);
      expect(g2.gems, g.gems);
      expect(g2.level, g.level);
      expect(g2.currentArea, g.currentArea);
      expect(g2.placed, g.placed);
      expect(g2.friends, g.friends);
      expect(g2.decorStyle, g.decorStyle);
      expect(g2.outfits, g.outfits);
      expect(g2.checkInCount, g.checkInCount);
      return g2;
    }

    const sessions = [8, 12, 19, 22];
    for (var day = 0; day < 60 && g.currentArea < 6; day++) {
      for (final h in sessions) {
        now = start.add(Duration(days: day, hours: h));
        g = reload();
        final off = g.computeOffline();
        if (off != null) g.grantOffline(off);
        final ci = g.claimCheckIn();
        if (ci != null) {
          used.add('checkIn');
          gCheck += ci.gems;
        }
        if (g.unreadMail > 0) {
          gMail += g.claimAllMail().gems;
          used.add('mail');
        }
        for (final d in Achievements.all) {
          for (Reward? r; (r = g.claimAchievement(d)) != null;) {
            used.add('achievement');
            gAch += r!.gems;
          }
        }
        if (h == sessions.first) dayOrders = g.stat(Stat.orders);
        for (var t = 0; t < 12 * 60; t += 2) {
          now = now.add(const Duration(seconds: 2));
          g.tick(2);
          // 바구니: 열린 바구니를 돌아가며 쓴다
          final open = g.openBaskets;
          if (open.length > 1) {
            g.selectBasket(open[(t ~/ 60) % open.length]);
            used.add('basket');
          }
          final r = g.tapSpawner();
          if (r == TapResult.noEnergy &&
              used.contains('outfit') &&
              g.gems >= g.refillCost + 60 &&
              rng.nextDouble() < 0.02) {
            if (g.buyEnergyRefill()) used.add('refill');
          }
          g.autoMergeOnce();
          for (var i = 0; i < g.orders.length; i++) {
            if (g.deliver(i)) used.add('deliver');
          }
          // 비눗방울: 다이아가 넉넉하면 가끔 연다
          for (var c = 0; c < g.board.length; c++) {
            final it = g.board[c];
            if (it != null && it.isBubble && g.gems > 200) {
              if (g.popBubbleWithGems(c)) used.add('bubbleGems');
            }
          }
          final slots = [
            for (var s = 0; s < Garden.slotsPerArea; s++)
              if (g.canPlace(s)) s,
          ];
          if (slots.isNotEmpty) {
            g.placeDecor(slots.first);
            used.add('decor');
          }
          if (g.boardStuck) {
            var low = -1;
            for (var c = 0; c < g.board.length; c++) {
              final it = g.board[c];
              if (it != null &&
                  !it.isBubble &&
                  (low < 0 || it.level < g.board[low]!.level)) {
                low = c;
              }
            }
            if (low >= 0) {
              if (g.sell(low) != null) {
                used.add('sell');
              }
            }
          }
          // 칸 넓히기 (레벨이 되면)
          if (g.level >= g.nextCellLevel && g.coins >= g.nextCellCost) {
            for (var c = 0; c < GameConfig.cellCount; c++) {
              if (!g.isCellOpen(c)) {
                if (g.buyCell(c)) used.add('cell');
                break;
              }
            }
          }
          if (t % 120 == 0) {
            final ups = UpgradeType.values.where(g.canBuyUpgrade).toList();
            if (ups.isNotEmpty) {
              g.buyUpgrade(ups[rng.nextInt(ups.length)]);
              used.add('upgrade');
            }
          }
        }
        // 세션 끝: 시장 · 디자인 · 의상
        if (g.dailyShopOpen) {
          for (var i = 0; i < g.offers.length; i++) {
            if (g.buyOffer(i) == BuyResult.ok) used.add('market');
          }
        }
        if (g.currentArea > 0 && g.coins > Garden.styleCoins(0, 0) * 3) {
          if (g.setStyle(0, rng.nextInt(Garden.slotsPerArea), 1) ==
              StyleResult.ok) {
            used.add('styleCoins');
          }
        }
        if (g.gems >= 60) {
          final f = g.friends.first;
          for (final o in Outfits.all) {
            if (g.wearOutfit(f, o.id) == StyleResult.ok) {
              used.add('outfit');
              break;
            }
          }
        }
        // 새 기능: 부탁이 다 끝나면 광고로 +2, 다이아 부스트 · 보관 칸 · 시즌 장식
        if (g.ordersDoneToday) {
          g.grantQuotaAd(g.friends.first);
          used.add('quotaAd');
        }
        if (g.gems > 60 && rng.nextDouble() < 0.03) {
          if (g.buyBoost(BoostKind.lucky)) used.add('boost');
        }
        if (g.gems > 70 && g.vaultOwned.length < 2) {
          if (g.buyVault(32 + g.vaultOwned.length)) used.add('vault');
        }
        if (g.gems > 90 && g.currentArea > 0 && g.isPlaced(0, 0)) {
          if (g.setStyle(0, 0, g.seasonStyleNow) == StyleResult.ok) {
            used.add('season');
          }
        }
        if (h == sessions.last && g.stat(Stat.orders) == dayOrders) stuckDays++;
        check('$day일 $h시');
      }
    }
    gLevel = (g.level - 1) * Gems.levelUp;
    print(
      '다이아(${g.stat(Stat.daysPlayed)}일): 업적 $gAch 출석 $gCheck 쪽지 $gMail 레벨업 $gLevel 사용 ${g.stat(Stat.gemsSpent)}',
    );
    // 7구역(순환)까지 넘어가도 문제없다
    expect(g.currentArea, greaterThanOrEqualTo(6), reason: '60일 안에 6구역을 못 끝냄');
    expect(Garden.areaAt(g.currentArea).decor.length, Garden.slotsPerArea);
    expect(g.friends.length, Friends.all.length, reason: '새 친구가 다 오지 않음');
    expect(stuckDays, 0, reason: '하루 종일 부탁을 하나도 못 들어준 날이 있음');
    for (final f in [
      'checkIn',
      'mail',
      'achievement',
      'basket',
      'deliver',
      'decor',
      'upgrade',
      'market',
      'styleCoins',
      'outfit',
      'boost',
      'vault',
      'season',
    ]) {
      expect(used, contains(f), reason: '$f 기능이 한 번도 쓰이지 않음');
    }
  });

  test('막힘 없음: 판이 가득 · 에너지 0 · 부탁 없음에서도 진행할 길이 있다', () {
    var now = DateTime(2026, 1, 1, 12);
    final g = GameState(random: Random(2), clock: () => now);
    final cells = g.unlockedCells.toList()..sort();
    for (var i = 0; i < cells.length; i++) {
      g.board[cells[i]] = Item(1000 + i, Chain.flower, 1 + (i % 3) * 5);
    }
    expect(g.tapSpawner(), TapResult.boardFull);
    // 판이 가득해도 팔 수 있다
    expect(g.sell(cells.first), isNotNull);
    g.energy = 0;
    expect(g.tapSpawner(), TapResult.noEnergy);
    now = now.add(const Duration(minutes: 10));
    g.tick(600);
    expect(g.energy, greaterThan(0)); // 시간이 지나면 다시 찬다
    expect(g.orders.length, GameConfig.orderSlots);
    // 부탁 교체도 늘 된다
    final before = g.orders.first.id;
    g.refreshOrder(0);
    expect(g.orders.first.id, isNot(before));
  });

  test('시계 이상: 시간이 거꾸로 가거나 1년 만에 들어와도 값이 망가지지 않는다', () {
    var now = DateTime(2026, 6, 1, 12);
    final g = GameState(random: Random(4), clock: () => now);
    g.level = 12;
    g.board[g.unlockedCells.first] = Item(1, Chain.flower, 8);
    g.lastSeen = now;
    // 거꾸로 (폰 시계를 되돌림)
    now = DateTime(2026, 5, 1);
    expect(g.computeOffline(), isNull);
    g.tick(1);
    expect(g.energy >= 0 && g.coins >= 0, isTrue);
    expect(g.claimCheckIn(), isNotNull);
    // 1년 뒤
    now = DateTime(2027, 6, 1);
    final off = g.computeOffline();
    if (off != null) {
      expect(off.coins.isFinite && off.coins >= 0, isTrue);
      g.grantOffline(off);
    }
    g.tick(1);
    expect(g.coins.isFinite, isTrue);
    expect(g.energy, lessThanOrEqualTo(GameConfig.energyCap * 3));
    final g2 = GameState(random: Random(4), clock: () => now);
    expect(g2.load(g.encode()), isTrue);
  });

  test('망가진 저장은 무시하고 새로 시작한다', () {
    final g = GameState(random: Random(1));
    g.coins = 77;
    expect(g.load('{"v":3,"coins":"x"}'), isFalse);
    expect(g.load('not json'), isFalse);
    expect(g.coins, 77); // 반쯤 덮어쓰지 않고 원래대로
    expect(g.orders.length, GameConfig.orderSlots);
  });
}

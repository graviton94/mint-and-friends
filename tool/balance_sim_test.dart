// ignore_for_file: avoid_print
// 밸런스 시뮬레이션: flutter test tool/balance_sim_test.dart
//
// 실제 생활 패턴 기준: 하루 4번(08:00, 12:30, 18:30, 22:00) × 12분 플레이, 나머지는 오프라인.
// 플레이 중: 1.5초마다 바구니 탭(에너지 있으면) + 손으로 합치기 1회, 가능한 부탁 전달,
// 별이 되면 가장 싼 장식, 코인은 칸/강화 중 싼 것, 막히면 가장 낮은 아이템 판매.
// 광고(무과금 평균): 에너지 광고는 에너지가 바닥나면 하루 상한까지, 부스트 하루 2회, 코인 주머니 하루 2회.
//
// 목표(장르 벤치마크): Lv5 첫 세션, Lv10 1~2일, Lv20 7~10일, Lv30 30~40일.
import 'dart:math';

import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() => test('sim', sim);

const sessions = [
  Duration(hours: 8),
  Duration(hours: 12, minutes: 30),
  Duration(hours: 18, minutes: 30),
  Duration(hours: 22),
];
const sessionLength = Duration(minutes: 12);
const days = 45;

void sim() {
  final start = DateTime(2026, 3, 1);
  var now = start;
  final g = GameState(random: Random(7), clock: () => now);
  final milestones = <int, String>{};
  final areas = <int, String>{};
  var lastArea = 0, sold = 0, ads = 0;
  var orderCoins = 0.0, achCoins = 0, mailCoins = 0, achStars = 0, mailStars = 0;
  // 인플레이션 기록: 하루 단위 수입 · 지출 · 잔고 · 다음 지출처 가격
  final daily = <String>[];
  var dayStartEarned = 0.0, dayStartCoins = 0.0;
  const report = {1, 2, 3, 5, 7, 10, 14, 21, 30, 45};

  String stamp() {
    final d = now.difference(start).inDays + 1;
    return '${d.toString().padLeft(2)}일차 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  bool watch(AdKind k) {
    if (!g.canWatchAd(k)) return false;
    g.recordAd(k);
    ads++;
    return true;
  }

  for (var day = 0; day < days; day++) {
    var boosts = 0, bags = 0;
    dayStartEarned = g.lifetimeCoins;
    dayStartCoins = g.coins;
    for (final s in sessions) {
      final begin = DateTime(
        start.year,
        start.month,
        start.day,
      ).add(Duration(days: day)).add(s);
      now = begin;
      final off = g.computeOffline();
      if (off != null) g.grantOffline(off);
      var t = 0.0, act = 0.0;
      while (t < sessionLength.inSeconds) {
        now = now.add(const Duration(milliseconds: 500));
        g.tick(0.5);
        t += 0.5;
        act += 0.5;
        if (act >= 1.5) {
          act = 0;
          if (g.tapSpawner() == TapResult.noEnergy &&
              g.isUnlocked(Feature.energyAd) &&
              watch(AdKind.energy)) {
            g.grantEnergyAd();
          }
          g.autoMergeOnce();
        }
        if (boosts < 2 &&
            g.isUnlocked(Feature.boost) &&
            !g.boostActive &&
            watch(AdKind.boost)) {
          g.grantBoost();
          boosts++;
        }
        if (bags < 2 &&
            g.isUnlocked(Feature.coinBag) &&
            g.coinBagReady &&
            watch(AdKind.coinBag)) {
          g.grantCoinBag();
          bags++;
        }
        // 업적 · 쪽지 보상은 생기는 대로 받는다
        for (final d in Achievements.all) {
          while (g.achievementClaimable(d)) {
            final r = g.claimAchievement(d)!;
            achCoins += r.coins;
            achStars += r.stars;
          }
        }
        if (g.unreadMail > 0) {
          final r = g.claimAllMail();
          mailCoins += r.coins;
          mailStars += r.stars;
        }
        for (var i = 0; i < g.orders.length; i++) {
          final o = g.orders[i];
          final c = g.orderCoins(o);
          if (g.deliver(i)) orderCoins += c;
        }
        final slots = [
          for (var x = 0; x < Garden.slotsPerArea; x++)
            if (!g.placed.contains(x)) x,
        ]..sort((a, b) => g.decorCost(a).compareTo(g.decorCost(b)));
        if (slots.isNotEmpty) g.placeDecor(slots.first);
        final ups =
            UpgradeType.values
                .where(
                  (u) =>
                      !g.upgradeMaxed(u) &&
                      !g.upgradeFeatureLocked(u) &&
                      !g.upgradeCapped(u),
                )
                .toList()
              ..sort((a, b) => g.upgradeCost(a).compareTo(g.upgradeCost(b)));
        final locked = [
          for (var i = 0; i < GameConfig.cellCount; i++)
            if (!g.isCellOpen(i)) i,
        ];
        if (locked.isNotEmpty &&
            g.level >= g.nextCellLevel &&
            (ups.isEmpty || g.nextCellCost <= g.upgradeCost(ups.first) * 2)) {
          g.buyCell(locked.first);
        } else if (ups.isNotEmpty) {
          g.buyUpgrade(ups.first);
        }
        if (g.boardStuck) {
          var low = -1;
          for (var i = 0; i < g.board.length; i++) {
            final it = g.board[i];
            if (it != null &&
                !it.isBubble &&
                (low < 0 || it.level < g.board[low]!.level))
              low = i;
          }
          if (low >= 0) {
            g.sell(low);
            sold++;
          }
        }
        for (final m in [5, 10, 15, 20, 25, 30, 35, 40]) {
          if (g.level >= m && !milestones.containsKey(m)) {
            milestones[m] =
                '${stamp()}  칸 ${g.unlockedCells.length}/30  구역 ${g.currentArea}(${g.placed.length}/8)  친구 ${g.friends.length}  코인 ${g.coins.round()}  강화 ${g.upgrades.values.fold(0, (a, b) => a + b)}';
          }
        }
        if (g.currentArea != lastArea) {
          lastArea = g.currentArea;
          areas[lastArea] = '${stamp()}  Lv${g.level}';
        }
      }
    }
    if (report.contains(day + 1)) {
      final earned = g.lifetimeCoins - dayStartEarned;
      final spent = earned - (g.coins - dayStartCoins);
      final ups = UpgradeType.values
          .where((u) => !g.upgradeMaxed(u) && !g.upgradeFeatureLocked(u))
          .map(g.upgradeCost)
          .fold<double>(double.infinity, (a, b) => min(a, b.toDouble()));
      daily.add(
        '${(day + 1).toString().padLeft(2)}일  Lv${g.level.toString().padLeft(2)}  '
        '수입 ${earned.round().toString().padLeft(7)}  지출 ${spent.round().toString().padLeft(7)}  '
        '잔고 ${g.coins.round().toString().padLeft(7)} (= ${(g.coins / max(1, earned)).toStringAsFixed(2)}일치)  '
        '다음 강화 ${ups.isFinite ? ups.round() : '-'} (${ups.isFinite ? (ups / max(1, earned)).toStringAsFixed(2) : '-'}일치)  '
        '다음 칸 ${g.nextCellCost.round()}  시간당 방치 ${g.incomePerHour.round()}',
      );
    }
  }
  print('=== 인플레이션: 하루 수입 · 지출 · 잔고 (잔고는 하루 수입의 1~2일치가 목표) ===');
  daily.forEach(print);
  print(
    '업적 코인 $achCoins  쪽지 코인 $mailCoins  (업적 ${Achievements.all.fold(0, (a, d) => a + g.achievementClaimedTiers(d))}/${Achievements.totalGoals} 단계)',
  );
  print('별 출처: 부탁 ${g.stat(Stat.orderStars)}  업적 $achStars  쪽지 $mailStars');
  print('=== 코인 출처 (45일 합계) ===');
  print(
    '부탁 ${orderCoins.round()}  방치(접속 중+오프라인) ${(g.lifetimeCoins - orderCoins).round()} (기타 보상 포함)',
  );
  print('=== 레벨 도달 (실제 날짜 기준) ===');
  milestones.forEach((k, v) => print('Lv${k.toString().padLeft(2)}: $v'));
  print('=== 구역 완성 ===');
  areas.forEach((k, v) => print('구역 $k: $v'));
  print(
    '=== $days일 뒤: Lv${g.level}, 칸 ${g.unlockedCells.length}, 구역 ${g.currentArea}(${g.placed.length}/8), 별 ${g.stars}, '
    '강화 ${g.upgrades.map((k, v) => MapEntry(k.name, v))}, 판매 $sold, 광고 $ads회(하루 평균 ${(ads / days).toStringAsFixed(1)}) ===',
  );
}

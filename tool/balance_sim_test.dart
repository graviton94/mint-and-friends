// ignore_for_file: avoid_print
// 밸런스 시뮬레이션: flutter test tool/balance_sim_test.dart
// 가상 플레이어: 2초마다 손으로 한 번 합치기(부탁 아이템은 남김), 가능한 부탁은 바로 전달,
// 별이 되면 가장 싼 장식 설치, 코인은 칸/강화 중 가장 싼 것에 사용, 막히면 가장 낮은 아이템 판매.
// "활동 시간" 기준(오프라인 수익, 광고, 깜짝 손님, 비눗방울 제외).
import 'dart:math';

import 'package:bloom_merge/game/config.dart';
import 'package:bloom_merge/game/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() => test('sim', sim);

void sim() {
  var now = DateTime(2026);
  final g = GameState(random: Random(7), clock: () => now);
  var t = 0.0, hand = 0.0, lastArea = 0, lastLevel = 1, delivered = 0, sold = 0;
  const dt = 0.5;
  String m() => '${(t / 60).toStringAsFixed(1).padLeft(6)}분';
  while (t < 3600 * 10 && g.currentArea < 6) {
    now = now.add(const Duration(milliseconds: 500));
    g.tick(dt);
    t += dt;
    hand += dt;
    if (hand >= 2) {
      hand = 0;
      g.autoMergeOnce();
    }
    for (var i = 0; i < g.orders.length; i++) {
      if (g.deliver(i)) delivered++;
    }
    final slots = [
      for (var s = 0; s < Garden.slotsPerArea; s++)
        if (!g.placed.contains(s)) s,
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
    final cellAffordable = locked.isNotEmpty && g.level >= g.nextCellLevel;
    if (cellAffordable &&
        (ups.isEmpty || g.nextCellCost <= g.upgradeCost(ups.first) * 1.5)) {
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
    if (g.level != lastLevel && g.level % 5 == 0) {
      print(
        '${m()}  Lv${g.level}  칸 ${g.unlockedCells.length}/30  구역 ${g.currentArea}(${g.placed.length}/8)',
      );
    }
    lastLevel = g.level;
    if (g.currentArea != lastArea) {
      lastArea = g.currentArea;
      print(
        '${m()}  ★ 구역 $lastArea 완성  Lv${g.level}  부탁 $delivered  판매 $sold  칸 ${g.unlockedCells.length}  친구 ${g.friends.length}  초당 ${g.incomePerSec.toStringAsExponential(1)}  강화 ${g.upgrades.values.toList()}',
      );
    }
  }
  print(
    '종료 ${(t / 60).toStringAsFixed(0)}분, Lv${g.level}, 구역 ${g.currentArea} 장식 ${g.placed.length}/8, 별 ${g.stars}, 칸 ${g.unlockedCells.length}, 판매 $sold',
  );
}

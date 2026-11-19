// ignore_for_file: avoid_print
// 밸런스 시뮬레이션: flutter test tool/balance_sim_test.dart
// 가상 플레이어: 2초마다 손으로 한 번 합치기(부탁 아이템은 남김), 가능한 부탁은 바로 전달,
// 별이 되면 가장 싼 장식 설치, 코인은 가장 싼 강화에 사용.
// "활동 시간" 기준(오프라인 수익, 광고, 깜짝 손님 제외).
import 'dart:math';

import 'package:bloom_merge/game/config.dart';
import 'package:bloom_merge/game/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() => test('sim', sim);

void sim() {
  var now = DateTime(2026);
  final g = GameState(random: Random(7), clock: () => now);
  var t = 0.0, hand = 0.0, lastArea = 0, delivered = 0;
  const dt = 0.5;
  while (t < 3600 * 12 && g.currentArea < 6) {
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
    final ups = UpgradeType.values.where((u) => !g.upgradeMaxed(u)).toList()
      ..sort((a, b) => g.upgradeCost(a).compareTo(g.upgradeCost(b)));
    if (ups.isNotEmpty) g.buyUpgrade(ups.first);
    // 보드가 막히면(부탁 아이템이 안 나옴) 가장 낮은 아이템을 버리는 대신 교체는 안 함 → 막힘 감지용 출력
    if (g.currentArea != lastArea) {
      lastArea = g.currentArea;
      print(
        '${(t / 60).toStringAsFixed(1).padLeft(6)}분  구역 $lastArea 완성  부탁 $delivered건  별 ${g.stars}  친구 ${g.friends.length}  최고 꽃Lv${g.highest[Chain.flower]} 간식Lv${g.highest[Chain.snack]}  초당 ${g.incomePerSec.toStringAsExponential(1)}  강화 ${g.upgrades.values.toList()}',
      );
    }
  }
  print(
    '종료 ${(t / 60).toStringAsFixed(0)}분, 구역 ${g.currentArea} 장식 ${g.placed.length}/8, 부탁 $delivered, 보드 ${g.board.whereType<Item>().length}/30, 부탁 ${g.orders.map((o) => '${o.chain.name}${o.level}').join(',')}',
  );
}

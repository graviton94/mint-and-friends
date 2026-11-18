// ignore_for_file: avoid_print
// 밸런스 시뮬레이션: flutter test tool/balance_sim_test.dart
// 가상 플레이어: 2초마다 손으로 한 번 합치기, 정원 작업 우선 구매, 남는 돈으로 가장 싼 강화.
// "활동 시간" 기준(오프라인 수익 제외). 광고 부스트 미사용.
import 'dart:math';
import 'package:bloom_merge/game/config.dart';
import 'package:bloom_merge/game/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() => test('sim', sim);

void sim() {
  var now = DateTime(2026);
  final g = GameState(random: Random(7), clock: () => now);
  var t = 0.0, hand = 0.0, last = 0;
  const dt = 0.5;
  while (t < 3600 * 12) {
    now = now.add(const Duration(milliseconds: 500));
    g.tick(dt);
    t += dt;
    hand += dt;
    if (hand >= 2) { hand = 0; g.autoMergeOnce(); }
    g.buyGardenTask();
    final ups = UpgradeType.values.where((u) => !g.upgradeMaxed(u)).toList()
      ..sort((a, b) => g.upgradeCost(a).compareTo(g.upgradeCost(b)));
    if (ups.isNotEmpty && g.upgradeCost(ups.first) < g.nextTaskCost * 0.5) g.buyUpgrade(ups.first);
    if (g.gardenProgress != last) {
      last = g.gardenProgress;
      if (last % 5 == 0) {
        print('${(t / 60).toStringAsFixed(1).padLeft(6)}분  영역 ${last ~/ 5} 완료  최고 Lv${g.highestLevel}  초당 ${g.incomePerSec.toStringAsExponential(2)}  강화 ${g.upgrades.values.toList()}');
      }
    }
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';

/// CI 전용 (save-check 워크플로): 실제 테스터 저장을 지금 코드로 불러 본다. 숫자만 출력.
void main() {
  test('실제 저장 불러오기 · 단계 이동', () {
    final path = Platform.environment['SAVES'];
    if (path == null) return;
    final saves = (jsonDecode(File(path).readAsStringSync()) as List)
        .cast<String>();
    final now = DateTime.now();
    var ok = 0, migrated = 0, shiftedItems = 0, valueMismatch = 0, failed = 0;
    for (final raw in saves) {
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final wasMigrated = GameState.chainLevelsMigrated(j);
      // 옮기기 전 가치 (예전 공식: 보정 없이)
      double oldValue = 0;
      var lateItems = 0;
      for (final e in (j['board'] as List? ?? const [])) {
        if (e is! Map) continue;
        final c = Chain.values[(e['c'] as num).toInt()];
        final l = (e['l'] as num).toInt();
        oldValue +=
            GameConfig.chainValue[c]! * pow(GameConfig.valueGrowth, l - 1);
        if (Chains.levelOffset(c) > 0) lateItems++;
      }
      final g = GameState(random: Random(1), clock: () => now);
      if (!g.loadJson(j)) {
        failed++;
        continue;
      }
      ok++;
      if (!wasMigrated) migrated++;
      shiftedItems += lateItems;
      double newValue = 0;
      for (final it in g.board) {
        if (it != null) newValue += GameConfig.valueOf(it.chain, it.level);
      }
      // 낮은 찻잎(예전 1~3단계)은 1단계로 모여 조금 오를 수 있다: 줄어들면 문제
      if (!wasMigrated && newValue + 1e-6 < oldValue * 0.999) valueMismatch++;
      // 다시 저장 · 불러오기 해도 그대로
      final g2 = GameState(random: Random(1), clock: () => now);
      expect(g2.loadJson(g.toJson()), isTrue);
      expect(
        [for (final it in g2.board) it?.level],
        [for (final it in g.board) it?.level],
      );
    }
    // ignore: avoid_print
    print(
      'saves=${saves.length} ok=$ok failed=$failed migrated=$migrated '
      'teaStardustOnBoard=$shiftedItems valueDropped=$valueMismatch',
    );
    expect(failed, 0);
    expect(valueMismatch, 0);
  });
}

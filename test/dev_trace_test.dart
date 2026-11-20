import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/game_state.dart';

void main() {
  test('성장 로그: 생성 · 합치기 · 행동이 기록되고 판 상태가 30칸으로 찍힌다', () {
    final lines = <String>[];
    GameState.tracer = (t, d) => lines.add('$t,$d');
    addTearDown(() => GameState.tracer = null);
    final g = GameState(random: Random(1), clock: () => DateTime(2026, 1, 1));
    for (var i = 0; i < 6; i++) {
      g.tapSpawner();
    }
    expect(lines.where((l) => l.startsWith('spawn,')).length, 6);
    // 같은 아이템 둘을 찾아 합친다
    final cells = [
      for (var i = 0; i < g.board.length; i++)
        if (g.board[i] != null) i,
    ];
    outer:
    for (final a in cells) {
      for (final b in cells) {
        final x = g.board[a], y = g.board[b];
        if (a != b &&
            x != null &&
            y != null &&
            x.chain == y.chain &&
            x.level == y.level) {
          g.move(a, b);
          break outer;
        }
      }
    }
    expect(lines.any((l) => l.startsWith('merge,')), isTrue);
    expect(lines.any((l) => l.startsWith('act,spawns')), isFalse);
    expect(g.boardCode().split(' ').length, g.board.length);
  });
}

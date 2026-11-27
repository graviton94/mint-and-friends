import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mint_and_friends/art/art.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';
import 'package:mint_and_friends/i18n/l10n.dart';
import 'package:mint_and_friends/ui/board/board_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 판 안정성 (D-100): 시간이 흐르거나 · 자동 진행 표시가 생기고 없어지거나 · 다른 칸이 합쳐져도
/// 관계없는 아이템은 새로 만들어지지 않아야 한다 (새로 만들어지면 '뿅'이 다시 나오고 자리가 튄다).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('관계없는 아이템은 그대로 (뿅 다시 안 함)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await L10n.instance.init();
      await Art.init();
    });
    var now = DateTime(2026, 1, 1, 12);
    final g = GameState(random: Random(1), clock: () => now);
    g.level = 30;
    g.energy = 100;
    g.upgrades[UpgradeType.autoMerge] = 60;
    g.upgrades[UpgradeType.autoSpawn] = 60;
    g.autoSpawnOn = true;
    g.highest[Chain.flower] = 10;
    g.highest[Chain.snack] = 10;
    g.board.fillRange(0, g.board.length, null);
    final open = GameConfig.startCells.toList()..sort();
    g.board[open[0]] = Item(9001, Chain.flower, 2);
    g.board[open[1]] = Item(9002, Chain.flower, 2);
    final bystander = Item(9003, Chain.snack, 5); // 짝이 없어 자동 합치기 대상이 아님
    g.board[open[5]] = bystander;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ListenableBuilder(
              listenable: g,
              builder: (_, _) => BoardView(
                game: g,
                selected: null,
                onSelect: (_) {},
                onLockedTap: (_) {},
                onBubbleTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    Element tileOf(Item it) => tester.element(
      find.byWidgetPredicate((w) => w is ItemTile && w.item.id == it.id),
    );
    final before = tileOf(bystander);

    // 자동 진행이 차오르고 · 흔들리고 · 합쳐지고 · 놓이는 동안 (표시 칸이 생기고 없어진다)
    for (var i = 0; i < 400; i++) {
      now = now.add(const Duration(milliseconds: 100));
      g.tick(0.1);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(g.board[open[0]]?.level ?? 0, greaterThanOrEqualTo(0));
    expect(
      identical(tileOf(bystander), before),
      isTrue,
      reason: '관계없는 아이템이 새로 만들어졌다',
    );
    // 아이템이 있는 칸 수 = 화면의 아이템 수 (빠지거나 겹치지 않음)
    final onBoard = g.board.where((e) => e != null).length;
    expect(find.byType(ItemTile).evaluate().length, onBoard);
    await tester.pumpWidget(const SizedBox());
  });

  test('저장의 다음 번호가 낮아도 아이템 번호가 겹치지 않는다 (D-100)', () {
    final now = DateTime(2026, 1, 1, 12);
    final g = GameState(random: Random(1), clock: () => now);
    final open = GameConfig.startCells.toList()..sort();
    g.board.fillRange(0, g.board.length, null);
    g.board[open[0]] = Item(5, Chain.flower, 2);
    g.board[open[1]] = Item(5, Chain.flower, 3); // 겹친 번호
    final j = g.toJson()..['nextId'] = 1;
    final g2 = GameState(random: Random(1), clock: () => now)..loadJson(j);
    g2.energy = 100;
    g2.tapSpawner();
    final ids = [
      for (final it in g2.board)
        if (it != null) it.id,
    ];
    expect(ids.toSet().length, ids.length);
  });
}

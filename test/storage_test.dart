import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';

void main() {
  GameState fresh() {
    final g = GameState();
    g.level = Leveling.unlockLevel[Feature.storage]!;
    return g;
  }

  int firstItemCell(GameState g) {
    if (g.board.every((it) => it == null)) g.tapSpawner();
    return g.board.indexWhere((it) => it != null && !it.isBubble);
  }

  test('보관함은 해금 레벨 전에는 쓸 수 없다', () {
    final g = GameState();
    g.level = 1;
    g.tapSpawner();
    expect(g.canStore(firstItemCell(g)), isFalse);
  });

  test('보관하고 꺼내면 같은 아이템이 판으로 돌아온다', () {
    final g = fresh();
    final cell = firstItemCell(g);
    final it = g.board[cell]!;
    final income = g.incomePerSec;
    expect(g.store(cell), isTrue);
    expect(g.board[cell], isNull);
    expect(g.storageUsed, 1);
    expect(g.incomePerSec, lessThan(income)); // 보관 중엔 수익 없음
    final back = g.retrieve(0);
    expect(back, isNotNull);
    expect(g.board[back!], same(it));
    expect(g.storageUsed, 0);
  });

  test('가득 차면 보관 실패, 칸을 사면 늘어나고 비용이 오른다', () {
    final g = fresh();
    for (var i = 0; i < Storage.startSlots; i++) {
      g.tapSpawner();
      expect(g.store(firstItemCell(g)), isTrue);
    }
    g.tapSpawner();
    final cell = firstItemCell(g);
    expect(g.storageFull, isTrue);
    expect(g.store(cell), isFalse);
    final cost = g.nextStorageCost;
    g.coins = cost * 10;
    expect(g.buyStorageSlot(), isTrue);
    expect(g.storage.length, Storage.startSlots + 1);
    expect(g.nextStorageCost, greaterThan(cost));
    expect(g.store(cell), isTrue);
  });

  test('예전 보관함은 불러올 때 판으로 꺼내고, 산 칸 수만큼 보관 칸을 무료로 연다 (D-017)', () {
    final g = fresh();
    g.coins = 1e9;
    g.buyStorageSlot();
    final cell = firstItemCell(g);
    final it = g.board[cell]!;
    g.store(cell);
    final h = GameState()..load(g.encode());
    expect(h.storageUsed, 0);
    expect(h.storage.length, Storage.startSlots);
    expect(h.vaultOwned.length, 1);
    expect(
      h.board.any((x) => x != null && x.id == it.id && x.level == it.level),
      isTrue,
    );
  });
}

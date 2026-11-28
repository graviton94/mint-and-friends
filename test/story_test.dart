import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';

/// D-119: 정원사 일기(구역 완성마다 한 장) · 친구 사연 편지(레벨 3 · 5 · 10).
void main() {
  GameState make() =>
      GameState(random: Random(1), clock: () => DateTime(2026, 11, 28, 12));

  test('구역을 완성하면 그 구역의 일기 한 장 + 다이아, 같은 장은 한 번만', () {
    final g = make()
      ..level = 60
      ..stars = 1 << 30;
    final gems0 = g.gems;
    for (var i = 0; i < Garden.slotsPerArea; i++) {
      expect(g.placeDecor(i), isTrue, reason: 'slot $i');
    }
    expect(g.currentArea, 1);
    expect(g.diaryFound, {0});
    expect(g.gems, greaterThanOrEqualTo(gems0 + GameState.diaryGems(0)));
  });

  test('이야기 전에 이미 끝낸 구역은 불러올 때 일기장에 채워 둔다', () {
    final g = make()..currentArea = 3;
    final h = make()..loadJson(g.toJson());
    expect(h.diaryFound, {0, 1, 2});
  });

  test('친구 레벨 3 · 5 · 10 에 사연 편지', () {
    final g = make()
      ..coins = 1e30
      ..level = 60;
    g.friends.add('dubu');
    g.deliveries['dubu'] = 10000;
    var n = 0;
    while (g.friendLevel('dubu') < 10 && g.levelFriend('dubu')) {
      n++;
      if (n > 20) break;
    }
    final ids = g.mail.map((m) => m.id).toSet();
    expect(ids, containsAll(['story-dubu-3', 'story-dubu-5', 'story-dubu-10']));
    expect(ids.where((x) => x.startsWith('story-')).length, 3);
  });
}

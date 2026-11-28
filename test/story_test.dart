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
    final e0 = g.energy;
    for (var i = 0; i < Garden.slotsPerArea; i++) {
      expect(g.placeDecor(i), isTrue, reason: 'slot $i');
    }
    expect(g.currentArea, 1);
    expect(g.diaryFound, {0});
    expect(
      g.energy,
      greaterThanOrEqualTo(e0 + GameState.diaryReward(0).energy),
    );
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

  test('에피소드: 같은 친구 부탁 3번이면 완성 + 에너지, 친구마다 한 번', () {
    final g = make();
    g.episodeFriend = 'kwak';
    final e0 = g.energy;
    void deliverFrom(String f) {
      // 그 친구의 부탁을 하나 만들어 바로 전한다
      final o = g.orders.first;
      g.orders[0] = Order(o.id, f, o.chain, o.level, o.stars);
      final cell = g.board.indexWhere((x) => x == null);
      g.board[cell] = Item(90000 + cell, o.chain, o.level);
      expect(g.deliver(0), isTrue);
    }

    deliverFrom('nabi');
    expect(g.episodeStep, 0, reason: '다른 친구 부탁은 세지 않는다');
    deliverFrom('kwak');
    deliverFrom('kwak');
    expect(g.episodeStep, 2);
    deliverFrom('kwak');
    expect(g.episodeFriend, isNull);
    expect(g.episodesDone, contains('kwak'));
    expect(g.energy, greaterThanOrEqualTo(e0 + GameState.episodeReward.energy));
  });

  test('일기 마지막 장을 찾으면 정원사의 예고 편지', () {
    final g = make()..currentArea = 5;
    g.diaryFound.addAll([0, 1, 2, 3, 4]);
    g.level = 99;
    g.stars = 1 << 30;
    for (var i = 0; i < Garden.slotsPerArea; i++) {
      g.placeDecor(i);
    }
    expect(g.diaryFound, contains(5));
    expect(g.mail.any((m) => m.id == 'story-teaser'), isTrue);
  });
}

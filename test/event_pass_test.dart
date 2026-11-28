import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/event_pass.dart';
import 'package:mint_and_friends/game/game_state.dart';

/// D-112: 월간 이벤트 — 하루 퀘스트 3개 = 한 칸, 하루 한 칸, 무료 · 패스 보상, 달이 바뀌면 처음부터.
void main() {
  late DateTime now;
  setUp(() {
    now = DateTime(2027, 1, 3, 10);
    EventPass.ready = (_) => true;
    EventPass.debugEvent = null;
  });
  GameState make() => GameState(random: Random(2), clock: () => now);

  void doQuests(GameState g, List<QuestKind> ks) {
    for (final k in ks) {
      for (var i = 0; i < EventPass.target[k]!; i++) {
        switch (k) {
          case QuestKind.ad:
            g.recordAd(AdKind.energy);
          default:
            g.debugQuest(k);
        }
      }
    }
  }

  test('1월엔 온천 이벤트, 3개 끝내면 한 칸, 같은 날은 더 안 오른다', () {
    final g = make();
    expect(g.currentEvent?.id, 'onsen');
    doQuests(g, [QuestKind.basket, QuestKind.merge]);
    expect(g.eventStep, 0);
    doQuests(g, [QuestKind.pat]);
    expect(g.eventStep, 1);
    doQuests(g, [QuestKind.ad]);
    expect(g.eventStep, 1, reason: '하루 한 칸');
    now = now.add(const Duration(days: 1));
    expect(g.questsDone, 0, reason: '날이 바뀌면 퀘스트 새로');
    doQuests(g, [QuestKind.basket, QuestKind.merge, QuestKind.ad]);
    expect(g.eventStep, 2);
  });

  test('정원 패스는 광고 퀘스트가 저절로', () {
    final g = make()..adFree = true;
    expect(g.questDone(QuestKind.ad), isTrue);
  });

  test('무료 보상은 누구나, 패스 보상은 패스가 있어야 · 달 중간에 사도 지난 칸까지', () {
    final g = make();
    g.currentEvent;
    g.eventStep = 5;
    final gems0 = g.gems;
    expect(g.claimEventStep(4, premium: false), isNotNull);
    expect(g.gems, gems0 + EventPass.free[4].amount);
    expect(g.claimEventStep(4, premium: false), isNull, reason: '두 번 못 받음');
    expect(g.claimEventStep(0, premium: true), isNull, reason: '패스 없음');
    expect(g.claimEventStep(5, premium: false), isNull, reason: '아직 안 오른 칸');
    g.grantEventPass();
    expect(g.hasEventPass, isTrue);
    expect(g.eventClaimable, 4 + 5);
    expect(g.claimEventStep(0, premium: true), isNotNull);
  });

  test('최종 보상: 패스 = 친구 의상, 무료 = 기념품 (정원 매력 +)', () {
    final g = make();
    final def = g.currentEvent!;
    g.eventStep = 20;
    g.grantEventPass();
    final m0 = g.gardenMultiplier;
    g.claimEventStep(19, premium: false);
    g.claimEventStep(19, premium: true);
    expect(g.souvenirs, contains(def.souvenir));
    expect(g.gardenMultiplier, closeTo(m0 + EventPass.souvenirCharm, 1e-9));
    expect(g.ownsOutfit(def.friend, def.outfit), isTrue);
  });

  test('달이 바뀌면 새 이벤트로 처음부터, 저장해도 남는다', () {
    final g = make();
    g.currentEvent;
    g.eventStep = 7;
    g.grantEventPass();
    final h = make()..loadJson(g.toJson());
    expect(h.eventStep, 7);
    expect(h.hasEventPass, isTrue);
    now = DateTime(2027, 2, 1, 9);
    expect(h.currentEvent?.id, 'cocoa');
    expect(h.eventStep, 0);
    expect(h.hasEventPass, isFalse);
  });

  test('그림이 없는 달은 열지 않는다', () {
    EventPass.ready = (_) => false;
    expect(make().currentEvent, isNull);
  });

  test('이벤트가 끝난 뒤 패스 결제가 오면 다이아로', () {
    now = DateTime(2026, 12, 5);
    final g = make();
    final g0 = g.gems;
    g.grantEventPass();
    expect(g.gems, g0 + 430);
  });
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/game_state.dart';

void main() {
  late DateTime now;
  GameState make() => GameState(random: Random(3), clock: () => now);
  AchievementDef ach(String id) =>
      Achievements.all.firstWhere((d) => d.id == id);

  setUp(() => now = DateTime(2026, 1, 1, 12));

  test('업적 정의: id 중복 없음, 단계는 오름차순, stat 업적은 stat 이 있다', () {
    final ids = <String>{};
    for (final d in Achievements.all) {
      expect(ids.add(d.id), isTrue, reason: d.id);
      for (var i = 1; i < d.tiers.length; i++) {
        expect(d.tiers[i], greaterThan(d.tiers[i - 1]), reason: d.id);
      }
      if (d.kind == AchKind.stat) expect(d.stat, isNotNull, reason: d.id);
    }
    expect(Achievements.totalGoals, greaterThan(150));
  });

  test('업적 보상은 단계마다 커진다', () {
    final d = ach('merges');
    for (var t = 1; t < d.tiers.length; t++) {
      expect(d.rewardFor(t).coins, greaterThan(d.rewardFor(t - 1).coins));
    }
    expect(d.rewardFor(0).stars, 0);
    expect(d.rewardFor(2).stars, greaterThan(0));
  });

  test('업적: 도달한 단계만 차례로 받는다', () {
    final g = make();
    final d = ach('merges');
    expect(g.achievementClaimable(d), isFalse);
    expect(g.claimAchievement(d), isNull);
    g.stats[Stat.merges] = 60; // 10, 50 두 단계 도달
    expect(g.achievementReached(d), 2);
    final c0 = g.coins;
    final r1 = g.claimAchievement(d)!;
    expect(g.coins, c0 + r1.coins);
    expect(g.claimAchievement(d), isNotNull);
    expect(g.claimAchievement(d), isNull);
    expect(g.achievementClaimedTiers(d), 2);
  });

  test('레벨 업적은 현재 레벨을 센다', () {
    final g = make();
    g.level = 12;
    expect(g.achievementReached(ach('level')), 2);
  });

  test('첫 실행에는 환영 쪽지가 한 통 온다', () {
    final g = make();
    expect(g.unreadMail, 1);
    final e0 = g.energy;
    final r = g.claimMail('welcome')!;
    expect(g.energy, e0 + r.energy);
    expect(g.unreadMail, 0);
    expect(g.claimMail('welcome'), isNull);
    expect(g.stat(Stat.mailClaimed), 1);
  });

  test('친구 깜짝 선물: 친구 2명부터, 몇 시간마다, 안 받은 건 최대 3통', () {
    final g = make();
    g.claimAllMail();
    now = now.add(const Duration(hours: 7));
    g.tick(1);
    expect(g.unreadMail, 0); // 친구가 1명뿐
    g.friends.add('dubu');
    for (var i = 0; i < 10; i++) {
      now = now.add(const Duration(hours: 7));
      g.tick(1);
    }
    expect(g.unreadMail, 3);
    final r = g.claimAllMail();
    expect(r.isEmpty, isFalse);
    expect(g.unreadMail, 0);
  });

  test('플레이한 날 수는 날짜가 바뀔 때만 오른다', () {
    final g = make();
    g.tick(1);
    final d = g.stat(Stat.daysPlayed);
    g.tick(1);
    expect(g.stat(Stat.daysPlayed), d);
    now = now.add(const Duration(days: 1));
    g.tick(1);
    expect(g.stat(Stat.daysPlayed), d + 1);
  });

  test('업적 · 쪽지 · 기록은 저장 후에도 남는다', () {
    final g = make();
    g.stats[Stat.merges] = 60;
    g.claimAchievement(ach('merges'));
    g.claimMail('welcome');
    final g2 = make();
    expect(g2.load(g.encode()), isTrue);
    expect(g2.stat(Stat.merges), 60);
    expect(g2.achievementClaimedTiers(ach('merges')), 1);
    expect(g2.unreadMail, 0);
    expect(g2.mail.length, 1);
  });

  test('합치기 · 바구니 탭이 기록에 쌓인다', () {
    final g = make();
    g.tapSpawner();
    g.tapSpawner();
    expect(g.stat(Stat.spawns), 2);
    expect(g.stat(Stat.energySpent), 2);
  });
}

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mint_and_friends/ui/social_ui.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';
import 'package:mint_and_friends/services/social_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 메모리 안에서만 도는 가짜 서버 (sendGift 의 하루 한 번 규칙도 흉내 낸다).
class FakeBackend implements SocialBackend {
  bool online = true;
  bool hang = false;
  final profiles = <String, Map<String, dynamic>>{};
  final codes = <String, String>{};
  final links =
      <String, Map<String, String?>>{}; // uid → friendUid → lastGiftSentDay
  final inboxes = <String, List<InboxItem>>{};
  final gifts = <String>{};
  final noticeList = <Notice>[];
  int profileWrites = 0;
  int deleteCalls = 0;

  Future<T> _go<T>(T Function() f) async {
    if (hang) await Completer<void>().future;
    if (!online) throw SocialException('offline');
    return f();
  }

  @override
  bool get available => true;
  @override
  Future<Map<String, dynamic>?> getProfile(String uid) =>
      _go(() => profiles[uid]);
  @override
  Future<void> putProfile(String uid, Map<String, dynamic> data) => _go(() {
    profileWrites++;
    profiles[uid] = data;
  });
  @override
  Future<bool> reserveCode(String code, String uid) => _go(() {
    final owner = codes[code];
    if (owner != null) return owner == uid;
    codes[code] = uid;
    return true;
  });
  @override
  Future<String?> lookupCode(String code) => _go(() => codes[code]);
  @override
  Future<List<FriendLink>> friendLinks(String uid) => _go(
    () => [
      for (final e in (links[uid] ?? {}).entries)
        FriendLink(e.key, lastGiftSentDay: e.value),
    ],
  );
  @override
  Future<void> addFriendLink(String uid, String friendUid) =>
      _go(() => (links[uid] ??= {})[friendUid] = null);
  final List<Map<String, dynamic>> reports = [];
  @override
  Future<void> report(Map<String, dynamic> data) =>
      _go(() => reports.add(data));
  @override
  Future<void> removeFriendLink(String uid, String friendUid) =>
      _go(() => links[uid]?.remove(friendUid));
  @override
  Future<Map<String, Map<String, dynamic>>> getProfiles(List<String> uids) =>
      _go(
        () => {
          for (final u in uids)
            if (profiles[u] != null) u: profiles[u]!,
        },
      );
  @override
  Future<List<InboxItem>> inbox(String uid) => _go(() => [...?inboxes[uid]]);
  @override
  Future<void> deleteInbox(String uid, List<String> ids) => _go(() {
    deleteCalls++;
    inboxes[uid]?.removeWhere((i) => ids.contains(i.id));
  });
  @override
  Future<List<Notice>> notices(DateTime now) => _go(() => noticeList);

  String? sender;
  @override
  Future<void> sendGift(String to, String day) => _go(() {
    final from = sender!;
    if (!(links[from]?.containsKey(to) ?? false)) {
      throw SocialException('notFriend');
    }
    if (!gifts.add('${from}_${to}_$day')) throw SocialException('already');
    links[from]![to] = day;
    (inboxes[to] ??= []).add(
      InboxItem(
        id: 'g${gifts.length}',
        kind: 'gift',
        fromUid: from,
        fromName: profiles[from]?['name'] as String? ?? '',
        reward: const Reward(energy: 5),
        at: DateTime(2026, 1, 1),
      ),
    );
  });
}

void main() {
  late DateTime now;
  late FakeBackend server;
  late SharedPreferences prefs;

  setUp(() async {
    now = DateTime(2026, 3, 1, 10);
    server = FakeBackend();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  SocialService make(String? uid, {int seed = 1, String? name}) {
    server.sender = uid;
    return SocialService(
      backend: server,
      prefs: prefs,
      uid: () => uid,
      accountName: () => name,
      random: Random(seed),
      clock: () => now,
    );
  }

  GameState game() => GameState(random: Random(1), clock: () => now);

  group('친구 코드', () {
    test('생성: 8자리, 헷갈리는 글자 없음', () {
      final rng = Random(7);
      for (var i = 0; i < 200; i++) {
        final c = FriendCode.generate(rng);
        expect(c.length, 8);
        expect(c, isNot(matches(RegExp('[ILO01]'))));
        expect(FriendCode.isValid(c), isTrue);
      }
    });

    test('입력 정리 · 검사', () {
      expect(FriendCode.normalize('abcd-efgh'), 'ABCDEFGH');
      expect(FriendCode.normalize(' AB CD EF GH '), 'ABCDEFGH');
      expect(FriendCode.normalize('ABCDEFG'), isNull); // 7자리
      expect(FriendCode.normalize('ABCDEFGO'), isNull); // O 는 쓰지 않는다
      expect(FriendCode.normalize('ABCDEFG1'), isNull);
      expect(FriendCode.display('ABCDEFGH'), 'ABCD-EFGH');
    });
  });

  test('닉네임 정리', () {
    expect(cleanName('  민트\n  친구 '), '민트 친구');
    expect(cleanName('a' * 40).length, SocialConfig.nameMax);
    expect(cleanName('\u202Eevil'), 'evil');
  });

  test('하루 한 번: 날짜 키와 판정', () {
    expect(socialDayKey(DateTime(2026, 3, 1, 23, 59)), '2026-03-01');
    expect(socialDayKey(DateTime(2026, 3, 2, 0, 1)), '2026-03-02');
    expect(canGiftToday(null, '2026-03-01'), isTrue);
    expect(canGiftToday('2026-03-01', '2026-03-01'), isFalse);
    expect(canGiftToday('2026-02-28', '2026-03-01'), isTrue);
  });

  test('받은 선물 → 쪽지 (id 는 서버 문서 id, 보상은 상한)', () {
    final m = inboxToMail(
      InboxItem(
        id: 'abc',
        kind: 'gift',
        fromUid: 'u2',
        fromName: ' 보리\n',
        reward: const Reward(energy: 999),
        at: DateTime(2026, 1, 1),
      ),
    )!;
    expect(m.id, 'gift-abc');
    expect(m.kind, MailKind.social);
    expect(m.from, '보리');
    expect(m.titleKey, 'social.mail.gift');
    expect(m.reward.energy, 20);
    final other = InboxItem(
      id: 'x',
      kind: 'weird',
      fromUid: '',
      fromName: '',
      reward: const Reward(),
      at: DateTime(2026),
    );
    expect(inboxToMail(other), isNull);
  });

  test('공지 → 쪽지: 언어별 제목, 기간 밖이면 없음', () {
    final n = Notice.fromMap('n1', {
      'title_ko': '점검 보상',
      'title_en': 'Maintenance gift',
      'reward': {'c': 100, 'e': 10},
      'startAt': DateTime(2026, 2, 1),
      'endAt': DateTime(2026, 4, 1),
    });
    final m = noticeToMail(n, 'en', now)!;
    expect(m.id, 'notice-n1');
    expect(m.kind, MailKind.notice);
    expect(m.from, 'team');
    expect(m.text, 'Maintenance gift');
    expect(m.reward.coins, 100);
    expect(noticeToMail(n, 'ja', now)!.text, '점검 보상'); // 없으면 한국어
    expect(noticeToMail(n, 'ko', DateTime(2026, 5, 1)), isNull);
    expect(noticeToMail(n, 'ko', DateTime(2026, 1, 1)), isNull);
  });

  test('구경용 정원: 공개 프로필 그대로, 모르는 친구 id 는 버린다', () {
    final p = SocialProfile.fromMap('u2', {
      'name': '친구',
      'code': 'ABCDEFGH',
      'level': 12,
      'area': 2,
      'placed': [0, 3, 99],
      'friends': ['dubu', 'hacker'],
      'avatar': 'nope',
    });
    expect(p.avatar, Friends.starter);
    expect(p.placed, {0, 3});
    final g = p.toVisitGame();
    expect(g.level, 12);
    expect(g.currentArea, 2);
    expect(g.isPlaced(2, 3), isTrue);
    expect(g.isPlaced(1, 7), isTrue);
    expect(g.friends, {Friends.starter, 'dubu'});
    expect(p.showcaseArea, 2);
    expect(
      SocialProfile.fromMap('u', {'area': 3, 'placed': []}).showcaseArea,
      2,
    );
  });

  group('서비스', () {
    test('로그인 안 함(기기 게스트)이면 쓸 수 없고 조용히 넘어간다', () async {
      final s = make(null);
      expect(s.canUse, isFalse);
      expect(s.badge, isFalse);
      await s.refresh(game());
      expect(server.profileWrites, 0);
      expect(
        () => s.addFriendByCode('ABCDEFGH'),
        throwsA(isA<SocialException>()),
      );
    });

    test('프로필 만들기: 코드 예약, 계정 이름, 바뀐 게 없으면 다시 쓰지 않음', () async {
      final s = make('u1', name: '민트');
      final g = game();
      final me = await s.ensureProfile(g);
      expect(me.name, '민트');
      expect(FriendCode.isValid(me.code), isTrue);
      expect(server.codes[me.code], 'u1');
      expect(server.profileWrites, 1);
      await s.syncProfile(g);
      now = now.add(const Duration(minutes: 5));
      await s.syncProfile(g);
      expect(server.profileWrites, 1);
      g.level = 3;
      await s.syncProfile(g);
      expect(server.profileWrites, 2);
      expect(server.profiles['u1']!['level'], 3);
    });

    test('코드가 겹치면 다른 코드를 고른다', () async {
      final taken = FriendCode.generate(Random(1));
      server.codes[taken] = 'someone';
      final s = make('u1');
      final me = await s.ensureProfile(game());
      expect(me.code, isNot(taken));
      expect(server.codes[me.code], 'u1');
    });

    test('친구 추가: 코드 확인, 나 자신 · 중복 · 없는 코드', () async {
      final b = make('u2', seed: 2);
      final bMe = await b.ensureProfile(game());
      final a = make('u1');
      final aMe = await a.ensureProfile(game());
      Future<String> err(String code) async {
        try {
          await a.addFriendByCode(code);
          return 'ok';
        } on SocialException catch (e) {
          return e.code;
        }
      }

      expect(await err('12'), 'invalidCode');
      expect(await err(aMe.code), 'self');
      expect(await err('ZZZZZZZZ'), 'notFound');
      expect(await err(FriendCode.display(bMe.code).toLowerCase()), 'ok');
      expect(a.friends.single.uid, 'u2');
      expect(await err(bMe.code), 'already');
      expect(server.links['u1']!.keys, ['u2']);
    });

    test('친구는 최대 50명', () async {
      final a = make('u1');
      await a.ensureProfile(game());
      for (var i = 0; i < SocialConfig.maxFriends; i++) {
        server.links['u1'] = {...?server.links['u1'], 'f$i': null};
        server.profiles['f$i'] = {'name': 'f$i', 'code': 'ABCDEFGH'};
      }
      await a.loadFriends(force: true);
      expect(a.friends.length, SocialConfig.maxFriends);
      server.codes['HHHHHHHH'] = 'x';
      server.profiles['x'] = {'name': 'x'};
      expect(
        () => a.addFriendByCode('HHHHHHHH'),
        throwsA(isA<SocialException>().having((e) => e.code, 'code', 'full')),
      );
    });

    test('신고: 이름 · 코드 · 이유를 남기고, 원하면 친구에서도 뺀다', () async {
      final b = make('u2', seed: 2);
      final bMe = await b.ensureProfile(game());
      final a = make('u1', name: '민트');
      await a.ensureProfile(game());
      final f = await a.addFriendByCode(bMe.code);
      await a.reportFriend(f, 'name');
      expect(server.reports.length, 1);
      expect(server.reports.first['from'], 'u1');
      expect(server.reports.first['target'], 'u2');
      expect(server.reports.first['code'], bMe.code);
      expect(server.reports.first['reason'], 'name');
      expect(a.friends.any((x) => x.uid == 'u2'), isFalse);
    });

    test('하루 한 번 선물: 보내면 완료, 업적 기록, 받는 쪽 쪽지 (중복 없음)', () async {
      final b = make('u2', seed: 2);
      final bGame = game();
      final bMe = await b.ensureProfile(bGame);
      final a = make('u1', name: '민트');
      final aGame = game();
      await a.ensureProfile(aGame);
      final f = await a.addFriendByCode(bMe.code);
      expect(a.badge, isTrue);

      await a.sendGift(f, aGame);
      expect(a.giftSentToday(f), isTrue);
      expect(a.badge, isFalse);
      expect(aGame.stat(Stat.giftsSent), 1);
      await a.sendGift(f, aGame); // 이미 보냄: 아무 일 없음
      expect(aGame.stat(Stat.giftsSent), 1);
      expect(server.inboxes['u2']!.length, 1);

      // 받는 쪽
      server.sender = 'u2';
      final before = bGame.mail.length;
      expect(await b.pullInbox(bGame), 1);
      expect(bGame.mail.length, before + 1);
      final m = bGame.mail.first;
      expect(m.kind, MailKind.social);
      expect(m.from, '민트');
      expect(m.reward.energy, 5);
      expect(server.inboxes['u2'], isEmpty);
      // 지우지 못한 같은 선물이 다시 와도 한 번만
      server.inboxes['u2'] = [
        InboxItem(
          id: m.id.substring(5),
          kind: 'gift',
          fromUid: 'u1',
          fromName: '민트',
          reward: const Reward(energy: 5),
          at: now,
        ),
      ];
      expect(await b.pullInbox(bGame), 0);
      expect(bGame.mail.length, before + 1);

      // 다음 날에는 다시 보낼 수 있다
      server.sender = 'u1';
      now = now.add(const Duration(days: 1));
      expect(a.giftSentToday(f), isFalse);
      await a.sendGift(f, aGame);
      expect(aGame.stat(Stat.giftsSent), 2);
    });

    test('서버가 이미 받았다고 하면 완료로만 표시 (기록은 늘리지 않음)', () async {
      final b = make('u2', seed: 2);
      final bMe = await b.ensureProfile(game());
      final a = make('u1');
      final g = game();
      await a.ensureProfile(g);
      final f = await a.addFriendByCode(bMe.code);
      server.gifts.add('u1_u2_${a.today}'); // 다른 기기에서 이미 보냄
      await a.sendGift(f, g);
      expect(a.giftSentToday(f), isTrue);
      expect(g.stat(Stat.giftsSent), 0);
    });

    test('공지는 한 번만 쪽지로', () async {
      final s = make('u1');
      final g = game();
      server.noticeList.add(
        Notice(
          id: 'n1',
          titles: const {'ko': '이벤트'},
          reward: const Reward(stars: 1),
          endAt: now.add(const Duration(days: 3)),
        ),
      );
      expect(await s.pullNotices(g, force: true), 1);
      expect(g.mail.first.id, 'notice-n1');
      g.mail.removeAt(0); // 쪽지함 정리로 지워져도
      expect(await s.pullNotices(g, force: true), 0);
    });

    test('구경 답례는 하루 한 번', () async {
      final s = make('u1');
      final g = game();
      final e0 = g.energy;
      expect(s.claimVisitThanks(g, '보리')!.energy, 3);
      expect(g.energy, e0 + 3);
      expect(s.claimVisitThanks(g, '보리'), isNull);
      now = now.add(const Duration(days: 1));
      expect(s.visitThanksReady, isTrue);
      expect(s.claimVisitThanks(g, '보리'), isNotNull);
    });

    test('오프라인: 예외로 알려 주고, refresh 는 조용히', () async {
      final s = make('u1');
      server.online = false;
      await s.refresh(game()); // 던지지 않는다
      expect(
        () => s.addFriendByCode('ABCDEFGH'),
        throwsA(isA<SocialException>()),
      );
    });

    testWidgets('응답이 없으면 10초 뒤 timeout (멈추지 않는다)', (tester) async {
      final s = make('u1');
      server.hang = true;
      Object? err;
      s
          .ensureProfile(game())
          .then(
            (_) {},
            onError: (Object e) {
              err = e;
            },
          );
      await tester.pump(const Duration(seconds: 9));
      expect(err, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(
        err,
        isA<SocialException>().having((e) => e.code, 'code', 'timeout'),
      );
    });
  });

  group('화면', () {
    Future<void> open(WidgetTester tester, SocialService s, GameState g) async {
      tester.view.physicalSize = const Size(1080, 2340); // 세로 폰
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showFriendsSheet(ctx, s, g),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('기기 게스트에게는 로그인 안내만', (tester) async {
      await open(tester, make(null), game());
      expect(find.textContaining('social.needSignIn'), findsOneWidget);
    });

    testWidgets('친구 목록 · 선물 · 구경', (tester) async {
      final g = game();
      late SocialService a;
      await tester.runAsync(() async {
        final b = make('u2', seed: 2);
        final bMe = await b.ensureProfile(game());
        a = make('u1', name: '민트');
        await a.ensureProfile(g);
        await a.addFriendByCode(bMe.code);
      });
      await open(tester, a, g);
      expect(find.text('민트'), findsOneWidget);
      expect(find.textContaining('social.gift'), findsWidgets);
      await tester.tap(find.textContaining('social.gift').last);
      await tester.pumpAndSettle();
      expect(g.stat(Stat.giftsSent), 1);
      expect(find.textContaining('social.giftDone'), findsOneWidget);
      await tester.tap(find.textContaining('social.visit'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(
          const Duration(milliseconds: 50),
        ); // 정원은 계속 움직여서 settle 하지 않는다
      }
      expect(find.textContaining('social.visitTitle'), findsOneWidget);
      await tester.ensureVisible(find.textContaining('social.visitThanks'));
      await tester.pump();
      await tester.tap(find.textContaining('social.visitThanks'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('social.visitThanked'), findsOneWidget);
    });
  });
}

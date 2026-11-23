import 'dart:async';
import 'dart:math';

import 'package:mint_and_friends/game/game_state.dart';
import 'package:mint_and_friends/services/save_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SaveSummary s(int level, {int area = 0, DateTime? at}) =>
    SaveSummary(level, area, level * 1e6 + area * 8e3, at);

void main() {
  final t0 = DateTime(2026, 1, 1, 12);
  final t1 = t0.add(const Duration(minutes: 5));

  test('클라우드에 없으면 기기 데이터를 올린다', () {
    expect(
      decideSync(local: s(5), localOwner: null, cloud: null, uid: 'u'),
      SyncDecision.uploadLocal,
    );
  });

  test('기기가 갓 시작한 게임이면 클라우드를 쓴다', () {
    expect(
      decideSync(local: s(1), localOwner: null, cloud: s(9), uid: 'u'),
      SyncDecision.useCloud,
    );
  });

  test('같은 계정이면 더 최근 저장을 쓴다', () {
    expect(
      decideSync(
        local: s(5, at: t1),
        localOwner: 'u',
        cloud: s(6, at: t0),
        uid: 'u',
      ),
      SyncDecision.uploadLocal,
    );
    expect(
      decideSync(
        local: s(5, at: t0),
        localOwner: 'u',
        cloud: s(6, at: t1),
        uid: 'u',
      ),
      SyncDecision.useCloud,
    );
  });

  test('다른 주인의 기기 데이터 + 클라우드 진행도가 있으면 묻는다', () {
    expect(
      decideSync(
        local: s(5, at: t1),
        localOwner: 'guest',
        cloud: s(7, at: t0),
        uid: 'u',
      ),
      SyncDecision.ask,
    );
    expect(
      decideSync(
        local: s(5, at: t1),
        localOwner: null,
        cloud: s(7, at: t0),
        uid: 'u',
      ),
      SyncDecision.ask,
    );
  });

  group('attach', () {
    late DateTime now;
    GameState make({int level = 1}) =>
        GameState(random: Random(1), clock: () => now)..level = level;
    final writes = <String>[];

    Future<SaveService> service(
      Map<String, Object> init, {
      CloudFetch? fetch,
    }) async {
      SharedPreferences.setMockInitialValues(init);
      final prefs = await SharedPreferences.getInstance();
      return SaveService(
        prefs,
        fetch: fetch,
        write: (id, json, game) async => writes.add(id),
      );
    }

    setUp(() {
      now = t0;
      writes.clear();
    });

    test('오래된 기기 저장은 같은 계정의 더 새 클라우드 저장을 덮어쓰지 않는다', () async {
      now = t0;
      final local = make(level: 5);
      final localRaw = local.encode(); // savedAt = t0
      now = t1;
      final cloud = make(level: 6).toJson(); // savedAt = t1
      now = t1.add(const Duration(hours: 3)); // 오래된 기기를 지금 켰다
      final save = await service({
        'save_v3': localRaw,
        'save_owner': 'u',
      }, fetch: (_) async => cloud);
      final g = make();
      expect(save.loadLocal(g), isTrue);
      final ok = await save.attach(
        'u',
        g,
        askUser: (_, _) async => fail('묻지 않아야 한다'),
      );
      expect(ok, isTrue);
      expect(g.level, 6);
      expect(writes, isEmpty);
    });

    test('연결 중 자동 저장이 주인을 바꿔도 게스트 → 기존 계정이면 묻는다', () async {
      now = t0;
      final g = make(level: 5);
      final cloudDone = Completer<Map<String, dynamic>?>();
      final cloud = make(level: 7).toJson();
      final save = await service({
        'save_v3': g.encode(),
        'save_owner': 'guest',
      }, fetch: (_) => cloudDone.future);
      save.uid = 'guest';
      var asked = false;
      final f = save.attach(
        'u',
        g,
        askUser: (_, _) async {
          asked = true;
          return false; // 기기 데이터를 쓴다
        },
      );
      expect(save.uid, isNull); // 결정 전에는 붙이지 않는다
      save.saveLocal(g); // 5초 자동 저장
      expect(save.localOwner, 'guest');
      cloudDone.complete(cloud);
      expect(await f, isTrue);
      expect(asked, isTrue);
      expect(save.uid, 'u');
      expect(save.localOwner, 'u');
      expect(writes, ['u']);
    });

    test('클라우드 저장을 불러오지 못하면 오류: 올리지도 동기화 표시도 안 한다', () async {
      final g = make(level: 5);
      final cloud = make(level: 7).toJson()..['v'] = -1;
      final save = await service({
        'save_v3': g.encode(),
        'save_owner': 'guest',
      }, fetch: (_) async => cloud);
      final ok = await save.attach('u', g, askUser: (_, _) async => true);
      expect(ok, isFalse);
      expect(save.uid, isNull);
      expect(save.status, SyncStatus.error);
      expect(writes, isEmpty);
      expect(g.level, 5);
    });

    test('업로드가 실패하면 false 를 돌려준다', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final save = SaveService(
        prefs,
        write: (_, _, _) async => throw Exception('offline'),
      );
      final g = make(level: 3);
      expect(await save.upload(g), isFalse); // uid 없음
      save.uid = 'u';
      expect(await save.upload(g), isFalse);
      expect(save.status, SyncStatus.error);
    });
  });
}

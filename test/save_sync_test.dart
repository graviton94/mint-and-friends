import 'package:mint_and_friends/services/save_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

import 'game_state.dart';

/// 손님 · 비눗방울 창(과 광고)이 떠 있는 동안 시간이 다 돼 사라지지 않게 붙잡는다.
/// 돌려받은 함수를 부르면 원래 시각으로 되돌린다 (여러 번 불러도 된다).
/// 보상을 줄 때는 되돌린 직후 같은 흐름에서 바로 받는다 (그 사이 tick 이 끼지 않는다).
class RewardHold {
  RewardHold._();

  /// 창 · 광고가 이보다 오래 걸리는 일은 없다.
  static const Duration grace = Duration(minutes: 10);

  static void Function() visitor(GameState g) {
    final until = g.visitorUntil;
    if (until == null || !g.visitorVisible) return () {};
    g.visitorUntil = g.now.add(grace);
    var done = false;
    return () {
      if (done) return;
      done = true;
      if (g.visitorUntil != null) g.visitorUntil = until; // 아직 안 받았으면 원래대로
    };
  }

  static void Function() bubble(GameState g, int cell) {
    final it = g.board[cell];
    final until = it?.bubbleUntil;
    if (it == null || until == null) return () {};
    // 비용은 남은 시간으로 매기므로, 늘린 시간은 되돌린 뒤에 계산된다
    it.bubbleUntil = g.now.add(grace);
    var done = false;
    return () {
      if (done) return;
      done = true;
      if (it.isBubble) it.bubbleUntil = until;
    };
  }
}

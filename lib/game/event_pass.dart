// 월간 이벤트 패스 (D-112, 기획: docs/plan/monthly_events.md).
// 매달 컨셉 하나. 하루 퀘스트 4개 중 3개 = 사다리 1칸 (하루 한 칸), 20칸. 칸마다 무료 · 패스 보상.
// 패스는 그달에만 (달 중간에 사도 지난 칸의 패스 보상까지 받는다).

/// 이달의 이벤트 정의. 그림(배너)이 들어온 달만 열린다.
class EventDef {
  final String id; // 'onsen' (그림 · 문구 키)
  final int year;
  final int month;
  final String friend; // 패스 최종 의상을 입는 친구
  final String outfit; // 의상 id (Outfits 에 없어도 됨: 이벤트 전용)

  /// 무료 최종 보상: 기념품 장식 id (null 이면 정원 효과 [effect]).
  final String? souvenir;
  final String? effect;
  const EventDef(
    this.id,
    this.year,
    this.month,
    this.friend,
    this.outfit, {
    this.souvenir,
    this.effect,
  });

  String get banner => 'assets/art/events/${id}_banner.webp';
  String get badge => 'assets/art/badges/$id.webp';
}

enum QuestKind { basket, merge, pat, ad }

enum RewardKind {
  energy,
  coins,
  stars,
  gems,
  boostCoins,
  boostEnergy,
  boostLucky,
  badge,
  finale,
}

/// 사다리 한 칸의 보상 하나. coins = 시간당 수입 n시간치, stars = 다음 장식 값의 n%.
class StepReward {
  final RewardKind kind;
  final int amount;
  const StepReward(this.kind, this.amount);
}

class EventPass {
  static const String productId = 'event_pass_5900';
  static const int krw = 5900;
  static const int steps = 20;

  /// 하루에 칸을 오르려면 퀘스트 몇 개.
  static const int questsNeeded = 3;

  static const Map<QuestKind, int> target = {
    QuestKind.basket: 30, // 바구니 30번
    QuestKind.merge: 30, // 합치기 30번
    QuestKind.pat: 5, // 정원 친구 쓰다듬기 5번 (친구 선물은 친구 기능이 없으면 못 해서 대신)
    QuestKind.ad: 1, // 광고 1번 (광고 없이 보상 받는 사람은 저절로)
  };

  static const List<EventDef> events = [
    EventDef('onsen', 2027, 1, 'bori', 'onsen', souvenir: 'onsen'),
    EventDef('cocoa', 2027, 2, 'dubu', 'cocoa', effect: 'cocoa'),
    EventDef('bloom', 2027, 3, 'kongtteok', 'bloom', souvenir: 'bloom'),
  ];

  static EventDef? at(int year, int month) =>
      events.where((e) => e.year == year && e.month == month).firstOrNull;

  static EventDef? byId(String id) =>
      events.where((e) => e.id == id).firstOrNull;

  /// 무료 줄 (다이아 합 30).
  static const List<StepReward> free = [
    StepReward(RewardKind.energy, 20),
    StepReward(RewardKind.coins, 1),
    StepReward(RewardKind.stars, 10),
    StepReward(RewardKind.boostLucky, 15),
    StepReward(RewardKind.gems, 5),
    StepReward(RewardKind.energy, 30),
    StepReward(RewardKind.coins, 2),
    StepReward(RewardKind.boostCoins, 30),
    StepReward(RewardKind.stars, 15),
    StepReward(RewardKind.badge, 1),
    StepReward(RewardKind.energy, 30),
    StepReward(RewardKind.coins, 3),
    StepReward(RewardKind.boostEnergy, 30),
    StepReward(RewardKind.stars, 20),
    StepReward(RewardKind.gems, 15),
    StepReward(RewardKind.energy, 40),
    StepReward(RewardKind.coins, 4),
    StepReward(RewardKind.gems, 10),
    StepReward(RewardKind.stars, 25),
    StepReward(RewardKind.finale, 1),
  ];

  /// 패스 줄 (다이아 합 130).
  static const List<StepReward> premium = [
    StepReward(RewardKind.gems, 10),
    StepReward(RewardKind.energy, 50),
    StepReward(RewardKind.boostCoins, 60),
    StepReward(RewardKind.coins, 4),
    StepReward(RewardKind.gems, 15),
    StepReward(RewardKind.energy, 60),
    StepReward(RewardKind.boostEnergy, 60),
    StepReward(RewardKind.coins, 6),
    StepReward(RewardKind.gems, 15),
    StepReward(RewardKind.gems, 20),
    StepReward(RewardKind.energy, 80),
    StepReward(RewardKind.boostLucky, 60),
    StepReward(RewardKind.coins, 8),
    StepReward(RewardKind.gems, 20),
    StepReward(RewardKind.energy, 100),
    StepReward(RewardKind.boostCoins, 120),
    StepReward(RewardKind.coins, 12),
    StepReward(RewardKind.gems, 30),
    StepReward(RewardKind.energy, 120),
    StepReward(RewardKind.finale, 1),
  ];

  /// 이벤트 그림(배너)이 들어왔는지 (Art.init 이 연결). 그림이 없는 달은 열지 않는다.
  static bool Function(EventDef e) ready = (_) => true;

  /// 미리보기 · 테스트용: 날짜와 상관없이 이 이벤트를 연다.
  static EventDef? debugEvent;

  /// 기념품 하나마다 정원 매력.
  static const double souvenirCharm = 0.005;
}

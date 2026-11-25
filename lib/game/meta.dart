import 'dart:math';

/// 업적 · 쪽지 같은 장기 콘텐츠의 정의 (순수 데이터, 화면 문구는 i18n 키로).

// ------------------------------------------------------------------ 누적 기록

/// 업적이 세는 누적 기록. 저장 키 = 이름이므로 바꾸지 말 것 (추가만).
enum Stat {
  merges,
  maxMerges,
  spawns,
  orders,
  orderStars,
  decor,
  areas,
  sells,
  stored,
  cellsBought,
  upgradesBought,
  visitors,
  bubblesPopped,
  friendTaps,
  adsWatched,
  daysPlayed,
  mailClaimed,
  giftsSent,
  coinsEarned,
  energySpent,
  gemsSpent,
  shopBuys,
  stylesBought,
  autoSpawns,
}

// ------------------------------------------------------------------ 업적

/// 보상 한 칸.
class Reward {
  final int coins;
  final int energy;
  final int stars;
  final int gems;
  const Reward({
    this.coins = 0,
    this.energy = 0,
    this.stars = 0,
    this.gems = 0,
  });

  bool get isEmpty => coins == 0 && energy == 0 && stars == 0 && gems == 0;

  Map<String, dynamic> toJson() => {
    if (coins > 0) 'c': coins,
    if (energy > 0) 'e': energy,
    if (stars > 0) 's': stars,
    if (gems > 0) 'g': gems,
  };

  static Reward fromJson(Map<String, dynamic>? j) => j == null
      ? const Reward()
      : Reward(
          coins: (j['c'] as num?)?.toInt() ?? 0,
          energy: (j['e'] as num?)?.toInt() ?? 0,
          stars: (j['s'] as num?)?.toInt() ?? 0,
          gems: (j['g'] as num?)?.toInt() ?? 0,
        );
}

/// 무엇을 세는 업적인지.
enum AchKind { stat, level, flowerLevel, snackLevel, friends, maxAffection }

/// 업적 한 줄 (여러 단계). id 는 i18n `ach.<id>` (이름) · `ach.<id>.desc` ({n} = 목표).
class AchievementDef {
  final String id;
  final String icon; // 아이콘 토큰 (예: 'sparkle', 'item:flower:5')
  final AchKind kind;
  final Stat? stat;

  /// 손으로 정한 앞 단계들. 실제 단계는 [tiers] (사이 단계를 채우고 뒤로 끝없이 늘린다, D-064).
  final List<int> base;

  /// 뒤로 늘리는 방법: 곱하기([grow]) 또는 더하기([step]), [cap] 까지. 둘 다 없으면 [base] 그대로.
  final double? grow;
  final int? step;
  final int cap;
  const AchievementDef(
    this.id,
    this.icon,
    this.kind,
    this.base, {
    this.stat,
    this.grow,
    this.step,
    this.cap = 9000000000000000000,
  });

  static final Map<String, List<int>> _cache = {};

  /// 단계 목표: 손으로 정한 단계 뒤로 끝없이 (최대 [maxTiers]).
  List<int> get tiers => _cache[id] ??= _build();
  static const int maxTiers = 400;

  /// 보기 좋은 수 (앞 두 자리만 남김: 1234 → 1200).
  static int nice(double v) {
    if (v < 100) return v.round();
    final p = pow(10, (log(v) / ln10).floor() - 1).toDouble();
    return ((v / p).round() * p).round();
  }

  List<int> _build() {
    // 앞 단계는 손으로 정한 그대로 (초반 속도 · 보상은 예전과 같게), 그 뒤로 끝없이
    final out = [...base];
    if (grow == null && step == null) return out;
    while (out.length < maxTiers) {
      final last = out.last;
      final next = grow != null ? nice(last * grow!) : last + step!;
      if (next <= last || next > cap) break;
      out.add(next);
    }
    return out;
  }

  /// 끝이 없는 업적인지 (화면에 '몇 / 몇' 대신 단계만).
  bool get endless => grow != null || (step != null && cap > 1000000000);

  /// 단계별 보상 (코인은 game_state 가 지금 수입에 맞춰 더 준다, D-064).
  /// 에너지 · 별 · 다이아는 상한을 둬서 끝없는 단계가 경제를 흔들지 않게.
  Reward rewardFor(int tier) => Reward(
    coins: (50 * pow(1.8, min(tier, 12))).round(),
    energy: tier >= 1 ? 5 + 5 * min(tier, 6) : 0,
    // 별: 9단계까지는 예전 그대로, 그 뒤는 5단계마다 20개
    stars: tier < 2
        ? 0
        : tier < 10
        ? (3 * pow(1.5, tier)).round()
        : (tier % 5 == 0 ? 20 : 0),
    // 다이아: 3~9단계는 1~7개, 그 뒤는 5단계마다 5개
    gems: tier < 3
        ? 0
        : tier < 10
        ? tier - 2
        : (tier % 5 == 0 ? 5 : 0),
  );
}

class Achievements {
  static const List<AchievementDef> all = [
    // 합치기 · 생산
    AchievementDef(
      'merges',
      'sparkle',
      AchKind.stat,
      [10, 50, 200, 500, 1000, 2500, 5000, 10000, 25000, 50000],
      stat: Stat.merges,
      grow: 1.6,
    ),
    AchievementDef(
      'maxMerges',
      'trophy',
      AchKind.stat,
      [1, 3, 10, 25, 50, 100],
      stat: Stat.maxMerges,
      grow: 1.6,
    ),
    AchievementDef(
      'spawns',
      'basket',
      AchKind.stat,
      [50, 200, 1000, 3000, 8000, 20000, 50000, 100000],
      stat: Stat.spawns,
      grow: 1.6,
    ),
    AchievementDef(
      'energySpent',
      'energy',
      AchKind.stat,
      [100, 500, 2000, 6000, 15000, 40000, 100000],
      stat: Stat.energySpent,
      grow: 1.6,
    ),
    // 도감
    AchievementDef(
      'flowerLevel',
      'item:flower:8',
      AchKind.flowerLevel,
      [3, 5, 7, 9, 11, 13, 15],
      step: 1,
      cap: 30,
    ),
    AchievementDef(
      'snackLevel',
      'item:snack:8',
      AchKind.snackLevel,
      [3, 5, 7, 9, 11, 13, 15],
      step: 1,
      cap: 30,
    ),
    // 부탁 · 친구
    AchievementDef(
      'orders',
      'letter',
      AchKind.stat,
      [5, 25, 100, 250, 500, 1000, 2500, 5000, 10000],
      stat: Stat.orders,
      grow: 1.6,
    ),
    AchievementDef(
      'orderStars',
      'star',
      AchKind.stat,
      [10, 50, 150, 400, 1000, 2500, 6000],
      stat: Stat.orderStars,
      grow: 1.6,
    ),
    AchievementDef('friends', 'heart', AchKind.friends, [2, 3, 4, 5, 6, 7, 8]),
    AchievementDef('maxAffection', 'heart', AchKind.maxAffection, [
      1,
      2,
      4,
      6,
      8,
    ]),
    AchievementDef(
      'friendTaps',
      'heart',
      AchKind.stat,
      [10, 50, 200, 500, 1500, 4000],
      stat: Stat.friendTaps,
      grow: 1.6,
    ),
    AchievementDef(
      'visitors',
      'gift',
      AchKind.stat,
      [1, 5, 20, 50, 100, 250, 500],
      stat: Stat.visitors,
      grow: 1.6,
    ),
    // 정원
    AchievementDef(
      'decor',
      'decorate',
      AchKind.stat,
      [1, 8, 16, 32, 48, 64, 96, 128],
      stat: Stat.decor,
      step: 16,
    ),
    AchievementDef(
      'areas',
      'area_yard',
      AchKind.stat,
      [1, 2, 3, 4, 6, 8, 12, 16],
      stat: Stat.areas,
      step: 2,
    ),
    // 성장
    AchievementDef('level', 'upgrade', AchKind.level, [
      5,
      10,
      15,
      20,
      25,
      30,
      40,
      50,
      60,
      75,
      100,
    ], step: 5),
    AchievementDef('cellsBought', 'lock', AchKind.stat, [
      1,
      3,
      6,
      10,
      14,
      18,
    ], stat: Stat.cellsBought),
    AchievementDef(
      'upgradesBought',
      'upgrade',
      AchKind.stat,
      [1, 10, 30, 60, 100, 150, 200],
      stat: Stat.upgradesBought,
      grow: 1.5,
    ),
    AchievementDef(
      'coinsEarned',
      'coinbag',
      AchKind.stat,
      [1000, 5000, 20000, 75000, 250000, 1000000, 5000000],
      stat: Stat.coinsEarned,
      grow: 4,
    ),
    // 정리
    AchievementDef(
      'sells',
      'coin',
      AchKind.stat,
      [5, 25, 100, 300, 1000],
      stat: Stat.sells,
      grow: 1.6,
    ),
    AchievementDef(
      'stored',
      'storage',
      AchKind.stat,
      [5, 25, 100, 300, 1000],
      stat: Stat.stored,
      grow: 1.6,
    ),
    AchievementDef(
      'bubblesPopped',
      'bubble',
      AchKind.stat,
      [1, 5, 20, 50, 150],
      stat: Stat.bubblesPopped,
      grow: 1.6,
    ),
    // 꾸준함 · 소셜
    AchievementDef(
      'daysPlayed',
      'moon',
      AchKind.stat,
      [1, 3, 7, 14, 30, 60, 100, 200, 365, 500, 1000],
      stat: Stat.daysPlayed,
      step: 50,
    ),
    AchievementDef(
      'mailClaimed',
      'letter',
      AchKind.stat,
      [1, 10, 50, 150, 400, 1000],
      stat: Stat.mailClaimed,
      grow: 1.6,
    ),
    AchievementDef(
      'giftsSent',
      'gift',
      AchKind.stat,
      [1, 10, 50, 150, 400, 1000],
      stat: Stat.giftsSent,
      grow: 1.6,
    ),
    AchievementDef(
      'adsWatched',
      'ad',
      AchKind.stat,
      [5, 25, 100, 300, 1000],
      stat: Stat.adsWatched,
      grow: 1.6,
    ),
  ];

  static int get totalGoals => all.fold(0, (a, d) => a + d.tiers.length);
}

// ------------------------------------------------------------------ 쪽지

enum MailKind { notice, friendGift, social }

/// 쪽지 한 통. 제목 · 본문은 i18n 키 + 인자 (원격 공지는 text 를 그대로).
class Mail {
  final String id;
  final MailKind kind;

  /// 보낸 이: 동물 친구 id, 'team'(운영), 또는 소셜 친구 이름.
  final String from;
  final String titleKey;
  final Map<String, String> args;

  /// 원격 공지처럼 번역 키가 없는 글 (제목).
  final String? text;

  /// 본문: 원격 공지 본문, 또는 번역 키(bodyKey). 상세 창에 보인다.
  final String? body;
  final String? bodyKey;
  final Reward reward;
  final DateTime at;

  /// 읽음 / 받음 (보상이 있으면 받았을 때, 없으면 열어 봤을 때).
  bool claimed;

  /// 읽은 때 (읽은 쪽지는 [MailConfig.keepRead] 뒤 자동으로 지운다).
  DateTime? readAt;

  Mail({
    required this.id,
    required this.kind,
    required this.from,
    required this.titleKey,
    this.args = const {},
    this.text,
    this.body,
    this.bodyKey,
    this.reward = const Reward(),
    required this.at,
    this.claimed = false,
    this.readAt,
  });

  bool get hasReward => !reward.isEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'k': kind.name,
    'f': from,
    't': titleKey,
    if (args.isNotEmpty) 'a': args,
    if (text != null) 'x': text,
    if (body != null) 'b': body,
    if (bodyKey != null) 'bk': bodyKey,
    if (readAt != null) 'ra': readAt!.millisecondsSinceEpoch,
    if (!reward.isEmpty) 'r': reward.toJson(),
    'at': at.millisecondsSinceEpoch,
    if (claimed) 'c': true,
  };

  static Mail fromJson(Map<String, dynamic> j) => Mail(
    id: j['id'] as String,
    kind: MailKind.values.byName(j['k'] as String? ?? 'notice'),
    from: j['f'] as String? ?? 'team',
    titleKey: j['t'] as String? ?? '',
    args: ((j['a'] as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v')),
    text: j['x'] as String?,
    body: j['b'] as String?,
    bodyKey: j['bk'] as String?,
    readAt: j['ra'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((j['ra'] as num).toInt()),
    reward: Reward.fromJson((j['r'] as Map?)?.cast<String, dynamic>()),
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    claimed: j['c'] == true,
  );
}

class MailConfig {
  /// 동물 친구 깜짝 선물: 3~6시간마다, 받지 않은 선물은 최대 3통.
  static const Duration friendGiftMinGap = Duration(hours: 3);
  static const Duration friendGiftMaxGap = Duration(hours: 6);
  static const int friendGiftMaxUnread = 3;

  /// 쪽지 보관 개수 (오래된 받은 쪽지부터 지운다).
  static const int keep = 60;

  /// 읽은 쪽지는 이만큼 지나면 오래된 것부터 지운다.
  static const Duration keepRead = Duration(days: 14);

  /// 업데이트 안내 쪽지에 담는 작은 선물.
  static const int updateGiftEnergy = 30;
}

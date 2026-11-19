import 'dart:math';

/// 밸런스와 콘텐츠 상수. 숫자 튜닝은 대부분 이 파일에서 한다.
/// 화면에 보이는 이름·문구는 여기 두지 않는다. id 를 키로 assets/i18n/*.json 에서 찾는다.
/// 이모지는 아트가 들어오기 전까지 쓰는 임시 그림이다 (ArtRegistry 참고).
class GameConfig {
  static const int cols = 6;
  static const int rows = 5;
  static const int cellCount = cols * rows;

  /// 처음부터 열려 있는 칸: 가운데 4x3.
  static final Set<int> startCells = {
    for (var r = 1; r <= 3; r++)
      for (var c = 1; c <= 4; c++) r * cols + c,
  };

  static const int maxLevel = 15;

  /// 아이템 1개의 초당 코인 생산량.
  static double incomeOf(int level) => pow(2.2, level - 1).toDouble();

  /// 판매 가격 = 해당 아이템 N초분 수익.
  static const double sellSeconds = 25;

  /// 판매 되돌리기 가능 시간.
  static const Duration sellUndoWindow = Duration(seconds: 6);

  /// 최고 레벨 두 개를 합치면 사라지면서 지급되는 코인 (해당 아이템 N초분).
  static const double maxMergePayoutSeconds = 1800;

  /// 신규 아이템 발견 보너스 (해당 레벨 아이템 N초분).
  static const double discoveryBonusSeconds = 120;

  /// 행운 생성 확률 (생성 레벨 +1).
  static const double luckySpawnChance = 0.06;

  /// 합칠 때 같은 아이템이 든 비눗방울이 생길 확률. 광고를 보면 꺼내서 가질 수 있다.
  static const double bubbleChance = 0.05;
  static const Duration bubbleLife = Duration(seconds: 60);
  static const int bubbleMinLevel = 4;

  /// 오프라인 수익 효율.
  static const double offlineEfficiency = 0.5;

  /// 보상형 광고: 수익 2배 부스트 1회당 시간, 최대 누적.
  static const Duration boostPerAd = Duration(minutes: 10);
  static const Duration boostMax = Duration(minutes: 60);

  /// 보상형 광고: 코인 주머니 = 현재 초당 수익 * N초, 쿨다운.
  static const double coinBagSeconds = 300;
  static const Duration coinBagCooldown = Duration(minutes: 4);

  /// 전면 광고 최소 간격, 앱 시작 후 유예.
  static const Duration interstitialGap = Duration(minutes: 3);
  static const Duration interstitialGrace = Duration(minutes: 2);

  /// 동시에 떠 있는 부탁 수.
  static const int orderSlots = 3;

  /// 부탁 보상 코인 = 해당 아이템 N초분.
  static const double orderCoinSeconds = 90;

  /// 친구 탭 보상 = 초당 수익 N초분, 친구별 쿨다운.
  static const double friendTapSeconds = 3;
  static const Duration friendTapCooldown = Duration(seconds: 8);

  /// 깜짝 손님.
  static const Duration visitorMinGap = Duration(minutes: 3);
  static const Duration visitorMaxGap = Duration(minutes: 6);
  static const Duration visitorStay = Duration(seconds: 50);
  static const double visitorCoinSeconds = 60; // 그냥 받기
  static const double visitorAdCoinSeconds = 300; // 광고 보고 받기
  static const int visitorAdStars = 2;

  /// 장식 1개 / 구역 완성 시 정원 매력도 (수익 배율) 증가.
  static const double decorIncomeBonus = 0.10;
  static const double areaIncomeBonus = 0.50;
}

// ------------------------------------------------------------------ 레벨, 해금

/// 플레이어 레벨에 따라 열리는 기능.
enum Feature {
  upgrades,
  boost,
  snack,
  coinBag,
  autoMerge,
  visitor,
  spawnLevel,
  offlineCap,
}

class Leveling {
  /// 다음 레벨까지 필요한 경험치.
  static int xpToNext(int level) => (15 * pow(1.24, level - 1)).round();

  /// 기능별 해금 레벨.
  static const Map<Feature, int> unlockLevel = {
    Feature.upgrades: 2,
    Feature.boost: 2,
    Feature.snack: 3,
    Feature.coinBag: 4,
    Feature.autoMerge: 5,
    Feature.visitor: 6,
    Feature.spawnLevel: 8,
    Feature.offlineCap: 10,
  };

  /// 구역별 입장 레벨. 별이 있어도 레벨이 낮으면 다음 구역을 꾸밀 수 없다.
  static int areaLevel(int area) => area <= 0 ? 1 : 2 + area * 4;

  /// 강화 단계 상한 = 플레이어 레벨 기준.
  static int upgradeCap(int playerLevel) => 3 + playerLevel * 2;

  /// n번째(0부터) 칸 구매에 필요한 레벨.
  static int cellLevel(int n) => 2 + n;

  /// 경험치
  static int xpForMerge(int resultLevel) => 0; // 경험치는 부탁·꾸미기 위주 (머지 장르 표준)
  static int xpForOrder(int stars) => 5 * stars;
  static int xpForDecor(int cost) => 3 * cost;
  static const int xpForDiscovery = 2;

  /// 레벨업 보상 = 초당 수익 N초분 (최소 보장) + 별.
  static const double levelUpCoinSeconds = 120;
  static const int levelUpStars = 1;

  static List<Feature> unlockedAt(int level) => [
    for (final e in unlockLevel.entries)
      if (e.value == level) e.key,
  ];
}

/// 칸 구매 비용 (지금까지 산 칸 수 기준, 살수록 비싸짐).
double cellCost(int purchased) => 200 * pow(2.4, purchased).toDouble();

// ------------------------------------------------------------------ 아이템

enum Chain { flower, snack }

class ItemDef {
  final Chain chain;
  final int level;
  final String emoji;
  const ItemDef(this.chain, this.level, this.emoji);

  /// 문구 키: item.flower.3
  String get key => 'item.${chain.name}.$level';
}

class Chains {
  static const Map<Chain, List<String>> _emoji = {
    Chain.flower: [
      '🌰',
      '🌱',
      '☘️',
      '🌿',
      '🪴',
      '🌼',
      '🌷',
      '🌸',
      '🌹',
      '🌺',
      '🌻',
      '🪷',
      '💐',
      '🌈',
      '🏵️',
    ],
    Chain.snack: [
      '🍒',
      '🍓',
      '🍎',
      '🍑',
      '🍋',
      '🍪',
      '🧁',
      '🍩',
      '🥞',
      '🥧',
      '🍮',
      '🍰',
      '🍨',
      '🎂',
      '🍱',
    ],
  };

  static ItemDef item(Chain c, int level) {
    final l = level.clamp(1, GameConfig.maxLevel);
    return ItemDef(c, l, _emoji[c]![l - 1]);
  }
}

// ------------------------------------------------------------------ 강화

enum UpgradeType { spawnSpeed, income, autoMerge, spawnLevel, offlineCap }

class UpgradeDef {
  final UpgradeType type;
  final String icon;
  final int maxLevel;
  final double baseCost;
  final double costGrowth;
  final Feature? feature; // 이 기능이 해금돼야 살 수 있음
  const UpgradeDef(
    this.type,
    this.icon,
    this.maxLevel,
    this.baseCost,
    this.costGrowth, {
    this.feature,
  });

  double costAt(int level) => baseCost * pow(costGrowth, level);
  String get key => 'upgrade.${type.name}';
}

class Upgrades {
  static const List<UpgradeDef> all = [
    UpgradeDef(UpgradeType.spawnSpeed, '⏱️', 25, 30, 1.55),
    UpgradeDef(UpgradeType.income, '💰', 100, 60, 1.45),
    UpgradeDef(
      UpgradeType.autoMerge,
      '🤖',
      20,
      600,
      2.0,
      feature: Feature.autoMerge,
    ),
    UpgradeDef(
      UpgradeType.spawnLevel,
      '⭐',
      6,
      8000,
      40,
      feature: Feature.spawnLevel,
    ),
    UpgradeDef(
      UpgradeType.offlineCap,
      '🌙',
      10,
      1500,
      2.6,
      feature: Feature.offlineCap,
    ),
  ];

  static UpgradeDef of(UpgradeType t) => all.firstWhere((u) => u.type == t);

  static double spawnInterval(int lv) => max(0.7, 4.5 * pow(0.9, lv));
  static double incomeMultiplier(int lv) => 1 + 0.25 * lv;
  static double? autoMergeInterval(int lv) =>
      lv <= 0 ? null : max(0.6, 8.0 * pow(0.86, lv - 1));
  static int spawnLevel(int lv) => 1 + lv;
  static Duration offlineCap(int lv) => Duration(hours: 2 + lv);
}

// ------------------------------------------------------------------ 친구

enum FriendBuff {
  spawnSpeed,
  income,
  orderCoins,
  lucky,
  offline,
  starBonus,
  autoMerge,
}

class FriendDef {
  final String id;
  final String emoji;
  final FriendBuff buff;
  final double perLevel; // 호감도 1당 효과
  const FriendDef(this.id, this.emoji, this.buff, this.perLevel);

  /// 문구 키: friend.bori.name / .species / .line
  String key(String field) => 'friend.$id.$field';
}

class Friends {
  static const List<FriendDef> all = [
    FriendDef('bori', '🐰', FriendBuff.spawnSpeed, 0.03),
    FriendDef('dubu', '🐻', FriendBuff.income, 0.05),
    FriendDef('kwak', '🦆', FriendBuff.orderCoins, 0.10),
    FriendDef('nabi', '🐱', FriendBuff.lucky, 0.01),
    FriendDef('dotori', '🐿️', FriendBuff.offline, 0.03),
    FriendDef('mochi', '🐼', FriendBuff.income, 0.05),
    FriendDef('danpung', '🦊', FriendBuff.starBonus, 0.03),
    FriendDef('kongtteok', '🐹', FriendBuff.autoMerge, 0.04),
  ];

  static FriendDef byId(String id) => all.firstWhere((f) => f.id == id);

  static const String starter = 'bori';
  static const int maxAffection = 10;

  /// 부탁 N번 들어줄 때마다 호감도 1.
  static const int deliveriesPerAffection = 2;

  static const String visitorEmoji = '🦔';
}

// ------------------------------------------------------------------ 정원

class DecorDef {
  final String id; // 문구 키: decor.<id>
  final String emoji;
  final double x; // 정원 씬 안의 상대 위치 (0~1)
  final double y;
  final String? bringsFriend; // 설치하면 놀러 오는 친구
  const DecorDef(this.id, this.emoji, this.x, this.y, {this.bringsFriend});

  String get key => 'decor.$id';
}

class AreaDef {
  final String id; // 문구 키: area.<id>
  final String emoji;
  final int sky; // 배경 색 (아트 전 임시)
  final int ground;
  final List<DecorDef> decor;
  final int round; // 순환 회차 (1부터)
  const AreaDef(
    this.id,
    this.emoji,
    this.sky,
    this.ground,
    this.decor, {
    this.round = 1,
  });

  String get key => 'area.$id';
}

class Garden {
  static const int slotsPerArea = 8;

  static const List<AreaDef> areas = [
    AreaDef('yard', '🏡', 0xFFBFE6F7, 0xFFA8D88E, [
      DecorDef('big_tree', '🌳', 0.14, 0.30),
      DecorDef('bench', '🪑', 0.42, 0.34),
      DecorDef('mailbox', '📮', 0.70, 0.30),
      DecorDef('veggie_patch', '🥕', 0.88, 0.52, bringsFriend: 'dubu'),
      DecorDef('lantern', '🏮', 0.12, 0.74),
      DecorDef('bird_feeder', '🐦', 0.38, 0.70),
      DecorDef('hut', '🛖', 0.64, 0.76),
      DecorDef('fountain', '⛲', 0.88, 0.84),
    ]),
    AreaDef('pond', '🦆', 0xFFC6E2FA, 0xFF9CD3B0, [
      DecorDef('stepping_stones', '🪨', 0.14, 0.32),
      DecorDef('water_lily', '🪷', 0.42, 0.30, bringsFriend: 'kwak'),
      DecorDef('fishing_spot', '🎣', 0.70, 0.34),
      DecorDef('rowboat', '🛶', 0.88, 0.52),
      DecorDef('reeds', '🌾', 0.12, 0.74),
      DecorDef('log_chair', '🪵', 0.38, 0.70, bringsFriend: 'nabi'),
      DecorDef('tent', '🏕️', 0.64, 0.76),
      DecorDef('wooden_bridge', '🌉', 0.88, 0.84),
    ]),
    AreaDef('greenhouse', '🪴', 0xFFF6E3F0, 0xFFB9DFA0, [
      DecorDef('glasshouse', '🪟', 0.14, 0.30),
      DecorDef('cactus', '🌵', 0.42, 0.34),
      DecorDef('mushroom_bed', '🍄', 0.70, 0.30, bringsFriend: 'dotori'),
      DecorDef('watering_can', '🚿', 0.88, 0.52),
      DecorDef('sunflower_field', '🌻', 0.12, 0.74),
      DecorDef('tea_table', '🫖', 0.38, 0.70),
      DecorDef('bamboo', '🎋', 0.64, 0.76, bringsFriend: 'mochi'),
      DecorDef('wind_chime', '🎐', 0.88, 0.84),
    ]),
    AreaDef('starry_hill', '🌙', 0xFF2E3A6B, 0xFF6F9A6A, [
      DecorDef('telescope', '🔭', 0.14, 0.30),
      DecorDef('camp_tent', '⛺', 0.42, 0.34),
      DecorDef('campfire', '🔥', 0.70, 0.30, bringsFriend: 'danpung'),
      DecorDef('ferris_wheel', '🎡', 0.88, 0.52),
      DecorDef('carousel', '🎠', 0.12, 0.74),
      DecorDef('moon_statue', '🌙', 0.38, 0.70),
      DecorDef('little_castle', '🏰', 0.64, 0.76, bringsFriend: 'kongtteok'),
      DecorDef('fireworks', '🎆', 0.88, 0.84),
    ]),
  ];

  /// 정해진 구역 이후로는 순환하며 무한 진행 (새 친구 없음).
  static AreaDef areaAt(int index) {
    final base = areas[index % areas.length];
    if (index < areas.length) return base;
    final decor = [
      for (final d in base.decor) DecorDef(d.id, d.emoji, d.x, d.y),
    ];
    return AreaDef(
      base.id,
      base.emoji,
      base.sky,
      base.ground,
      decor,
      round: index ~/ areas.length + 1,
    );
  }

  /// 장식 별 비용. 구역이 올라갈수록 비싸진다.
  static int decorCost(int area, int slot) =>
      ((1 + slot ~/ 2) * pow(2.0, area)).ceil();

  /// 부탁 아이템 레벨의 중심값 (구역, 설치한 장식 수 기준).
  static double orderLevelCenter(int area, int placed) =>
      min(13.5, 3.0 + area * 2.5 + placed * 0.3);

  /// 부탁 1건의 별 보상.
  static int orderStars(int level) => 1 + (level - 2) ~/ 3;
}

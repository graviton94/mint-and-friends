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

  // ---- 에너지 (머지 장르 표준: 상한 100, 2분에 1, 탭 1회 = 1)
  static const int energyCap = 100;
  static const int energyRegenSeconds = 120;
  static const int energyPerTap = 1;
  static const int energyStart = 100;

  /// 보상형 광고 1회 에너지 (+25, 하루 4회 = 100).
  static const int energyAdAmount = 25;

  /// 보상형 광고 종류별 하루 횟수 상한 (합계 약 20회/일, 장르 평균 10~20회).
  static const Map<AdKind, int> adDailyCap = {
    AdKind.energy: 4,
    AdKind.boost: 6,
    AdKind.coinBag: 5,
    AdKind.refresh: 5,
  };

  /// 장식 1개 / 구역 완성 시 정원 매력도 (수익 배율) 증가.
  static const double decorIncomeBonus = 0.10;
  static const double areaIncomeBonus = 0.50;
}

/// 하루 횟수 제한이 있는 보상형 광고 종류 (오프라인 2배·손님·비눗방울은 제한 없음).
enum AdKind { energy, boost, coinBag, refresh }

// ------------------------------------------------------------------ 레벨, 해금

/// 플레이어 레벨에 따라 열리는 기능.
enum Feature {
  energyAd,
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
  /// 장르 기준(Merge Mansion 실측 x1.12~1.13): 초반은 가파르게(x1.25), Lv9 이후 완만하게(x1.12).
  /// 누적: Lv10 ≈ 520, Lv20 ≈ 2.8K, Lv30 ≈ 9.3K, Lv40 ≈ 29K, Lv50 ≈ 90K
  /// 기준값 = 초반 부탁 약 4건 분량 (부탁 1건 = 별1 = 5xp).
  static const double _xpBase = 20;
  static int xpToNext(int level) {
    if (level < 9) return (_xpBase * pow(1.25, level - 1)).round();
    return (_xpBase * pow(1.25, 8) * pow(1.12, level - 9)).round();
  }

  /// 기능별 해금 레벨.
  static const Map<Feature, int> unlockLevel = {
    Feature.energyAd: 2,
    Feature.upgrades: 2,
    Feature.boost: 3,
    Feature.snack: 3,
    Feature.coinBag: 4,
    Feature.autoMerge: 6,
    Feature.visitor: 7,
    Feature.offlineCap: 8,
    Feature.spawnLevel: 12,
  };

  /// 구역별 입장 레벨. 별이 있어도 레벨이 낮으면 다음 구역을 꾸밀 수 없다.
  static const List<int> _areaLevels = [1, 5, 10, 15, 20];
  static int areaLevel(int area) => area < _areaLevels.length
      ? _areaLevels[area]
      : _areaLevels.last + (area - _areaLevels.length + 1) * 4;

  /// 강화 단계 상한 = 플레이어 레벨 기준.
  static int upgradeCap(int playerLevel) => 4 + playerLevel * 3;

  /// n번째(0부터) 칸 구매에 필요한 레벨. 바깥 18칸이 Lv32 까지 나뉘어 열린다 (약 한 달).
  static const List<int> _cellLevels = [
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    12,
    14,
    16,
    18,
    20,
    23,
    26,
    29,
    32,
  ];
  static int cellLevel(int n) =>
      n < _cellLevels.length ? _cellLevels[n] : _cellLevels.last;

  /// 경험치: 부탁·꾸미기 위주 (머지 장르 표준). 합치기는 경험치 없음.
  static int xpForMerge(int resultLevel) => 0;

  /// 부탁 경험치는 요구 아이템 레벨에 비례 (높은 단계일수록 에너지가 많이 드는 만큼 보상).
  static int xpForOrder(int itemLevel) => 2 * itemLevel - 2;
  static int xpForDecor(int cost) => 2 * cost;
  static const int xpForDiscovery = 2;

  /// 레벨업 보상: 코인(초당 수익 N초분, 최소 보장) + 별 1 + 에너지.
  /// 에너지는 Lv10 까지 +25, 이후 +20.
  static const double levelUpCoinSeconds = 120;
  static const int levelUpStars = 0; // 별은 부탁으로만 (꾸미기 속도 조절)
  static int levelUpEnergy(int newLevel, int current) =>
      newLevel <= 10 ? 25 : 20;

  static List<Feature> unlockedAt(int level) => [
    for (final e in unlockLevel.entries)
      if (e.value == level) e.key,
  ];
}

/// 칸 구매 비용 (지금까지 산 칸 수 기준, 살수록 비싸짐).
double cellCost(int purchased) => 300 * pow(1.8, purchased).toDouble();

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

/// 강화. 방치형 기준(AdVenture Capitalist 1.07, Cookie Clicker 1.15, 펭귄의 섬 1.2):
/// 비용은 단계마다 x1.13~1.15, 수익 강화는 x1.08 + 10/25/50/100 단계 달성 시 x2.
class Upgrades {
  static const List<UpgradeDef> all = [
    UpgradeDef(UpgradeType.spawnSpeed, 'timer', 30, 40, 1.15),
    UpgradeDef(UpgradeType.income, 'coinbag', 100, 60, 1.13),
    UpgradeDef(
      UpgradeType.autoMerge,
      'auto',
      30,
      500,
      1.15,
      feature: Feature.autoMerge,
    ),
    UpgradeDef(
      UpgradeType.spawnLevel,
      'quality',
      4,
      20000,
      12,
      feature: Feature.spawnLevel,
    ),
    UpgradeDef(
      UpgradeType.offlineCap,
      'moon',
      8,
      2000,
      1.6,
      feature: Feature.offlineCap,
    ),
  ];

  static UpgradeDef of(UpgradeType t) => all.firstWhere((u) => u.type == t);

  /// 바구니가 저절로 만드는 간격(초). 탭(에너지)이 주 생산, 자동 생성은 방치용 보조.
  static double spawnInterval(int lv) => max(3.0, 15.0 * pow(0.95, lv));

  static const List<int> incomeMilestones = [10, 25, 50, 100];
  static double incomeMultiplier(int lv) =>
      pow(1.08, lv) *
      pow(2, incomeMilestones.where((m) => lv >= m).length).toDouble();

  static double? autoMergeInterval(int lv) =>
      lv <= 0 ? null : max(1.0, 10.0 * pow(0.93, lv - 1));
  static int spawnLevel(int lv) => 1 + lv;

  /// 오프라인 수익 최대 시간: 2시간 + 30분씩, 최대 6시간.
  static Duration offlineCap(int lv) => Duration(minutes: 120 + 30 * lv);
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

/// 친구들이 걸어 다닐 수 있는 땅 (씬 대비 0~1 사각형). 배경 그림의 물·길을 피한다.
class WalkZone {
  final double x0, y0, x1, y1;
  const WalkZone(this.x0, this.y0, this.x1, this.y1);
}

/// 물 영역 (타원, 씬 대비 0~1). 친구가 들어가면 첨벙 효과와 함께 몸 아래가 잠겨 보인다.
class WaterZone {
  final double cx, cy, rx, ry;
  const WaterZone(this.cx, this.cy, this.rx, this.ry);
  bool contains(double x, double y) {
    final dx = (x - cx) / rx, dy = (y - cy) / ry;
    return dx * dx + dy * dy <= 1;
  }
}

class AreaDef {
  final String id; // 문구 키: area.<id>
  final String emoji;
  final int sky; // 배경 색 (아트 전 임시)
  final int ground;
  final List<DecorDef> decor;
  final int round; // 순환 회차 (1부터)
  final List<WalkZone> walk;
  final List<WaterZone> water;
  const AreaDef(
    this.id,
    this.emoji,
    this.sky,
    this.ground,
    this.decor, {
    this.round = 1,
    this.walk = const [WalkZone(0.08, 0.42, 0.92, 0.92)],
    this.water = const [],
  });

  String get key => 'area.$id';
}

class Garden {
  static const int slotsPerArea = 8;

  static const List<AreaDef> areas = [
    AreaDef('yard', '🏡', 0xFFBFE6F7, 0xFFA8D88E, [
      DecorDef('big_tree', '🌳', 0.12, 0.44),
      DecorDef('bench', '🪑', 0.36, 0.40),
      DecorDef('mailbox', '📮', 0.64, 0.36),
      DecorDef('veggie_patch', '🥕', 0.56, 0.58, bringsFriend: 'dubu'),
      DecorDef('lantern', '🏮', 0.10, 0.80),
      DecorDef('bird_feeder', '🐦', 0.32, 0.74),
      DecorDef('hut', '🛖', 0.90, 0.64),
      DecorDef('fountain', '⛲', 0.86, 0.90),
    ]),
    AreaDef(
      'pond',
      '🦆',
      0xFFC6E2FA,
      0xFF9CD3B0,
      [
        DecorDef('stepping_stones', '🪨', 0.12, 0.60),
        DecorDef('water_lily', '🪷', 0.45, 0.58, bringsFriend: 'kwak'),
        DecorDef('fishing_spot', '🎣', 0.76, 0.46),
        DecorDef('rowboat', '🛶', 0.62, 0.70),
        DecorDef('reeds', '🌾', 0.08, 0.86),
        DecorDef('log_chair', '🪵', 0.32, 0.92, bringsFriend: 'nabi'),
        DecorDef('tent', '🏕️', 0.84, 0.90),
        DecorDef('wooden_bridge', '🌉', 0.26, 0.44),
      ],
      walk: [WalkZone(0.06, 0.44, 0.94, 0.94)],
      water: [WaterZone(0.52, 0.58, 0.46, 0.21)],
    ),
    AreaDef('greenhouse', '🪴', 0xFFF6E3F0, 0xFFB9DFA0, [
      DecorDef('glasshouse', '🪟', 0.10, 0.40),
      DecorDef('cactus', '🌵', 0.24, 0.48),
      DecorDef('mushroom_bed', '🍄', 0.72, 0.48, bringsFriend: 'dotori'),
      DecorDef('watering_can', '🚿', 0.50, 0.50),
      DecorDef('sunflower_field', '🌻', 0.20, 0.70),
      DecorDef('tea_table', '🫖', 0.50, 0.78),
      DecorDef('bamboo', '🎋', 0.80, 0.70, bringsFriend: 'mochi'),
      DecorDef('wind_chime', '🎐', 0.92, 0.90),
    ]),
    AreaDef('starry_hill', '🌙', 0xFF2E3A6B, 0xFF6F9A6A, [
      DecorDef('telescope', '🔭', 0.14, 0.46),
      DecorDef('camp_tent', '⛺', 0.42, 0.44),
      DecorDef('campfire', '🔥', 0.70, 0.48, bringsFriend: 'danpung'),
      DecorDef('ferris_wheel', '🎡', 0.88, 0.56),
      DecorDef('carousel', '🎠', 0.14, 0.78),
      DecorDef('moon_statue', '🌙', 0.40, 0.74),
      DecorDef('little_castle', '🏰', 0.66, 0.80, bringsFriend: 'kongtteok'),
      DecorDef('fireworks', '🎆', 0.90, 0.88),
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
      walk: base.walk,
      water: base.water,
    );
  }

  /// 장식 별 비용. 구역이 올라갈수록 비싸진다.
  static int decorCost(int area, int slot) =>
      ((1 + slot ~/ 2) * pow(2.0, area)).ceil();

  /// 부탁 아이템 레벨의 중심값 (구역, 설치한 장식 수 기준).
  static double orderLevelCenter(int area, int placed) =>
      min(13.5, 4.0 + area * 2.2 + placed * 0.25);

  /// 부탁 1건의 별 보상.
  static int orderStars(int level) => 1 + (level - 2) ~/ 3;
}

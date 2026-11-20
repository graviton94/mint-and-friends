import 'dart:math';

import 'meta.dart' show Reward;
import 'tuning.dart';

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

  // ---- 코인 (머지 장르 기준: 코인은 주로 부탁으로 번다. 방치 수익은 부탁 수입의 약 10%)
  // 참고: Merge Mansion · Gossip Harbor 등 — 에너지 1 ≈ 코인 1, 코인은 칸 · 보관함 · 강화에 쓴다.

  /// 판 위 아이템 1개의 초당 방치 수익 (시간당 단계만큼 코인. 지수로 늘지 않는다).
  /// 칸마다 시간당 값을 작게 표시하므로 정수로 떨어지게 둔다. 오프라인은 감쇄가 걸린다.
  static double incomeOf(int level) => level / 3600;

  /// 부탁 보상 코인의 기준 (아이템을 만드는 데 든 에너지 수 = 2^(단계-1)).
  static double orderCoinsOf(int level) => pow(2, level - 1).toDouble();

  /// 판매 가격: 만드는 데 든 에너지의 절반 (최소 1).
  static double sellValueOf(int level) => max(1, pow(2, level - 1) * 0.5);

  /// 판매 되돌리기 가능 시간.
  static const Duration sellUndoWindow = Duration(seconds: 6);

  /// 최고 레벨 두 개를 합치면 사라지면서 지급되는 코인.
  static double maxMergePayoutOf(int level) => 20.0 * level;

  /// 신규 아이템 발견 보너스 코인.
  static double discoveryBonusOf(int level) => 3.0 * level;

  /// 바구니에서 2단계가 나올 확률 (기본). 바구니 품질 강화로 더 오른다.
  static const double luckySpawnChance = 0.08;

  /// 합칠 때 같은 아이템이 든 비눗방울이 생길 확률. 광고를 보면 꺼내서 가질 수 있다.
  static const double bubbleChance = 0.05;
  static const Duration bubbleLife = Duration(seconds: 60);
  static const int bubbleMinLevel = 4;

  /// 오프라인 보상: 최소 자리 비움 시간 (이보다 짧으면 보상 없음).
  static const Duration offlineMinAway = Duration(minutes: 15);

  /// 오프라인 수익 감쇄 (방치 장르 공통): 처음 1시간 50%, 1~3시간 25%, 그 뒤 10%.
  /// [seconds] 동안 초당 [perSec] 를 벌 때 받는 양.
  static double offlineEarnings(double perSec, double seconds) {
    const tiers = [(3600.0, 0.5), (7200.0, 0.25), (double.infinity, 0.10)];
    var left = seconds, sum = 0.0;
    for (final (span, rate) in tiers) {
      final t = min(left, span);
      sum += perSec * t * rate;
      left -= t;
      if (left <= 0) break;
    }
    return sum;
  }

  /// 보상형 광고: 코인 2배 (부탁 · 방치 수익 모두) 1회당 시간, 최대 누적.
  static const Duration boostPerAd = Duration(minutes: 15);
  static const Duration boostMax = Duration(minutes: 60);

  /// 보상형 광고: 코인 주머니 = 20 + 8 × 레벨, 쿨다운.
  static double coinBagOf(int playerLevel) => 20.0 + 8 * playerLevel;
  static const Duration coinBagCooldown = Duration(minutes: 30);

  /// 전면 광고 최소 간격, 앱 시작 후 유예.
  static const Duration interstitialGap = Duration(minutes: 3);
  static const Duration interstitialGrace = Duration(minutes: 2);

  /// 동시에 떠 있는 부탁 수.
  static const int orderSlots = 3;

  /// 친구 탭 보상 코인, 친구별 쿨다운 (작은 즐거움).
  static const double friendTapCoins = 1;
  static const Duration friendTapCooldown = Duration(seconds: 30);

  /// 깜짝 손님.
  static const Duration visitorMinGap = Duration(minutes: 6);
  static const Duration visitorMaxGap = Duration(minutes: 12);
  static const Duration visitorStay = Duration(seconds: 50);
  static double visitorCoinsOf(int playerLevel) =>
      10.0 + 3 * playerLevel; // 그냥 받기
  static const double visitorAdMultiplier = 3; // 광고 보고 받기
  static const int visitorAdStars = 5;

  /// 구조 부탁(판에 막힌 고단계 아이템을 원하는 부탁) 최소 간격. 확률은 Tuning.rescueChance.
  static const Duration rescueOrderGap = Duration(minutes: 10);

  // ---- 에너지 (장르: 상한 100 · 2분에 1. 캐주얼 3~4회 접속에 맞춰 2분 30초로 조금 느리게)
  static const int energyCap = 100;
  static const int energyRegenSeconds = 150;
  static const int energyPerTap = 1;
  static const int energyStart = 100;

  /// 보상형 광고 1회 에너지 (장르 15~25), 하루 5회 = 100. 에너지가 이만큼 아래일 때만 제안.
  static const int energyAdAmount = 20;
  static const int energyAdBelow = 20;

  /// 보상형 광고 종류별 하루 횟수 상한.
  static const Map<AdKind, int> adDailyCap = {
    AdKind.energy: 5,
    AdKind.boost: 4,
    AdKind.coinBag: 5,
    AdKind.refresh: 3,
  };

  /// 장식 1개 / 구역 완성 시 정원 매력도 (코인 배율) 증가.
  static const double decorIncomeBonus = 0.02;
  static const double areaIncomeBonus = 0.10;
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
  storage,
}

class Leveling {
  /// 다음 레벨까지 필요한 경험치.
  /// 장르 기준(Merge Mansion 실측 x1.12~1.13): 초반은 가파르게(x1.25), Lv9 이후 완만하게(x1.12).
  /// 누적: Lv10 ≈ 520, Lv20 ≈ 2.8K, Lv30 ≈ 9.3K, Lv40 ≈ 29K, Lv50 ≈ 90K
  /// 기준값 = 초반 부탁 약 4건 분량 (부탁 1건 = 별1 = 5xp).
  /// 장르 조사 곡선(10 + 5·(L−1)^1.6)에 1.3배: 시뮬레이션(하루 4회 × 12분)에서
  /// Lv5 첫 세션 · Lv10 2~3일 · Lv20 약 2주 · Lv30 약 6주가 되도록 맞춘 값.
  static int xpToNext(int level) => (13 + 6.5 * pow(level - 1, 1.6)).round();

  /// 기능별 해금 레벨.
  static const Map<Feature, int> unlockLevel = {
    Feature.energyAd: 2,
    Feature.upgrades: 2,
    Feature.boost: 3,
    Feature.snack: 3,
    Feature.coinBag: 4,
    Feature.storage: 5,
    Feature.autoMerge: 6,
    Feature.visitor: 7,
    Feature.offlineCap: 8,
    Feature.spawnLevel: 10,
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

  /// 부탁 경험치: 아이템 단계별 표 (에너지 1 ≈ 경험치 0.7).
  static const List<int> _orderXp = [
    1,
    1,
    3,
    6,
    11,
    22,
    45,
    80,
    130,
    200,
    300,
    450,
    650,
    900,
    1200,
  ];
  static int xpForOrder(int itemLevel) =>
      _orderXp[(itemLevel - 1).clamp(0, _orderXp.length - 1)];

  /// 장식 경험치: 별 가격이 아니라 구역 · 자리 기준 (별이 에너지 비례로 커져도 레벨 속도는 그대로).
  static int xpForDecor(int area, int slot) => (2 + slot ~/ 2) * (1 + area);

  /// 부탁 아이템 단계의 중심값: 플레이어 레벨 기준 (Lv1 ≈ 3, Lv10 = 5, Lv20 이상 7.5).
  static double orderLevelCenter(int playerLevel) =>
      min(7.5, 2.5 + playerLevel * 0.25);

  /// 레벨업 코인.
  static double levelUpCoins(int newLevel) => 10.0 + 5 * newLevel;
  static const int xpForDiscovery = 2;

  /// 레벨업 에너지: Lv10 까지 +15, 이후 +10 (작은 선물. 에너지는 회복 · 광고가 주 공급원).
  static const int levelUpStars = 0; // 별은 부탁으로만 (꾸미기 속도 조절)
  static int levelUpEnergy(int newLevel, int current) =>
      newLevel <= 10 ? 15 : 10;

  static List<Feature> unlockedAt(int level) => [
    for (final e in unlockLevel.entries)
      if (e.value == level) e.key,
  ];
}

/// 칸 구매 비용 (지금까지 산 칸 수 기준, 살수록 비싸짐).
/// n번째(0부터) 칸 구매 비용: 150 × 1.3^n (Merge Mansion 보관함 +20%/칸보다 조금 가파르게).
double cellCost(int purchased) => 150 * pow(1.3, purchased).toDouble();

/// 보관함: 판 밖에 아이템을 맡겨 두는 칸 (수익·부탁 대상 아님).
/// 장르 기준(Travel Town·Merge Mansion): 처음 2칸, 칸마다 비용이 가파르게 오른다.
class Storage {
  static const int startSlots = 2;
  static const int maxSlots = 10;

  /// n번째(0부터) 추가 칸 비용: 50 × 1.2^n (Merge Mansion 보관함과 같은 +20%/칸).
  static double slotCost(int purchased) => 50 * pow(1.2, purchased).toDouble();
}

// ------------------------------------------------------------------ 아이템

enum Chain { flower, snack, tea, stardust }

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
    // 새 체인은 그림이 들어와야 열린다 (이모지 대체 없음)
    Chain.tea: ['', '', '', '', '', '', '', '', '', ''],
    Chain.stardust: ['', '', '', '', '', '', '', '', '', ''],
  };

  /// 체인별 최고 단계: 꽃 · 간식 15, 구역 체인(찻잎 · 별가루) 10 (바이블 §5.1).
  static int maxLevel(Chain c) =>
      c == Chain.tea || c == Chain.stardust ? 10 : GameConfig.maxLevel;

  static ItemDef item(Chain c, int level) {
    final l = level.clamp(1, maxLevel(c));
    return ItemDef(c, l, _emoji[c]![l - 1]);
  }

  /// 체인 그림이 준비됐는지 (Art.init 이 바꿔 낀다). 기본: 꽃 · 간식만.
  static bool Function(Chain c) ready = (c) =>
      c == Chain.flower || c == Chain.snack;

  /// 바구니: 0 정원 바구니(꽃 · 간식), 1 찻잎 바구니(온실 구역부터), 2 별가루 병(별빛 언덕부터).
  static const List<List<Chain>> baskets = [
    [Chain.flower, Chain.snack],
    [Chain.tea],
    [Chain.stardust],
  ];
  static const List<int> basketArea = [0, 2, 3];
  static const List<String> basketIcon = ['basket', 'tea_basket', 'star_jar'];
}

// ------------------------------------------------------------------ 강화

enum UpgradeType {
  energyRegen,
  income,
  autoMerge,
  spawnLevel,
  offlineCap,
  flowerPower,
  snackPower,
}

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
    UpgradeDef(UpgradeType.energyRegen, 'timer', 30, 100, 1.18),
    UpgradeDef(UpgradeType.income, 'coinbag', 20, 80, 1.25),
    UpgradeDef(
      UpgradeType.autoMerge,
      'auto',
      20,
      400,
      1.3,
      feature: Feature.autoMerge,
    ),
    UpgradeDef(
      UpgradeType.spawnLevel,
      'quality',
      3,
      500,
      3,
      feature: Feature.spawnLevel,
    ),
    UpgradeDef(
      UpgradeType.offlineCap,
      'moon',
      8,
      300,
      1.6,
      feature: Feature.offlineCap,
    ),
    // 생산력 강화는 끝이 없다 (머지 · 방치 장르의 후반 코인 소모처): 비용은 단계마다 ×1.28 로
    // 지수 증가, 효과는 +20% 로 선형 증가라 저절로 느려진다. 레벨 상한(4 + 3·레벨)으로만 막힌다.
    UpgradeDef(
      UpgradeType.flowerPower,
      'item:flower:6',
      Upgrades.endless,
      60,
      1.28,
    ),
    UpgradeDef(
      UpgradeType.snackPower,
      'item:snack:6',
      Upgrades.endless,
      60,
      1.28,
      feature: Feature.snack,
    ),
  ];

  static const int endless = 9999;

  static UpgradeDef of(UpgradeType t) => all.firstWhere((u) => u.type == t);

  /// 종류별 생산력 강화 (꽃 · 간식): 그 종류 아이템의 방치 수익 +20% / 단계.
  static double chainPower(int lv) => 1 + 0.2 * lv;

  /// 찻잎은 꽃 생산력, 별가루는 간식 생산력을 따른다.
  static UpgradeType powerOf(Chain c) => c == Chain.flower || c == Chain.tea
      ? UpgradeType.flowerPower
      : UpgradeType.snackPower;

  /// 에너지 1 회복 간격(초). 아이템은 바구니 탭(에너지 1)으로만 나온다 (머지 장르 표준:
  /// Merge Mansion · Travel Town 모두 생산은 에너지, 방치 요소는 수익·자동 합치기).
  static double energyRegenSeconds(int lv) =>
      max(60.0, Tuning.energyRegenSeconds * pow(0.98, lv).toDouble());

  /// 방치 수익 배율: 단계마다 +5% (최대 20단계 = ×2). 크게 키우면 방치 수익이 부탁 수입을 압도한다.
  static double incomeMultiplier(int lv) => 1 + 0.05 * lv;

  static double? autoMergeInterval(int lv) =>
      lv <= 0 ? null : max(1.0, 10.0 * pow(0.93, lv - 1));

  /// 바구니 품질: 2단계가 나올 확률 추가 (+4% / 단계).
  static double qualityChance(int lv) => 0.04 * lv;

  /// 오프라인 수익 최대 시간: 2시간 + 30분씩, 최대 6시간.
  static Duration offlineCap(int lv) => Duration(minutes: 120 + 30 * lv);
}

// ------------------------------------------------------------------ 친구

enum FriendBuff {
  energyRegen,
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
    FriendDef('bori', '🐰', FriendBuff.energyRegen, 0.03),
    FriendDef('dubu', '🐻', FriendBuff.income, 0.05),
    FriendDef('kwak', '🦆', FriendBuff.orderCoins, 0.10),
    FriendDef('nabi', '🐱', FriendBuff.lucky, 0.01),
    FriendDef('dotori', '🐿️', FriendBuff.offline, 0.03),
    FriendDef('mochi', '🐼', FriendBuff.income, 0.05),
    FriendDef('danpung', '🦊', FriendBuff.starBonus, 0.03),
    FriendDef('kongtteok', '🐹', FriendBuff.autoMerge, 0.04),
    // 5 · 6구역 친구 (그림이 들어오면 그 구역과 함께 열린다)
    FriendDef('bogeul', '🦦', FriendBuff.orderCoins, 0.08),
    FriendDef('pposong', '🐧', FriendBuff.energyRegen, 0.03),
  ];

  /// 처음부터 있던 친구 (그림 걱정 없이 도감에 보인다).
  static const int coreCount = 8;

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
    // 5 · 6구역: 배경 · 장식 · 친구 그림이 모두 들어와야 열린다 (그 전에는 1~4구역 순환)
    AreaDef('seaside', '🏖️', 0xFFBDE8F5, 0xFFF3E3B8, [
      DecorDef('beach_hut', '🛖', 0.12, 0.44),
      DecorDef('parasol', '⛱️', 0.36, 0.42),
      DecorDef('lighthouse', '🗼', 0.86, 0.40),
      DecorDef('sandcastle', '🏰', 0.58, 0.58, bringsFriend: 'bogeul'),
      DecorDef('deck_chair', '🪑', 0.12, 0.80),
      DecorDef('shell_fountain', '🐚', 0.36, 0.74),
      DecorDef('surf_rack', '🏄', 0.88, 0.66),
      DecorDef('seagull_post', '🪵', 0.66, 0.90),
    ]),
    AreaDef('snow_village', '❄️', 0xFFDDE9F5, 0xFFF4F7FA, [
      DecorDef('chimney_cottage', '🏠', 0.12, 0.42),
      DecorDef('winter_tree', '🎄', 0.36, 0.44),
      DecorDef('snowman', '⛄', 0.62, 0.46),
      DecorDef('igloo', '🛖', 0.88, 0.50),
      DecorDef('sled', '🛷', 0.16, 0.78),
      DecorDef('cocoa_stand', '☕', 0.42, 0.72),
      DecorDef('ice_rink', '⛸️', 0.68, 0.80, bringsFriend: 'pposong'),
      DecorDef('snow_lantern', '🏮', 0.90, 0.90),
    ]),
  ];

  static const int coreAreas = 4;

  /// 구역 그림이 준비됐는지 (Art.init 이 바꿔 낀다). 기본: 1~4구역만.
  static bool Function(AreaDef a) ready = (a) => areas.indexOf(a) < coreAreas;

  /// 지금 열 수 있는 구역들 (순환은 이 목록 기준).
  static List<AreaDef> get live => [
    for (final a in areas)
      if (ready(a)) a,
  ];

  /// 정해진 구역 이후로는 순환하며 무한 진행 (새 친구 없음).
  static AreaDef areaAt(int index) {
    final list = live;
    final base = list[index % list.length];
    if (index < list.length) return base;
    final decor = [
      for (final d in base.decor) DecorDef(d.id, d.emoji, d.x, d.y),
    ];
    return AreaDef(
      base.id,
      base.emoji,
      base.sky,
      base.ground,
      decor,
      round: index ~/ list.length + 1,
      walk: base.walk,
      water: base.water,
    );
  }

  /// 장식 별 비용: 구역 안에서 2 → 5, 구역마다 (1 + 구역) 배. 앞마당 28, 연못 56, 온실 84 …
  static int decorCost(int area, int slot) =>
      max(1, (areaStars(area) * (2 + slot ~/ 2) / 28).round());

  /// 구역 하나를 다 꾸미는 데 드는 별 (하루 에너지 약 480 → 별 약 120 기준).
  /// 1구역 첫 15~20분, 2구역 1~2일차, 3구역 4~5일차, 4구역 10일차, 5구역 20일차, 6구역 한 달.
  static const List<int> _areaStars = [24, 160, 480, 1150, 2350, 4200];
  static int areaStars(int area) =>
      ((area < _areaStars.length
                  ? _areaStars[area]
                  : _areaStars.last * pow(1.6, area - _areaStars.length + 1)) *
              Tuning.areaStarScale)
          .round();

  /// 장식 디자인 (바이블 D-005): 0 기본(별) · 1 고급(코인, 별값 × 120 ≈ 하루 수입 0.5~1일치) · 2 특별(다이아).
  static const int styles = 3;
  static int styleCoins(int area, int slot) => decorCost(area, slot) * 120;
  static int styleGems(int area) => 25 + 5 * min(area, 11);

  /// 부탁 1건의 별 보상: 에너지 10 이하(≤4단계) 1, 30 이하(5단계) 2, 그 이상 3.
  static int orderStars(int level) => level <= 3
      ? 1
      : (pow(2, level - 1) / 4 * (1 + 0.05 * (level - 3))).round();
}

// ------------------------------------------------------------------ 다이아 (하드 통화)

/// 다이아 팩 (Play 인앱 상품, 소모형). 가격은 스토어 값이 우선, krw 는 스토어 연결 전 표시용.
class GemPack {
  final String id;
  final int gems;
  final int krw;
  const GemPack(this.id, this.gems, this.krw);

  /// 가장 작은 팩 대비 보너스 % (한 줌 60개 / ₩1,200 기준).
  int get bonusPct => (gems / (krw * 60 / 1200) * 100 - 100).round();
}

/// 바이블 §6: 무료 다이아는 하루 평균 5~10개, 에너지 100 = 다이아 40 (Travel Town 기준).
class Gems {
  static const List<GemPack> packs = [
    GemPack('gems_60', 60, 1200),
    GemPack('gems_330', 330, 5900),
    GemPack('gems_700', 700, 12000),
    GemPack('gems_1800', 1800, 29000),
    GemPack('gems_3800', 3800, 59000),
  ];

  static GemPack? pack(String id) => packs.where((p) => p.id == id).firstOrNull;

  /// 레벨업마다 무료 다이아.
  static const int levelUp = 3;

  /// 에너지 충전: 하루 안에 다시 살수록 비싸진다 (40 → 60 → 80 … 최대 120).
  static const int refillEnergy = 100;
  static int refillCost(int boughtToday) => min(
    Tuning.refillMax,
    Tuning.refillBase + Tuning.refillStep * boughtToday,
  );

  /// 비눗방울 바로 열기: 남은 20초마다 1개, 최소 2개.
  static int bubbleCost(Duration left) => max(2, (left.inSeconds / 20).ceil());
}

// ------------------------------------------------------------------ 출석 · 오늘의 시장

/// 7일 출석: 빠진 날이 있어도 처음으로 돌아가지 않고 이어서 받는다 (힐링 장르 관례).
/// 한 주 무료 다이아 35개 = 하루 5개 (바이블 §6.1 목표 5~10).
class CheckIn {
  static const int days = 7;
  static Reward reward(int day, int level) => switch (day) {
    0 => const Reward(energy: 20),
    1 => Reward(coins: 40 + 20 * level),
    2 => const Reward(gems: 5),
    3 => const Reward(energy: 40),
    4 => Reward(coins: 2 * (40 + 20 * level)),
    5 => const Reward(gems: 10),
    _ => const Reward(gems: 20, energy: 50),
  };
}

/// 오늘의 시장: 하루 4칸, 낮은 단계 아이템을 코인으로 (후반 코인 소모처 · 외부 보고서 채택).
class DailyShop {
  static const int unlockLevel = 4;
  static const int slots = 4;

  /// 가격: 아이템 에너지값 × (10 + 2·레벨) — 레벨이 오를수록 코인 가치 하락을 따라간다.
  static int price(int itemLevel, int playerLevel) =>
      (pow(2, itemLevel - 1) * (Tuning.marketPriceBase + 2 * playerLevel))
          .round();
}

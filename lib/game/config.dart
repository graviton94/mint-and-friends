import 'dart:math';

import 'meta.dart' show Reward;
import 'tuning.dart';

/// 밸런스와 콘텐츠 상수. 숫자 튜닝은 대부분 이 파일에서 한다.
/// 화면에 보이는 이름·문구는 여기 두지 않는다. id 를 키로 assets/i18n/*.json 에서 찾는다.
/// 이모지는 아트가 들어오기 전까지 쓰는 임시 그림이다 (ArtRegistry 참고).
class GameConfig {
  static const int cols = 6;
  static const int rows = 6;
  static const int cellCount = cols * rows;

  /// 위 5줄(30칸)은 코인으로 여는 칸, 맨 아랫줄 6칸은 보관 칸 (다이아로 영구 해금 · 정원 패스는 2칸).
  static const int coinCells = 30;
  static bool isVault(int i) => i >= coinCells && i < cellCount;
  static const List<int> passVault = [30, 31];

  /// 보관 칸 다이아 가격: 이미 가진 칸 수에 따라 30 · 60 · 90 · …
  static int vaultCost(int owned) => 30 * (owned + 1);

  /// 처음부터 열려 있는 칸: 가운데 4x3.
  static final Set<int> startCells = {
    for (var r = 1; r <= 3; r++)
      for (var c = 1; c <= 4; c++) r * cols + c,
  };

  static const int maxLevel = 30;

  // ---- 코인 (머지 장르 기준: 코인은 주로 부탁으로 번다. 방치 수익은 부탁 수입의 약 10%)
  // 참고: Merge Mansion · Gossip Harbor 등 — 에너지 1 ≈ 코인 1, 코인은 칸 · 보관함 · 강화에 쓴다.

  /// 아이템 가치 (코인 인플레이션의 기준, D-029): 단계마다 ×2.2 → 두 개를 합치면 가치 ×1.1.
  /// 뒤에 열리는 체인일수록 단계당 가치가 크다 (꽃 · 간식 1, 찻잎 3, 별가루 8).
  static const double valueGrowth = 2.2;
  static const Map<Chain, double> chainValue = {
    Chain.flower: 1,
    Chain.snack: 1,
    Chain.tea: 3,
    Chain.stardust: 8,
  };
  static double valueOf(Chain c, int level) =>
      chainValue[c]! *
      pow(valueGrowth, level + Chains.levelOffset(c) - 1) *
      Tuning.coinScale;

  /// 판 위 아이템 1개의 초당 방치 수익: 시간당 가치 1배.
  static double incomeOf(Chain c, int level) => valueOf(c, level) / 3600;

  /// 부탁 보상 코인: 가치 2배 (2시간치 방치 수익).
  static double orderCoinsOf(Chain c, int level) => 2 * valueOf(c, level);

  /// 판매 가격: 가치의 절반 (최소 1).
  static double sellValueOf(Chain c, int level) =>
      max(1, 0.5 * valueOf(c, level));

  /// 판매 되돌리기 가능 시간.
  static const Duration sellUndoWindow = Duration(seconds: 6);

  /// 최고 레벨 두 개를 합치면 사라지면서 지급되는 코인.
  static double maxMergePayoutOf(Chain c, int level) => 3 * valueOf(c, level);

  /// 최고 단계 아이템을 친구에게 선물할 때 코인 (하트 +1 과 함께).
  static double maxGiftCoinsOf(Chain c, int level) => 2 * valueOf(c, level);

  /// 하트가 다 찬 친구에게 선물하면 대신 별.
  static const int maxGiftStars = 30;

  /// 신규 아이템 발견 보너스 코인.
  static double discoveryBonusOf(Chain c, int level) => valueOf(c, level);

  /// 바구니에서 2단계가 나올 확률 (기본). 바구니 품질 강화로 더 오른다.
  static const double luckySpawnChance = 0.08;

  /// 합칠 때 같은 아이템이 든 비눗방울이 생길 확률. 광고를 보면 꺼내서 가질 수 있다.
  /// 비눗방울: 합치기(4단계 이상) 3%, 판에 하나만, 빈칸이 4칸 이상일 때만, 5분에 한 번까지 (진행을 막지 않게).
  static const double bubbleChance = 0.03;
  static const int bubbleMinFree = 4;
  static const Duration bubbleGap = Duration(minutes: 5);
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

  /// 보상형 광고: 코인 주머니 = 20 + 8 × 레벨, 쿨다운.
  /// 코인 주머니: 기본 + 지금 방치 수익 20분치 (수입 인플레이션을 따라간다).
  static double coinBagOf(int playerLevel, double incomePerSec) =>
      20.0 + 8 * playerLevel + incomePerSec * 1200;
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
  static const Duration visitorMinGap = Duration(minutes: 12);
  static const Duration visitorMaxGap = Duration(minutes: 28);
  static const Duration visitorStay = Duration(seconds: 60);

  /// 손님 선물: 기본 + 지금 방치 수익 10분치.
  static double visitorCoinsOf(int playerLevel, double incomePerSec) =>
      10.0 + 3 * playerLevel + incomePerSec * 600; // 그냥 받기
  static const double visitorAdMultiplier = 2; // 광고 보고 받기
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
    AdKind.boost: 6,
    AdKind.coinBag: 5,
    AdKind.refresh: 5,
    AdKind.quota: 6,
    AdKind.gems: 3,
    AdKind.market: 1,
  };

  /// 광고 보고 다이아: 하루 3번 × 3개 (한 달 최대 270 ≈ ₩5,100어치, D-036).
  static const int adGems = 3;

  /// 하루 부탁 단계 보상: 오늘 N번째 부탁을 들어주면 다이아 (하루 최대 10, 한 달 300).
  static const List<int> orderMilestones = [10, 20, 30];
  static const List<int> orderMilestoneGems = [2, 3, 5];

  /// 2회차부터 부탁 별 보너스: 회차당 +5%, 최대 +50%.
  static double roundStarBonus(int round) => min(0.5, 0.05 * (round - 1));

  /// 장식 1개 / 구역 완성 시 정원 매력도 (코인 배율) 증가.
  static const double decorIncomeBonus = 0.02;
  static const double areaIncomeBonus = 0.10;
}

/// 하루 횟수 제한이 있는 보상형 광고 종류 (오프라인 2배·손님·비눗방울은 제한 없음).
enum AdKind { energy, boost, coinBag, refresh, quota, gems, market }

/// 시간제 부스트. coins = 코인 2배 (예전 '부스트'), energy = 바구니 에너지 무료, lucky = 행운 바구니.
enum BoostKind { coins, energy, lucky }

class Boosts {
  /// 광고 1번으로 얻는 시간.
  static const Map<BoostKind, Duration> perAd = {
    BoostKind.coins: Duration(minutes: 15),
    BoostKind.energy: Duration(minutes: 5),
    BoostKind.lucky: Duration(minutes: 5),
  };

  /// 에너지 절약: 바구니 한 번에 에너지가 들지 않을 확률 (예전 '무한 에너지'는 한 판에 1,000번 넘게 무료라 폐지).
  static const double energySaveChance = 0.25;

  /// 다이아로 사는 시간 · 가격.
  static const Map<BoostKind, Duration> perGems = {
    BoostKind.coins: Duration(minutes: 30),
    BoostKind.energy: Duration(minutes: 15),
    BoostKind.lucky: Duration(minutes: 20),
  };
  static const Map<BoostKind, int> gemCost = {
    BoostKind.coins: 20,
    BoostKind.energy: 20,
    BoostKind.lucky: 20,
  };

  /// 쌓을 수 있는 최대 남은 시간.
  static const Duration max = Duration(minutes: 60);

  /// 행운 바구니: 한 단계 높게 나올 확률 추가.
  static const double luckyBonus = 0.20;
}

/// 친구 부탁 하루 한도: 친구마다 하루 [perFriend] 번까지 별을 준다.
/// 한도가 끝나도 부탁은 계속 나오고 코인 · 경험치만 준다. 첫 구역을 끝낼 때까지는 한도 없음.
/// 공유 · 친구 초대 (D-045).
class Invite {
  /// 초대받아 시작한 새 계정의 환영 선물.
  static const int welcomeGems = 50;

  /// 초대한 친구가 조건을 채우면 초대한 사람에게 (최대 [maxRewards]명).
  static const int rewardGems = 100;
  static const int maxRewards = 5;

  /// '일주일쯤 제대로 플레이': 초대 뒤 7일 · 서로 다른 5일 접속 · Lv15.
  static const int needLevel = 15;
  static const int needDays = 5;
  static const Duration wait = Duration(days: 7);

  /// 초대(환영 선물)를 받을 수 있는 새 계정: 이 레벨 이하 · 아직 초대받은 적 없음.
  static const int newPlayerMaxLevel = 10;

  /// 하루 한 번, 자랑하기를 누르면 에너지.
  static const int shareEnergy = 10;

  static const String package = 'io.github.graviton94.mintandfriends';

  /// 스토어 링크 + 설치 추천인 (설치 후 첫 실행 때 이 코드로 친구가 맺어진다).
  static String link(String? code) =>
      'https://play.google.com/store/apps/details?id=$package'
      '${code == null || code.isEmpty ? '' : '&referrer=code%3D$code'}';
}

class OrderQuota {
  static int get perFriend => Tuning.orderQuotaPerFriend; // 원격 조정 가능

  /// 처음 이만큼은 한도 없이 (튜토리얼 · 첫 구역 초반).
  static const int freeOrders = 20;
  static const int perAd = 2;
  static const int pass = 2;

  /// 부탁 바꾸기: 하루 무료 횟수 (그다음은 광고).
  static const int freeRerolls = 3;

  /// 정원 패스: 매일 다이아.
  static const int passDailyGems = 10;

  /// 정원 패스: 에너지 통 +50 (D-080).
  static const int passEnergyCap = 50;
}

/// 정원 패스 가치표 (D-081): 광고 없이 바로 받는 보상을 게임 안 다이아 값으로 바꿔 30일을 더한다.
/// 에너지는 다이아 충전(100개 = Tuning.refillBase), 부스트는 다이아로 사는 코인 2배 값, 다이아 광고는 그대로.
class PassValue {
  static const int days = 30;

  /// 하루 최대 (광고 종류 · 횟수 · 다이아 값).
  static List<(AdKind, int, int)> perDay() {
    final energyAds = GameConfig.adDailyCap[AdKind.energy] ?? 0;
    final boostAds = GameConfig.adDailyCap[AdKind.boost] ?? 0;
    final gemAds = GameConfig.adDailyCap[AdKind.gems] ?? 0;
    final energyGems =
        (energyAds *
                Tuning.energyAdAmount *
                Tuning.refillBase /
                Gems.refillEnergy)
            .round();
    final boostOne =
        Boosts.gemCost[BoostKind.coins]! *
        Boosts.perAd[BoostKind.coins]!.inMinutes /
        Boosts.perGems[BoostKind.coins]!.inMinutes;
    return [
      (AdKind.energy, energyAds, energyGems),
      (AdKind.boost, boostAds, (boostAds * boostOne).round()),
      (AdKind.gems, gemAds, gemAds * GameConfig.adGems),
    ];
  }

  static int get dailyGems => OrderQuota.passDailyGems;
  static int get perDayTotal =>
      perDay().fold<int>(0, (a, e) => a + e.$3) + dailyGems;
  static int get monthTotal => perDayTotal * days;

  /// 같은 값(₩5,900)의 다이아 팩 대비 배율 (내림).
  static int get timesPack {
    final pack = Gems.packs.firstWhere((p) => p.id == 'gems_430');
    return monthTotal ~/ pack.gems;
  }
}

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
  autoSpawn,
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
  /// 초반 가산(D-033, 실기기 로그: 14분에 Lv7 → 너무 빠름): Lv1 +30 → Lv10 +3, 그 뒤 0.
  /// 장기 곡선은 그대로 두고 첫 세션을 Lv5 안팎으로.
  static int xpToNext(int level) =>
      (13 + 6.5 * pow(level - 1, 1.6) + max(0, 30 - 3 * (level - 1))).round();

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
    Feature.autoSpawn: 9,
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
double cellCost(int purchased) =>
    150 * pow(1.3, purchased).toDouble() * Tuning.coinScale;

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
    Chain.tea: [],
    Chain.stardust: [],
  };

  /// 늦게 열리는 체인은 1단계부터 시작한다 (증분 성장, D-053): 바구니 등급에서 이만큼 뺀 단계가 나오고,
  /// 가치는 이만큼 올린 단계로 센다 (예전 찻잎 4단계 = 지금 찻잎 1단계, 경제는 그대로).
  /// 값 = 그 체인이 열리는 구역에 닿을 때 보통의 바구니 등급 (시뮬: 온실 ≈ 등급 3, 별빛 언덕 ≈ 등급 5).
  static int levelOffset(Chain c) => switch (c) {
    Chain.tea => 3,
    Chain.stardust => 5,
    _ => 0,
  };

  /// 체인별 최고 단계: 모두 30 (D-029, 방치 머지의 수입 인플레이션 · 바구니 등급으로 올라간다).
  static int maxLevel(Chain c) => GameConfig.maxLevel;

  /// 처음부터 그림이 있던 단계 수 (이 단계까지 그림이 있으면 체인이 열린다).
  static int baseArtLevels(Chain c) =>
      c == Chain.tea || c == Chain.stardust ? 10 : 15;

  static ItemDef item(Chain c, int level) {
    final l = level.clamp(1, maxLevel(c));
    final e = _emoji[c]!;
    return ItemDef(c, l, e.isEmpty ? '' : e[min(l, e.length) - 1]);
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

  /// 구역 바구니(찻잎 · 별가루)는 충전식: 최대 횟수 · 1회 충전 초 (0 = 에너지만).
  /// 짧은 체인(Lv10 = 1단계 512개)이 하루 만에 끝나지 않게 (밸런스 시뮬레이션: 최고 단계 2~3주).
  /// D-031: 체인이 30단계가 되고 부탁이 바구니 등급을 따라가면서 충전식은 고단계 부탁을 막아 없앴다 (0 = 에너지만).
  static const List<int> basketCharges = [0, 0, 0];
  static const List<int> basketRechargeSec = [0, 360, 450];
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
  basketTier,
  teaPower,
  stardustPower,
  autoSpawn,
}

class UpgradeDef {
  final UpgradeType type;
  final String icon;
  final int maxLevel;
  final double baseCost;
  final double costGrowth;
  final Feature? feature; // 이 기능이 해금돼야 살 수 있음

  /// 처음 여는 비용 (0 = 없음). 새 강화 줄은 비싸게 열고, 그 뒤 단계는 작게 · 지수로 오른다.
  final double unlockCost;

  /// 단계마다 필요한 플레이어 레벨: 다음 단계 L(0부터) = gateStart + gateStep × L.
  final int gateStart;
  final double gateStep;

  /// 높은 단계에서 더 가파르게 (애드캡처럼 비싼 줄일수록 성장률이 다르다): [lateFrom] 단계부터 단계마다 ×[lateGrowth].
  final int lateFrom;
  final double lateGrowth;
  const UpgradeDef(
    this.type,
    this.icon,
    this.maxLevel,
    this.baseCost,
    this.costGrowth, {
    this.feature,
    this.unlockCost = 0,
    this.gateStart = 2,
    this.gateStep = 0,
    this.lateFrom = 1 << 30,
    this.lateGrowth = 1,
  });

  double costAt(int level) =>
      (level == 0 && unlockCost > 0
          ? unlockCost
          : baseCost *
                pow(costGrowth, level) *
                pow(lateGrowth / costGrowth, max(0, level - lateFrom))) *
      Tuning.coinScale;
  int levelFor(int nextLevel) => gateStart + (gateStep * nextLevel).floor();
  String get key => 'upgrade.${type.name}';
}

/// 강화 (D-029, 방치 머지 구조): 단계를 많이 · 단계당 성장은 조금 · 가격은 지수로.
/// 뒤 단계일수록 가성비가 나빠지고(코인 소모처), 새 강화 줄은 비싸게 연다.
/// 수입은 아이템 가치(단계마다 ×2.2)로 불어나고, 가격도 지수로 따라 오른다 (총수입 ↔ 총지출).
class Upgrades {
  static const List<UpgradeDef> all = [
    // 바구니 등급: 바구니에서 나오는 기본 단계 +1 (부탁 · 수입이 한 단계씩 올라간다). 단계마다 가격 ×2.75
    // (수입은 단계당 ×2.2 → 갈수록 오래 모아야 한다). Lv 3 · 6 · 9 … (최고 단계 도달 약 6~9개월, 1년 시뮬)
    UpgradeDef(
      UpgradeType.basketTier,
      'basket',
      24,
      400,
      4.0,
      gateStart: 3,
      gateStep: 2,
      lateFrom: 12,
      lateGrowth: 6.0,
    ),
    // 체인별 생산력: 끝없음, 단계당 +5% · 25단계마다 ×2, 가격 ×1.28
    UpgradeDef(
      UpgradeType.flowerPower,
      'item:flower:6',
      Upgrades.endless,
      150,
      1.28,
    ),
    UpgradeDef(
      UpgradeType.snackPower,
      'item:snack:6',
      Upgrades.endless,
      200,
      1.28,
      feature: Feature.snack,
      gateStart: 3,
    ),
    UpgradeDef(
      UpgradeType.teaPower,
      'item:tea:6',
      Upgrades.endless,
      2000,
      1.28,
      unlockCost: 20000,
      gateStart: 10,
    ),
    UpgradeDef(
      UpgradeType.stardustPower,
      'item:stardust:6',
      Upgrades.endless,
      8000,
      1.28,
      unlockCost: 150000,
      gateStart: 15,
    ),
    // 전체 수익: 끝없음, 단계당 +3%, 가격 ×1.32
    UpgradeDef(
      UpgradeType.income,
      'coinbag',
      Upgrades.endless,
      500,
      1.32,
      gateStart: 3,
    ),
    // 에너지 회복 (자동 줄, D-059): 150초 → 20단계 100초(단계당 −2.5초) → 60단계 70초(단계당 −0.75초)
    UpgradeDef(
      UpgradeType.energyRegen,
      'timer',
      Upgrades.autoMax,
      1500,
      1.3,
      unlockCost: 4000,
      gateStart: 6,
      gateStep: 0.75,
      lateFrom: 20,
      lateGrowth: 1.75,
    ),
    // 바구니 품질: 한 단계 높게 나올 확률 +0.5%p × 20
    UpgradeDef(
      UpgradeType.spawnLevel,
      'quality',
      20,
      1500,
      1.3,
      feature: Feature.spawnLevel,
      unlockCost: 8000,
      gateStart: 10,
      gateStep: 2,
    ),
    // 오프라인 한도: 2시간 → 12시간 (10단계)
    UpgradeDef(
      UpgradeType.offlineCap,
      'moon',
      10,
      1500,
      1.45,
      feature: Feature.offlineCap,
      unlockCost: 4000,
      gateStart: 8,
      gateStep: 3,
    ),
    // 자동 합치기 (자동 줄, D-059): 30초 → 60단계 약 6초, 합치는 상한 = 바구니 단계 + 2 + 단계/10
    UpgradeDef(
      UpgradeType.autoMerge,
      'auto',
      Upgrades.autoMax,
      5000,
      1.7,
      feature: Feature.autoMerge,
      unlockCost: 20000,
      gateStart: 6,
      gateStep: 0.75,
    ),
    // 자동 놓기 (자동 줄, D-059): 에너지로 바구니를 대신 누른다. 36초 → 60단계 약 7초
    UpgradeDef(
      UpgradeType.autoSpawn,
      'basket',
      Upgrades.autoMax,
      8000,
      1.7,
      feature: Feature.autoSpawn,
      unlockCost: 40000,
      gateStart: 9,
      gateStep: 0.75,
    ),
  ];

  static const int endless = 9999;

  /// 자동 줄 (에너지 충전 · 자동 놓기 · 자동 합치기, D-059): 재단장해도 남고,
  /// 한 판에 올릴 수 있는 단계는 [autoCap] 까지 (재단장할수록 열린다).
  static const int autoMax = 60;
  static const List<UpgradeType> autoLines = [
    UpgradeType.energyRegen,
    UpgradeType.autoSpawn,
    UpgradeType.autoMerge,
  ];

  /// 자동 정원 보너스 (D-059): 화면을 켜 두고 [idleAfter] 동안 손대지 않으면, 자동 줄 단계 합(최대 180)에 따라
  /// 정원 수입 +0% → 최대 +180%. 처음엔 조금, 중반부터 확실히 (제곱근 1.5 곡선).
  static const Duration idleAfter = Duration(seconds: 60);
  static double autoIdleBonus(int levelSum) =>
      1.8 * pow(min(levelSum, 3 * autoMax) / (3 * autoMax), 1.5).toDouble();

  static int autoCap(int renews, int memoryPerk) =>
      min(autoMax, 15 + 7 * renews + 7 * memoryPerk);

  static UpgradeDef of(UpgradeType t) => all.firstWhere((u) => u.type == t);

  /// 25단계마다 ×2 가 붙는 강화면 그 간격 (생산력 4종).
  static int? milestoneEvery(UpgradeType t) => switch (t) {
    UpgradeType.flowerPower ||
    UpgradeType.snackPower ||
    UpgradeType.teaPower ||
    UpgradeType.stardustPower => 25,
    _ => null,
  };

  /// 체인별 생산력: 단계당 +5%, 25단계마다 ×2.
  static double chainPower(int lv) =>
      (1 + 0.05 * lv) * pow(2, lv ~/ 25).toDouble();

  static UpgradeType powerOf(Chain c) => switch (c) {
    Chain.flower => UpgradeType.flowerPower,
    Chain.snack => UpgradeType.snackPower,
    Chain.tea => UpgradeType.teaPower,
    Chain.stardust => UpgradeType.stardustPower,
  };

  static double energyRegenSeconds(int lv) {
    final early = max(
      min(100.0, Tuning.energyRegenSeconds),
      Tuning.energyRegenSeconds - 2.5 * min(lv, 20),
    );
    return lv <= 20 ? early : max(70.0, early - 0.75 * (lv - 20));
  }

  /// 전체 수익 배율: 단계당 +3%.
  static double incomeMultiplier(int lv) => 1 + 0.03 * lv;

  /// 자동 합치기 간격: 30초에서 단계마다 조금씩 (60단계 약 6초).
  static double? autoMergeInterval(int lv) =>
      lv <= 0 ? null : 4 + 26 * pow(0.955, min(lv, autoMax) - 1).toDouble();

  /// 자동 놓기 간격: 합치기보다 조금 느리고 비율이 딱 떨어지지 않아 둘이 계속 엇갈린다 (36초 → 약 7초).
  static double? autoSpawnInterval(int lv) =>
      lv <= 0 ? null : 5 + 31 * pow(0.955, min(lv, autoMax) - 1).toDouble();

  /// 예전 자동 합치기 단계(10단계, 30 → 8초)를 같은 간격 이하가 되는 새 단계로 (1.0.11).
  static int migrateAutoMerge(int oldLv) {
    if (oldLv <= 0) return 0;
    const old = [30.0, 27, 24, 21, 18, 16, 14, 12, 10, 8];
    final want = old[min(oldLv, 10) - 1];
    for (var n = 1; n <= autoMax; n++) {
      if (autoMergeInterval(n)! <= want) return n;
    }
    return autoMax;
  }

  /// 바구니 품질: 한 단계 높게 나올 확률 추가 (+0.5% / 단계).
  static double qualityChance(int lv) => 0.005 * lv;

  /// 오프라인 수익 최대 시간: 2시간 + 1시간씩 (10단계 = 12시간).
  static Duration offlineCap(int lv) => Duration(hours: 2 + min(lv, 10));
}

// ------------------------------------------------------------------ 정원 재단장 (환생, D-031)

enum SeedPerk {
  startBasket,
  startCoins,
  energyJar,
  autoMemory,
  moonRest,
  starWish,
}

class SeedPerkDef {
  final SeedPerk perk;
  final String icon;
  final int maxLevel;
  final int baseCost; // 다음 단계 비용 = baseCost × (단계 + 1)
  const SeedPerkDef(this.perk, this.icon, this.maxLevel, this.baseCost);
  int costAt(int lv) => baseCost * (lv + 1);
}

/// 정원 재단장: 바구니 등급 Lv.10 이상이면 판 · 코인 · 바구니 등급 · 생산력/수익 강화를 처음부터 다시 하고
/// 황금 씨앗을 받는다. 씨앗은 모은 만큼 영구 수입 +10%, 쓰면 영구 강화(씨앗을 써도 수입 배율은 그대로).
class Renewal {
  static const int needBasketTier = 10;
  static double get seedIncome => Tuning.seedIncome;
  static double get coinsPerSeedBase => Tuning.seedCoinBase;
  static const double adBonus = 1.5;

  /// 지금까지 번 모든 코인으로 정해지는 씨앗 몫: ⌊(누적 코인 ÷ 기준)^(1/3)⌋ (D-038).
  /// 재단장 때는 이 몫에서 이미 받은 만큼을 뺀 것만 받는다 → 씨앗이 씨앗을 부르는 눈덩이가 없다.
  static int seedsFor(double coins) =>
      coins <= 0 ? 0 : (pow(coins / coinsPerSeedBase, 1 / 3) + 1e-9).floor();

  /// 씨앗 몫이 n 이 되는 누적 코인.
  static double coinsForSeeds(int n) => coinsPerSeedBase * pow(n, 3);

  static const List<SeedPerkDef> perks = [
    SeedPerkDef(SeedPerk.startBasket, 'seed_basket', 5, 5),
    SeedPerkDef(SeedPerk.startCoins, 'seed_coin', 5, 3),
    SeedPerkDef(SeedPerk.energyJar, 'energy_jar', 10, 4),
    SeedPerkDef(SeedPerk.autoMemory, 'seed_memory', 1, 8),
    SeedPerkDef(SeedPerk.moonRest, 'moon', 5, 2),
    SeedPerkDef(SeedPerk.starWish, 'star', 10, 6),
  ];
  static SeedPerkDef of(SeedPerk p) => perks.firstWhere((d) => d.perk == p);
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
  /// 친구 레벨 (D-029): 최대 30, 단계당 효과는 작게, 가격은 지수(600 × 1.3^L).
  /// 하트(호감도)가 그 레벨 이상이어야 한다. 레벨 10: 그 친구 별 부탁 하루 +1, 20: 효과 ×1.25, 30: ×1.5.
  static const int starMilestone = 10;
  static const int boostMilestone = 20;
  static const int maxMilestone = 30;
  static double effectiveLevel(int lv) => lv >= maxMilestone
      ? lv * 1.5
      : lv >= boostMilestone
      ? lv * 1.25
      : lv.toDouble();

  static double levelCost(int current) =>
      600 * pow(1.3, current).toDouble() * Tuning.coinScale;

  static const List<FriendDef> all = [
    // 친구 레벨 1당 효과 (D-029: 최대 30 · 하트만큼, 단계당 작게)
    FriendDef('bori', '🐰', FriendBuff.energyRegen, 0.004),
    FriendDef('dubu', '🐻', FriendBuff.income, 0.01),
    FriendDef('kwak', '🦆', FriendBuff.orderCoins, 0.01),
    FriendDef('nabi', '🐱', FriendBuff.lucky, 0.002),
    FriendDef('dotori', '🐿️', FriendBuff.offline, 0.01),
    FriendDef('mochi', '🐼', FriendBuff.income, 0.01),
    FriendDef('danpung', '🦊', FriendBuff.starBonus, 0.007),
    FriendDef('kongtteok', '🐹', FriendBuff.autoMerge, 0.01),
    // 5 · 6구역 친구 (그림이 들어오면 그 구역과 함께 열린다)
    FriendDef('bogeul', '🦦', FriendBuff.orderCoins, 0.01),
    FriendDef('pposong', '🐧', FriendBuff.energyRegen, 0.004),
  ];

  /// 처음부터 있던 친구 (그림 걱정 없이 도감에 보인다).
  static const int coreCount = 8;

  static FriendDef byId(String id) => all.firstWhere((f) => f.id == id);

  static const String starter = 'bori';
  static const int maxAffection = 30;

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

  /// 랜드마크(D-048)가 서는 자리: 가운데 x · 바닥 y (씬 대비 0~1). 구역마다 조금씩 다르게.
  final double landmarkX, landmarkY;
  const AreaDef(
    this.id,
    this.emoji,
    this.sky,
    this.ground,
    this.decor, {
    this.round = 1,
    this.walk = const [WalkZone(0.08, 0.42, 0.92, 0.92)],
    this.water = const [],
    this.landmarkX = 0.5,
    this.landmarkY = 0.62,
  });

  String get key => 'area.$id';
}

class Garden {
  static const int slotsPerArea = 8;

  static const List<AreaDef> areas = [
    AreaDef(
      'yard',
      '🏡',
      0xFFBFE6F7,
      0xFFA8D88E,
      [
        DecorDef('big_tree', '🌳', 0.10, 0.38),
        DecorDef('bench', '🪑', 0.23, 0.36),
        DecorDef('mailbox', '📮', 0.80, 0.38),
        DecorDef('veggie_patch', '🥕', 0.18, 0.62, bringsFriend: 'dubu'),
        DecorDef('lantern', '🏮', 0.63, 0.70),
        DecorDef('bird_feeder', '🐦', 0.32, 0.80),
        DecorDef('hut', '🛖', 0.69, 0.32),
        DecorDef('fountain', '⛲', 0.86, 0.58),
      ],
      landmarkX: 0.42,
      landmarkY: 0.66,
    ),
    AreaDef(
      'pond',
      '🦆',
      0xFFC6E2FA,
      0xFF9CD3B0,
      [
        DecorDef('stepping_stones', '🪨', 0.70, 0.48),
        DecorDef('water_lily', '🪷', 0.52, 0.52, bringsFriend: 'kwak'),
        DecorDef('fishing_spot', '🎣', 0.85, 0.36),
        DecorDef('rowboat', '🛶', 0.62, 0.68),
        DecorDef('reeds', '🌾', 0.09, 0.80),
        DecorDef('log_chair', '🪵', 0.54, 0.90, bringsFriend: 'nabi'),
        DecorDef('tent', '🏕️', 0.88, 0.80),
        DecorDef('wooden_bridge', '🌉', 0.30, 0.74),
      ],
      walk: [WalkZone(0.06, 0.44, 0.94, 0.94)],
      water: [WaterZone(0.52, 0.58, 0.46, 0.21)],
      landmarkX: 0.20,
      landmarkY: 0.47,
    ),
    AreaDef(
      'greenhouse',
      '🪴',
      0xFFF6E3F0,
      0xFFB9DFA0,
      [
        DecorDef('glasshouse', '🪟', 0.10, 0.32),
        DecorDef('cactus', '🌵', 0.27, 0.38),
        DecorDef('mushroom_bed', '🍄', 0.80, 0.58, bringsFriend: 'dotori'),
        DecorDef('watering_can', '🚿', 0.73, 0.38),
        DecorDef('sunflower_field', '🌻', 0.19, 0.58),
        DecorDef('tea_table', '🫖', 0.36, 0.84),
        DecorDef('bamboo', '🎋', 0.92, 0.40, bringsFriend: 'mochi'),
        DecorDef('wind_chime', '🎐', 0.66, 0.84),
      ],
      landmarkX: 0.5,
      landmarkY: 0.62,
    ),
    AreaDef(
      'starry_hill',
      '🌙',
      0xFF2E3A6B,
      0xFF6F9A6A,
      [
        DecorDef('telescope', '🔭', 0.13, 0.30),
        DecorDef('camp_tent', '⛺', 0.29, 0.40),
        DecorDef('campfire', '🔥', 0.38, 0.55, bringsFriend: 'danpung'),
        DecorDef('ferris_wheel', '🎡', 0.88, 0.33),
        DecorDef('carousel', '🎠', 0.82, 0.58),
        DecorDef('moon_statue', '🌙', 0.15, 0.64),
        DecorDef('little_castle', '🏰', 0.36, 0.82, bringsFriend: 'kongtteok'),
        DecorDef('fireworks', '🎆', 0.80, 0.82),
      ],
      landmarkX: 0.58,
      landmarkY: 0.55,
    ),
    // 5 · 6구역: 배경 · 장식 · 친구 그림이 모두 들어와야 열린다 (그 전에는 1~4구역 순환)
    AreaDef(
      'seaside',
      '🏖️',
      0xFFBDE8F5,
      0xFFF3E3B8,
      [
        DecorDef('beach_hut', '🛖', 0.10, 0.38),
        DecorDef('parasol', '⛱️', 0.29, 0.42),
        DecorDef('lighthouse', '🗼', 0.90, 0.28),
        DecorDef('sandcastle', '🏰', 0.36, 0.72, bringsFriend: 'bogeul'),
        DecorDef('deck_chair', '🪑', 0.18, 0.60),
        DecorDef('shell_fountain', '🐚', 0.14, 0.82),
        DecorDef('surf_rack', '🏄', 0.72, 0.40),
        DecorDef('seagull_post', '🪵', 0.62, 0.76),
      ],
      landmarkX: 0.52,
      landmarkY: 0.31,
    ),
    AreaDef(
      'snow_village',
      '❄️',
      0xFFDDE9F5,
      0xFFF4F7FA,
      [
        DecorDef('chimney_cottage', '🏠', 0.12, 0.36),
        DecorDef('winter_tree', '🎄', 0.29, 0.36),
        DecorDef('snowman', '⛄', 0.20, 0.62),
        DecorDef('igloo', '🛖', 0.89, 0.44),
        DecorDef('sled', '🛷', 0.58, 0.84),
        DecorDef('cocoa_stand', '☕', 0.36, 0.72),
        DecorDef('ice_rink', '⛸️', 0.73, 0.62, bringsFriend: 'pposong'),
        DecorDef('snow_lantern', '🏮', 0.88, 0.80),
      ],
      landmarkX: 0.5,
      landmarkY: 0.58,
    ),
  ];

  static const int coreAreas = 4;

  /// 구역 그림이 준비됐는지 (Art.init 이 바꿔 낀다). 기본: 1~4구역만.
  static bool Function(AreaDef a) ready = (a) => areas.indexOf(a) < coreAreas;

  /// 이 장식의 이 디자인 그림이 있는지 (Art.init 이 바꿔 낀다).
  static bool Function(DecorDef d, int style) styleReady = (_, _) => true;

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
      landmarkX: base.landmarkX,
      landmarkY: base.landmarkY,
    );
  }

  /// 장식 별 비용: 구역 안에서 2 → 5, 구역마다 (1 + 구역) 배. 앞마당 28, 연못 56, 온실 84 …
  static int decorCost(int area, int slot) =>
      max(1, (areaStars(area) * (2 + slot ~/ 2) / 28).round());

  /// 구역 하나를 다 꾸미는 데 드는 별 (하루 에너지 약 480 → 별 약 120 기준).
  /// 1구역 첫 15~20분, 2구역 1~2일차, 3구역 4~5일차, 4구역 11일차, 5구역 한 달, 6구역 완성 두 달 (D-047:
  /// 새 그림 구역 6개를 6주 만에 다 쓰던 것을 늦춤. 나머지는 테스트 지표 · 원격 area_star_scale 로).
  static const List<int> _areaStars = [24, 160, 480, 1600, 3900, 8000];
  static int areaStars(int area) =>
      ((area < _areaStars.length
                  ? _areaStars[area]
                  : _areaStars.last * pow(1.6, area - _areaStars.length + 1)) *
              Tuning.areaStarScale)
          .round();

  /// 장식 디자인 (바이블 D-005): 0 기본(별) · 1 고급(코인, 별값 × 120 ≈ 하루 수입 0.5~1일치) · 2 특별(다이아).
  /// 디자인: 0 기본 · 1 고급(코인) · 2 특별(다이아) · 3~6 시즌(겨울 · 봄 · 여름 · 가을, 다이아).
  static const int styles = 7;
  static const Map<int, String> seasonStyles = {
    3: 'winter',
    4: 'spring',
    5: 'summer',
    6: 'autumn',
  };
  static bool isSeasonStyle(int s) => seasonStyles.containsKey(s);

  /// 화면에 보이는 계절 순서: 봄 · 여름 · 가을 · 겨울.
  static const List<int> seasonOrder = [4, 5, 6, 3];

  /// 시즌 디자인 → 계절 번호 (0 봄 · 1 여름 · 2 가을 · 3 겨울).
  static int seasonIndexOf(int style) => switch (style) {
    4 => 0,
    5 => 1,
    6 => 2,
    _ => 3,
  };

  /// 계절 세트(한 구역 8종) 완성마다 정원 매력 보너스 (D-046: 고과금 쏠림을 줄여 +5% → +2%).
  static const double seasonSetBonus = 0.02;

  /// 부분 효과 (D-063): 시즌 장식 하나마다 +0.1%, 8종을 다 모으면 나머지 +1.2% (합 +2%, 예전과 같음).
  static const double seasonPieceBonus = 0.001;
  static double get seasonCompleteBonus =>
      seasonSetBonus - 8 * seasonPieceBonus;

  /// 지금 달의 시즌 디자인 (그 시즌에만 살 수 있고, 산 것은 계속 쓴다).
  static int seasonStyleFor(int month) => switch (month) {
    12 || 1 || 2 => 3,
    3 || 4 || 5 => 4,
    6 || 7 || 8 => 5,
    _ => 6,
  };

  /// 시즌 장식: 한 개 · 구역 8종 세트 (할인).
  static const int seasonGems = 40;
  static const int seasonSetGems = 250;
  static int styleCoins(int area, int slot) =>
      (decorCost(area, slot) * 120 * Tuning.coinScale).round();

  /// 특별 디자인 한 자리 (D-046): 80 + 40 × 구역 (앞마당 80 ~ 눈꽃 마을 280, 6구역 전부 8,640).
  static int styleGems(int area) => 80 + 40 * min(area, DecorSets.areas - 1);

  /// 부탁 1건의 별 보상: 에너지 10 이하(≤4단계) 1, 30 이하(5단계) 2, 그 이상 3.
  static int orderStars(int level) => level <= 3
      ? 1
      : (pow(2, level - 1) / 4 * (1 + 0.05 * (level - 3))).round();
}

// ------------------------------------------------------------------ 정원 랜드마크 (D-048)

/// 구역마다 가운데 큰 조형물. 구역을 다 꾸미면 세울 수 있고, 코인으로 끝없이(최대 [maxLevel]) 키운다.
/// 가격은 고정이 아니라 '지금 시간당 수입 × 시간' (언제 사도 같은 노력). 재단장해도 남는다.
class Landmarks {
  /// 구역 순서대로 (그림: `assets/art/landmarks/<id>_<단계>.webp`).
  static const List<String> ids = [
    'windmill',
    'waterwheel',
    'flowerclock',
    'observatory',
    'sailship',
    'icepalace',
  ];
  static const int maxLevel = 50;

  /// 그림 단계가 바뀌는 레벨 (1단계 · 2 · 3 · 4).
  static const List<int> stageAt = [1, 10, 20, 30];
  static int stageOf(int lv) {
    var st = 1;
    for (var i = 0; i < stageAt.length; i++) {
      if (lv >= stageAt[i]) st = i + 1;
    }
    return st;
  }

  /// lv → lv+1 가격 = 지금 시간당 수입(플레이 중 실제로 버는 속도) × 이 시간:
  /// Lv1 15분 · Lv20 약 3시간 · Lv40 약 1.4일 · Lv49 약 3.7일 (최대는 오래 걸리게, 1년 시뮬로 맞춤).
  static double hoursAt(int lv) => 0.12 * pow(1.115, lv).toDouble();

  /// 정원 매력 (수입 배율에 더함): 레벨당 +0.4%, 10레벨마다 +3% 더 → Lv50 하나 +35%.
  static double charm(int lv) => 0.004 * lv + 0.03 * (lv ~/ 10);

  /// 세운 랜드마크 높이 (장식 크기 대비).
  static const double scale = 2.0;
}

// ------------------------------------------------------------------ 꾸밈 점수 · 세트 효과 (D-046)

/// 구역 세트 효과의 종류 (구역 순서대로).
enum SetEffect {
  energyCap,
  energyRegen,
  orderStars,
  offline,
  lucky,
  visitorCoins,
}

/// 꾸밈 효과: 무과금(고급 · 코인)으로 완성하면 과금(특별 · 다이아) 완성의 40%.
class DecorSets {
  /// 세트 · 점수를 세는 구역 수 (6구역. 그 뒤 순환 구역은 세지 않는다: 끝없이 쌓이지 않게).
  static const int areas = 6;

  /// 꾸밈 점수: 특별 디자인 1점 · 고급 0.4점, 1점마다 영구 수입 +0.25%.
  static const double specialPoint = 1.0;
  static const double premiumPoint = 0.4;
  static const double incomePerPoint = 0.0025;

  /// 고급 세트 효과 = 특별 세트의 이 비율.
  static const double premiumRatio = 0.4;

  /// 부분 효과 (D-063): 효과의 절반은 장식 하나하나에 나눠 붙고(특별 1/16 · 고급 0.4/16),
  /// 나머지 절반은 8자리를 다 모았을 때 세트 보너스로 켜진다. 다 모으면 예전과 같은 값.
  static const double pieceShare = 0.5;
  static double piece(SetEffect e, {bool special = true}) =>
      full[e]! * pieceShare / 8 * (special ? 1 : premiumRatio);
  static double setPart(SetEffect e, {bool special = true}) =>
      full[e]! * (1 - pieceShare) * (special ? 1 : premiumRatio);

  /// 구역 i 의 특별 세트 효과 (고급은 [premiumRatio] 배). 단위: 에너지 통 +칸 · 비율 · 분 · 확률.
  static const List<SetEffect> effects = [
    SetEffect.energyCap,
    SetEffect.energyRegen,
    SetEffect.orderStars,
    SetEffect.offline,
    SetEffect.lucky,
    SetEffect.visitorCoins,
  ];
  static const Map<SetEffect, double> full = {
    SetEffect.energyCap: 5,
    SetEffect.energyRegen: 0.05,
    SetEffect.orderStars: 0.05,
    SetEffect.offline: 60,
    SetEffect.lucky: 0.02,
    SetEffect.visitorCoins: 0.10,
  };
}

// ------------------------------------------------------------------ 다이아 (하드 통화)

/// 다이아 팩 (Play 인앱 상품, 소모형). 가격은 스토어 값이 우선, krw 는 스토어 연결 전 표시용.
class GemPack {
  final String id;
  final int gems;
  final int krw;
  const GemPack(this.id, this.gems, this.krw);

  /// 가장 작은 팩(100개 / ₩1,900) 대비 가치 배율 · 보너스 %.
  double get valueX => gems / (krw * 100 / 1900);
  int get bonusPct => (valueX * 100 - 100).round();
}

/// 바이블 §6: 무료 다이아는 하루 평균 5~10개, 에너지 100 = 다이아 40 (Travel Town 기준).
class Gems {
  static const List<GemPack> packs = [
    // 캐주얼 장르는 고가 팩을 거의 사지 않으므로, 위 단계로 갈수록 파격적으로 싸게 (가치 1 → 1.4 → 2 → 3 → 3.4배)
    GemPack('gems_100', 100, 1900),
    GemPack('gems_430', 430, 5900),
    GemPack('gems_900', 900, 9900),
    GemPack('gems_2000', 2000, 19000),
    GemPack('gems_6000', 6000, 38000),
    GemPack('gems_14000', 14000, 79000),
  ];

  static GemPack? pack(String id) => packs.where((p) => p.id == id).firstOrNull;

  /// 레벨업마다 무료 다이아.
  static const int levelUp = 3;

  /// 첫 결제 다이아 배수: 다이아 팩 전체에서 한 번만 (Play 상품 · 가격은 그대로, 게임 안에서 더 준다).
  static const int firstBuyMultiplier = 2;

  /// 에너지 충전: 하루 안에 다시 살수록 비싸진다 (60 → 90 → 120 → 최대 150).
  static const int refillEnergy = 100;
  static int refillCost(int boughtToday) => min(
    Tuning.refillMax,
    Tuning.refillBase + Tuning.refillStep * boughtToday,
  );

  /// 코인 꾸러미 (다이아): 지금 시간당 수입의 1 · 3 · 8시간치, 최소값은 물가(바구니 등급)를 따른다.
  /// 머지 장르 관례대로 가성비는 일부러 애매하게 — 초반에 막혔을 때 넘기기용.
  static const List<(int gems, double hours, double floor)> coinPacks = [
    (20, 1, 800),
    (50, 3, 2500),
    (120, 8, 7000),
  ];

  /// 계절 정원 효과 따로 사기.
  static const int effectGems = 450;

  /// 깜짝 상자: 지금 판 · 보관함의 최고 단계보다 1~2단계 낮은 아이템 하나 (최소 바구니 +1).
  /// 값은 그 아이템을 바구니로 만드는 에너지(2^(단계-바구니)) × [surpriseGemPerEnergy],
  /// 에너지 100 충전(0.6개/에너지)보다 살짝 비싸게 — 시간을 사는 값.
  static const double surpriseGemPerEnergy = 0.7;
  static const int surpriseMinGems = 10;
  static const int surpriseMaxGems = 600;

  /// 추천 아이템은 바구니보다 최대 이만큼 높게 (재단장 직후 보관 칸의 높은 아이템 때문에 값만 상한에 걸린 지름길이 되지 않게).
  static const int featuredMaxAbove = 8;

  /// 오늘의 시장: 다이아 칸 가격 · 단계(바구니 +4), 광고 칸 단계(바구니 +3).
  static const int marketGemPrice = 12;
  static const int marketGemLevelUp = 4;
  static const int marketAdLevelUp = 3;

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
  static int price(Chain c, int itemLevel, int playerLevel) =>
      (GameConfig.valueOf(c, itemLevel) *
              (Tuning.marketPriceBase + 2 * playerLevel) /
              4)
          .round();
}

// ------------------------------------------------------------------ 친구 의상 (외형 전용, 바이블 D-008)

class OutfitDef {
  final String id;

  /// 다이아 가격. 음수 = 판매하지 않는 한정 의상 (패키지로만).
  final int gems;

  /// 파는 달 (계절 의상은 그 계절 3개월만, null = 늘). 산 옷은 계절이 지나도 입는다.
  final List<int>? months;
  const OutfitDef(this.id, this.gems, {this.months});
  String get key => 'outfit.$id';
  bool get limited => gems < 0;
  bool onSaleIn(int month) => months == null || months!.contains(month);
}

class Outfits {
  /// 그림이 들어온 의상만 옷장에 보인다 (Art.outfitsFor).
  static const List<OutfitDef> all = [
    OutfitDef('picnic', 120, months: [3, 4, 5]), // 봄
    OutfitDef('summer', 120, months: [6, 7, 8]),
    OutfitDef('autumn', 120, months: [9, 10, 11]),
    OutfitDef('winter', 120, months: [12, 1, 2]),
    OutfitDef('starlight', -1),
  ];
  static OutfitDef? byId(String id) => all.where((o) => o.id == id).firstOrNull;
}

// ------------------------------------------------------------------ 새싹 정원 패키지 (첫 결제, D-019)

/// ₩2,900 계정당 1회. 체감 가치 ₩20,000 이상: 패스 30일 · 다이아 100 · 에너지 100 · 부스트 묶음 ·
/// 한정 정원 효과(계절마다 꽃잎 · 반딧불 · 낙엽 · 눈) · 민트 한정 의상(별빛 요정).
class Starter {
  static const String productId = 'starter_2900';
  static const int krw = 2900;
  static const int gems = 100;
  static const int energy = 100;
  static const Duration pass = Duration(days: 7);

  /// 부스트 묶음 (보관 후 30분씩 꺼내 쓴다): 에너지 절약 2시간 · 행운 2시간 · 코인 꾸러미 3시간.
  static const Map<BoostKind, Duration> boosts = {
    BoostKind.energy: Duration(minutes: 120),
    BoostKind.lucky: Duration(minutes: 120),
    BoostKind.coins: Duration(minutes: 180),
  };

  /// 보관 부스트 한 번에 꺼내 쓰는 시간.
  static const Duration boostUse = Duration(minutes: 30);
  static const String effect = 'seasons';
  static const String outfitFriend = 'bori';
  static const String outfit = 'starlight';

  /// 처음 보여 준 뒤 7일 동안만 판다 (타이머가 끝나면 상점에서도 사라진다).
  static const Duration offerWindow = Duration(days: 7);
  static const int worthKrw = 20000;
}

import 'dart:math';

/// 밸런스와 콘텐츠 상수. 숫자 튜닝은 대부분 이 파일에서 한다.
/// 이모지는 아트가 들어오기 전까지 쓰는 임시 그림이다.
class GameConfig {
  static const int cols = 6;
  static const int rows = 5;
  static const int cellCount = cols * rows;

  static const int maxLevel = 15;

  /// 아이템 1개의 초당 코인 생산량.
  static double incomeOf(int level) => pow(2.2, level - 1).toDouble();

  /// 최고 레벨 두 개를 합치면 사라지면서 지급되는 코인 (해당 아이템 N초분).
  static const double maxMergePayoutSeconds = 1800;

  /// 신규 아이템 발견 보너스 (해당 레벨 아이템 N초분).
  static const double discoveryBonusSeconds = 120;

  /// 행운 스폰 확률 (스폰 레벨 +1).
  static const double luckySpawnChance = 0.06;

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

enum Chain { flower, snack }

class ItemDef {
  final String name;
  final String emoji;
  const ItemDef(this.name, this.emoji);
}

class Chains {
  static const Map<Chain, List<ItemDef>> items = {
    Chain.flower: [
      ItemDef('씨앗', '🌰'),
      ItemDef('새싹', '🌱'),
      ItemDef('클로버', '☘️'),
      ItemDef('어린 잎', '🌿'),
      ItemDef('화분', '🪴'),
      ItemDef('데이지', '🌼'),
      ItemDef('튤립', '🌷'),
      ItemDef('벚꽃', '🌸'),
      ItemDef('장미', '🌹'),
      ItemDef('히비스커스', '🌺'),
      ItemDef('해바라기', '🌻'),
      ItemDef('연꽃', '🪷'),
      ItemDef('꽃다발', '💐'),
      ItemDef('무지개꽃', '🌈'),
      ItemDef('황금 꽃', '🏵️'),
    ],
    Chain.snack: [
      ItemDef('체리', '🍒'),
      ItemDef('딸기', '🍓'),
      ItemDef('사과', '🍎'),
      ItemDef('복숭아', '🍑'),
      ItemDef('레몬', '🍋'),
      ItemDef('쿠키', '🍪'),
      ItemDef('컵케이크', '🧁'),
      ItemDef('도넛', '🍩'),
      ItemDef('팬케이크', '🥞'),
      ItemDef('파이', '🥧'),
      ItemDef('푸딩', '🍮'),
      ItemDef('조각 케이크', '🍰'),
      ItemDef('파르페', '🍨'),
      ItemDef('생일 케이크', '🎂'),
      ItemDef('피크닉 도시락', '🍱'),
    ],
  };

  static ItemDef item(Chain c, int level) =>
      items[c]![(level - 1).clamp(0, GameConfig.maxLevel - 1)];
}

// ------------------------------------------------------------------ 강화

enum UpgradeType { spawnSpeed, income, autoMerge, spawnLevel, offlineCap }

class UpgradeDef {
  final UpgradeType type;
  final String title;
  final String icon;
  final int maxLevel;
  final double baseCost;
  final double costGrowth;
  const UpgradeDef(
    this.type,
    this.title,
    this.icon,
    this.maxLevel,
    this.baseCost,
    this.costGrowth,
  );

  double costAt(int level) => baseCost * pow(costGrowth, level);
}

class Upgrades {
  static const List<UpgradeDef> all = [
    UpgradeDef(UpgradeType.spawnSpeed, '바구니 속도', '⏱️', 25, 30, 1.55),
    UpgradeDef(UpgradeType.income, '수익 배율', '💰', 100, 60, 1.45),
    UpgradeDef(UpgradeType.autoMerge, '자동 합치기', '🤖', 20, 600, 2.0),
    UpgradeDef(UpgradeType.spawnLevel, '바구니 품질', '⭐', 6, 8000, 40),
    UpgradeDef(UpgradeType.offlineCap, '오프라인 수익 시간', '🌙', 10, 1500, 2.6),
  ];

  static UpgradeDef of(UpgradeType t) => all.firstWhere((u) => u.type == t);

  static double spawnInterval(int lv) => max(0.7, 4.5 * pow(0.9, lv));
  static double incomeMultiplier(int lv) => 1 + 0.25 * lv;
  static double? autoMergeInterval(int lv) =>
      lv <= 0 ? null : max(0.6, 8.0 * pow(0.86, lv - 1));
  static int spawnLevel(int lv) => 1 + lv;
  static Duration offlineCap(int lv) => Duration(hours: 2 + lv);

  static String describe(UpgradeType t, int lv) {
    switch (t) {
      case UpgradeType.spawnSpeed:
        return '${spawnInterval(lv).toStringAsFixed(1)}초마다 생성';
      case UpgradeType.income:
        return '수익 x${incomeMultiplier(lv).toStringAsFixed(2)}';
      case UpgradeType.autoMerge:
        final i = autoMergeInterval(lv);
        return i == null ? '꺼짐' : '${i.toStringAsFixed(1)}초마다 자동';
      case UpgradeType.spawnLevel:
        return 'Lv.${spawnLevel(lv)} 아이템 생성';
      case UpgradeType.offlineCap:
        return '최대 ${offlineCap(lv).inHours}시간';
    }
  }
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
  final String name;
  final String species;
  final String emoji;
  final FriendBuff buff;
  final double perLevel; // 호감도 1당 효과
  final String line; // 탭했을 때 대사
  const FriendDef(
    this.id,
    this.name,
    this.species,
    this.emoji,
    this.buff,
    this.perLevel,
    this.line,
  );

  String buffText(int lv) {
    final v = perLevel * lv * 100;
    final s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
    switch (buff) {
      case FriendBuff.spawnSpeed:
        return '바구니 속도 +$s%';
      case FriendBuff.income:
        return '수익 +$s%';
      case FriendBuff.orderCoins:
        return '부탁 코인 +$s%';
      case FriendBuff.lucky:
        return '행운 생성 +$s%';
      case FriendBuff.offline:
        return '오프라인 수익 +$s%';
      case FriendBuff.starBonus:
        return '별 추가 획득 확률 +$s%';
      case FriendBuff.autoMerge:
        return '자동 합치기 속도 +$s%';
    }
  }
}

class Friends {
  static const List<FriendDef> all = [
    FriendDef(
      'bori',
      '보리',
      '토끼',
      '🐰',
      FriendBuff.spawnSpeed,
      0.03,
      '오늘도 정원 가꾸기 좋은 날이야!',
    ),
    FriendDef(
      'dubu',
      '두부',
      '곰',
      '🐻',
      FriendBuff.income,
      0.05,
      '꿀 냄새가 나는 것 같아…',
    ),
    FriendDef(
      'kwak',
      '꽥이',
      '오리',
      '🦆',
      FriendBuff.orderCoins,
      0.10,
      '연못 물이 반짝반짝해!',
    ),
    FriendDef(
      'nabi',
      '나비',
      '고양이',
      '🐱',
      FriendBuff.lucky,
      0.01,
      '햇볕 좋은 자리 찾았다냥.',
    ),
    FriendDef(
      'dotori',
      '도토리',
      '다람쥐',
      '🐿️',
      FriendBuff.offline,
      0.03,
      '도토리 숨겨둔 곳 비밀이야!',
    ),
    FriendDef(
      'mochi',
      '모찌',
      '판다',
      '🐼',
      FriendBuff.income,
      0.05,
      '대나무 차 한 잔 할래?',
    ),
    FriendDef(
      'danpung',
      '단풍',
      '여우',
      '🦊',
      FriendBuff.starBonus,
      0.03,
      '밤하늘 별이 정말 예쁘지?',
    ),
    FriendDef(
      'kongtteok',
      '콩떡',
      '햄스터',
      '🐹',
      FriendBuff.autoMerge,
      0.04,
      '쳇바퀴 돌리듯 열심히!',
    ),
  ];

  static FriendDef byId(String id) => all.firstWhere((f) => f.id == id);

  /// 처음부터 함께하는 친구.
  static const String starter = 'bori';

  static const int maxAffection = 10;

  /// 부탁 N번 들어줄 때마다 호감도 1.
  static const int deliveriesPerAffection = 2;

  static const String visitorEmoji = '🦔';
}

// ------------------------------------------------------------------ 정원

class DecorDef {
  final String name;
  final String emoji;
  final double x; // 정원 씬 안의 상대 위치 (0~1)
  final double y;
  final String? bringsFriend; // 설치하면 놀러 오는 친구
  const DecorDef(this.name, this.emoji, this.x, this.y, {this.bringsFriend});
}

class AreaDef {
  final String name;
  final String emoji;
  final int sky; // 배경 색 (임시)
  final int ground;
  final List<DecorDef> decor;
  const AreaDef(this.name, this.emoji, this.sky, this.ground, this.decor);
}

class Garden {
  static const int slotsPerArea = 8;

  static const List<AreaDef> areas = [
    AreaDef('햇살 앞마당', '🏡', 0xFFBFE6F7, 0xFFA8D88E, [
      DecorDef('큰 나무', '🌳', 0.14, 0.30),
      DecorDef('나무 벤치', '🪑', 0.42, 0.34),
      DecorDef('우체통', '📮', 0.70, 0.30),
      DecorDef('작은 텃밭', '🥕', 0.88, 0.52, bringsFriend: 'dubu'),
      DecorDef('등불', '🏮', 0.12, 0.74),
      DecorDef('새 모이대', '🐦', 0.38, 0.70),
      DecorDef('오두막', '🛖', 0.64, 0.76),
      DecorDef('분수', '⛲', 0.88, 0.84),
    ]),
    AreaDef('반짝 연못', '🦆', 0xFFC6E2FA, 0xFF9CD3B0, [
      DecorDef('징검다리', '🪨', 0.14, 0.32),
      DecorDef('수련', '🪷', 0.42, 0.30, bringsFriend: 'kwak'),
      DecorDef('낚시터', '🎣', 0.70, 0.34),
      DecorDef('나룻배', '🛶', 0.88, 0.52),
      DecorDef('갈대숲', '🌾', 0.12, 0.74),
      DecorDef('통나무 의자', '🪵', 0.38, 0.70, bringsFriend: 'nabi'),
      DecorDef('텐트', '🏕️', 0.64, 0.76),
      DecorDef('나무다리', '🌉', 0.88, 0.84),
    ]),
    AreaDef('꽃향기 온실', '🪴', 0xFFF6E3F0, 0xFFB9DFA0, [
      DecorDef('유리 온실', '🪟', 0.14, 0.30),
      DecorDef('선인장 화분', '🌵', 0.42, 0.34),
      DecorDef('버섯 정원', '🍄', 0.70, 0.30, bringsFriend: 'dotori'),
      DecorDef('물뿌리개', '🚿', 0.88, 0.52),
      DecorDef('해바라기 밭', '🌻', 0.12, 0.74),
      DecorDef('티 테이블', '🫖', 0.38, 0.70),
      DecorDef('대나무', '🎋', 0.64, 0.76, bringsFriend: 'mochi'),
      DecorDef('풍경', '🎐', 0.88, 0.84),
    ]),
    AreaDef('별빛 언덕', '🌙', 0xFF2E3A6B, 0xFF6F9A6A, [
      DecorDef('망원경', '🔭', 0.14, 0.30),
      DecorDef('캠핑 텐트', '⛺', 0.42, 0.34),
      DecorDef('모닥불', '🔥', 0.70, 0.30, bringsFriend: 'danpung'),
      DecorDef('관람차', '🎡', 0.88, 0.52),
      DecorDef('회전목마', '🎠', 0.12, 0.74),
      DecorDef('달 조형물', '🌙', 0.38, 0.70),
      DecorDef('작은 성', '🏰', 0.64, 0.76, bringsFriend: 'kongtteok'),
      DecorDef('불꽃놀이', '🎆', 0.88, 0.84),
    ]),
  ];

  /// 정해진 구역 이후로는 순환하며 "N번째" 로 무한 진행 (새 친구는 없음).
  static AreaDef areaAt(int index) {
    final base = areas[index % areas.length];
    if (index < areas.length) return base;
    final round = index ~/ areas.length + 1;
    final decor = [
      for (final d in base.decor) DecorDef(d.name, d.emoji, d.x, d.y),
    ];
    return AreaDef(
      '${base.name} ($round번째)',
      base.emoji,
      base.sky,
      base.ground,
      decor,
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

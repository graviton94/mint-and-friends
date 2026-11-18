import 'dart:math';

/// 밸런스/콘텐츠 상수. 숫자 튜닝은 대부분 이 파일에서 한다.
class GameConfig {
  static const int cols = 5;
  static const int rows = 7;
  static const int cellCount = cols * rows;

  /// 꽃 체인 (레벨 1부터). 아트가 나오기 전까지 이모지 플레이스홀더.
  static const List<ItemDef> items = [
    ItemDef('씨앗', '🌰'),
    ItemDef('새싹', '🌱'),
    ItemDef('클로버', '☘️'),
    ItemDef('어린 잎', '🌿'),
    ItemDef('꽃봉오리', '🪴'),
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
  ];

  /// 15종 꽃 x 3등급(일반/황금/다이아). 등급은 같은 아트에 테두리·광택 효과만 추가.
  static const List<String> tierNames = ['', '황금 ', '다이아 '];
  static int get maxLevel => items.length * tierNames.length;

  static int tierOf(int level) => ((level - 1) ~/ items.length).clamp(0, tierNames.length - 1);

  static ItemDef item(int level) {
    final base = items[(level - 1) % items.length];
    final tier = tierOf(level);
    return tier == 0 ? base : ItemDef('${tierNames[tier]}${base.name}', base.emoji);
  }

  /// 아이템 1개의 초당 코인 생산량.
  static double incomeOf(int level) => pow(2.4, level - 1).toDouble();

  /// 최고 레벨 두 개를 합치면 사라지면서 지급되는 코인 (해당 아이템 N초분).
  static const double maxMergePayoutSeconds = 1800;

  /// 신규 꽃 발견 보너스 (해당 레벨 아이템 N초분).
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

  /// 전면 광고 최소 간격 / 앱 시작 후 유예.
  static const Duration interstitialGap = Duration(minutes: 3);
  static const Duration interstitialGrace = Duration(minutes: 2);
}

class ItemDef {
  final String name;
  final String emoji;
  const ItemDef(this.name, this.emoji);
}

enum UpgradeType { spawnSpeed, spawnLevel, income, autoMerge, offlineCap }

class UpgradeDef {
  final UpgradeType type;
  final String title;
  final String icon;
  final int maxLevel;
  final double baseCost;
  final double costGrowth;
  const UpgradeDef(this.type, this.title, this.icon, this.maxLevel, this.baseCost, this.costGrowth);

  double costAt(int level) => baseCost * pow(costGrowth, level);
}

class Upgrades {
  static const List<UpgradeDef> all = [
    UpgradeDef(UpgradeType.spawnSpeed, '씨앗 생성 속도', '⏱️', 25, 30, 1.55),
    UpgradeDef(UpgradeType.income, '수익 배율', '💰', 200, 60, 1.45),
    UpgradeDef(UpgradeType.autoMerge, '자동 합치기', '🤖', 20, 800, 2.1),
    UpgradeDef(UpgradeType.spawnLevel, '씨앗 품질', '⭐', 30, 20000, 30),
    UpgradeDef(UpgradeType.offlineCap, '오프라인 수익 시간', '🌙', 10, 1500, 2.6),
  ];

  static UpgradeDef of(UpgradeType t) => all.firstWhere((u) => u.type == t);

  /// 스폰 간격(초).
  static double spawnInterval(int lv) => max(0.7, 5.0 * pow(0.9, lv));

  /// 수익 배율.
  static double incomeMultiplier(int lv) => 1 + 0.25 * lv;

  /// 자동 합치기 간격(초). lv 0 이면 꺼짐.
  static double? autoMergeInterval(int lv) => lv <= 0 ? null : max(0.6, 8.0 * pow(0.86, lv - 1));

  /// 스폰 레벨.
  static int spawnLevel(int lv) => 1 + lv;

  /// 오프라인 최대 누적 시간.
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
        return 'Lv.${spawnLevel(lv)} ${GameConfig.item(spawnLevel(lv)).name} 생성';
      case UpgradeType.offlineCap:
        return '최대 ${offlineCap(lv).inHours}시간';
    }
  }
}

/// 정원 복구(메타) 콘텐츠.
class GardenArea {
  final String name;
  final String emoji;
  final List<GardenTask> tasks;
  const GardenArea(this.name, this.emoji, this.tasks);
}

class GardenTask {
  final String name;
  final String emoji;
  const GardenTask(this.name, this.emoji);
}

class Garden {
  static const List<GardenArea> areas = [
    GardenArea('버려진 앞마당', '🏡', [
      GardenTask('잡초 뽑기', '🧹'),
      GardenTask('울타리 고치기', '🪵'),
      GardenTask('화단 만들기', '🟫'),
      GardenTask('벤치 놓기', '🪑'),
      GardenTask('우체통 세우기', '📮'),
    ]),
    GardenArea('작은 연못', '🦆', [
      GardenTask('연못 청소', '🫧'),
      GardenTask('징검다리 놓기', '🪨'),
      GardenTask('수련 심기', '🪷'),
      GardenTask('오리 집 짓기', '🛖'),
      GardenTask('분수 복구', '⛲'),
    ]),
    GardenArea('온실', '🏠', [
      GardenTask('유리창 교체', '🪟'),
      GardenTask('선반 설치', '🗄️'),
      GardenTask('화분 정리', '🪴'),
      GardenTask('물뿌리개 걸기', '🚿'),
      GardenTask('난초 들이기', '🌸'),
    ]),
    GardenArea('티 가든', '🫖', [
      GardenTask('테라스 깔기', '🟨'),
      GardenTask('파라솔 펴기', '⛱️'),
      GardenTask('티 테이블', '🫖'),
      GardenTask('조명 달기', '🏮'),
      GardenTask('장미 아치', '🌹'),
    ]),
  ];

  static const int tasksPerArea = 5;

  /// 정해진 영역 이후로는 순환하며 "N번째 정원" 으로 무한 진행.
  static GardenArea areaAt(int index) {
    final base = areas[index % areas.length];
    if (index < areas.length) return base;
    final round = index ~/ areas.length + 1;
    return GardenArea('${base.name} ($round번째)', base.emoji, base.tasks);
  }

  /// 전체 진행 순번(n = area*5 + task) 기준 비용.
  static double taskCost(int n) => 400.0 * pow(3.2, n);

  /// 작업 1개 완료 시 영구 수익 보너스 (+%), 영역 완료 시 추가 보너스.
  static const double taskIncomeBonus = 0.10;
  static const double areaIncomeBonus = 0.50;
}

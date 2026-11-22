/// 출시 뒤 앱 업데이트 없이 바꿀 수 있는 경제 변수 (Firebase Remote Config, 바이블 D-014).
/// 값은 게임 코드의 기본값이고, RemoteTuning 이 서버 값으로 덮어쓴다. 범위를 벗어난 값은 무시한다.
class Tuning {
  /// 에너지 1 회복 간격(초).
  static double energyRegenSeconds = 150;

  /// 에너지 광고 1회 보상.
  static int energyAdAmount = 20;

  /// 다이아 에너지 충전: 첫 가격 · 같은 날 다시 살 때 오르는 폭 · 상한.
  static int refillBase = 60;
  static int refillStep = 30;
  static int refillMax = 150;

  /// 낮은 단계 부탁 확률 (판에 남는 낮은 아이템 소모처).
  static double easyOrderChance = 0.33;

  /// 구조 부탁 확률.
  static double rescueChance = 0.25;

  /// 오늘의 시장 가격 계수 (에너지값 × (base + 2·레벨)).
  static int marketPriceBase = 10;

  /// 정원 재단장: 씨앗 1개당 영구 수입 · 씨앗 공식 기준 코인 (D-031).
  static double seedIncome = 0.10;
  static double seedCoinBase = 1e9;

  /// 코인 수입 · 가격 전체 배율 (인플레이션 조정용, 둘 다 같은 배율이라 비율은 그대로).
  static double coinScale = 1.0;

  /// 구역 꾸미기 별 합계 배율 (구역 진행 속도 A/B).
  static double areaStarScale = 1.6;

  /// 이 버전 코드보다 낮은 앱은 필수 업데이트 (전체 화면). 0 = 없음.
  static int minVersionCode = 0;

  /// 서버 키 → (최소, 최대, 적용).
  static final Map<String, (num, num, void Function(num))> keys = {
    'energy_regen_seconds': (60, 600, (v) => energyRegenSeconds = v.toDouble()),
    'energy_ad_amount': (5, 100, (v) => energyAdAmount = v.toInt()),
    'refill_base': (10, 200, (v) => refillBase = v.toInt()),
    'refill_step': (0, 100, (v) => refillStep = v.toInt()),
    'refill_max': (10, 500, (v) => refillMax = v.toInt()),
    'rescue_chance': (0, 1, (v) => rescueChance = v.toDouble()),
    'easy_order_chance': (0, 1, (v) => easyOrderChance = v.toDouble()),
    'market_price_base': (1, 100, (v) => marketPriceBase = v.toInt()),
    'area_star_scale': (0.3, 3, (v) => areaStarScale = v.toDouble()),
    'coin_scale': (0.1, 10, (v) => coinScale = v.toDouble()),
    'seed_income': (0.01, 1, (v) => seedIncome = v.toDouble()),
    'seed_coin_base': (1e6, 1e15, (v) => seedCoinBase = v.toDouble()),
    'min_version_code': (0, 1e9, (v) => minVersionCode = v.toInt()),
  };

  /// 기본값 표 (Remote Config 콘솔에 넣을 값과 같다).
  static Map<String, Object> get defaults => {
    'energy_regen_seconds': 150,
    'energy_ad_amount': 20,
    'refill_base': 60,
    'refill_step': 30,
    'refill_max': 150,
    'rescue_chance': 0.25,
    'easy_order_chance': 0.33,
    'market_price_base': 10,
    'area_star_scale': 1.6,
    'coin_scale': 1.0,
    'seed_income': 0.10,
    'seed_coin_base': 1e9,
    'min_version_code': 0,
  };

  /// 서버 값 하나 적용. 범위 밖이면 false.
  static bool apply(String key, num value) {
    final k = keys[key];
    if (k == null || value < k.$1 || value > k.$2) return false;
    k.$3(value);
    return true;
  }
}

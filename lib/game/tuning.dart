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

  /// 구조 부탁 확률.
  static double rescueChance = 0.25;

  /// 오늘의 시장 가격 계수 (에너지값 × (base + 2·레벨)).
  static int marketPriceBase = 10;

  /// 구역 꾸미기 별 합계 배율 (구역 진행 속도 A/B).
  static double areaStarScale = 1.6;

  /// 서버 키 → (최소, 최대, 적용).
  static final Map<String, (num, num, void Function(num))> keys = {
    'energy_regen_seconds': (60, 600, (v) => energyRegenSeconds = v.toDouble()),
    'energy_ad_amount': (5, 100, (v) => energyAdAmount = v.toInt()),
    'refill_base': (10, 200, (v) => refillBase = v.toInt()),
    'refill_step': (0, 100, (v) => refillStep = v.toInt()),
    'refill_max': (10, 500, (v) => refillMax = v.toInt()),
    'rescue_chance': (0, 1, (v) => rescueChance = v.toDouble()),
    'market_price_base': (1, 100, (v) => marketPriceBase = v.toInt()),
    'area_star_scale': (0.3, 3, (v) => areaStarScale = v.toDouble()),
  };

  /// 기본값 표 (Remote Config 콘솔에 넣을 값과 같다).
  static Map<String, Object> get defaults => {
    'energy_regen_seconds': 150,
    'energy_ad_amount': 20,
    'refill_base': 60,
    'refill_step': 30,
    'refill_max': 150,
    'rescue_chance': 0.25,
    'market_price_base': 10,
    'area_star_scale': 1.0,
  };

  /// 서버 값 하나 적용. 범위 밖이면 false.
  static bool apply(String key, num value) {
    final k = keys[key];
    if (k == null || value < k.$1 || value > k.$2) return false;
    k.$3(value);
    return true;
  }
}

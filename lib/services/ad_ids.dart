import 'package:flutter/foundation.dart';

/// AdMob 광고 단위 ID.
/// 디버그 빌드는 항상 Google 공식 테스트 ID를 쓴다 (실광고 클릭 → 계정 정지 위험 방지).
/// 출시 전 아래 _prod* 값과 android/app/src/main/AndroidManifest.xml 의 APPLICATION_ID 를 교체할 것.
class AdIds {
  // 스토어 빌드(aab.yml)는 시크릿 ADMOB_* 을 --dart-define 으로 받는다. 없으면 테스트 ID.
  static const _prodBanner = String.fromEnvironment(
    'ADMOB_BANNER',
    defaultValue: 'ca-app-pub-3940256099942544/9214589741',
  );
  static const _prodInterstitial = String.fromEnvironment(
    'ADMOB_INTERSTITIAL',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );
  static const _prodRewarded = String.fromEnvironment(
    'ADMOB_REWARDED',
    defaultValue: 'ca-app-pub-3940256099942544/5224354917',
  );

  static const _testBanner = 'ca-app-pub-3940256099942544/9214589741';
  static const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const _testRewarded = 'ca-app-pub-3940256099942544/5224354917';

  static String get banner => kReleaseMode ? _prodBanner : _testBanner;
  static String get interstitial =>
      kReleaseMode ? _prodInterstitial : _testInterstitial;
  static String get rewarded => kReleaseMode ? _prodRewarded : _testRewarded;
}

/// Play Console 에 등록할 구독 상품 ID (정원 패스: 광고 제거 · 매일 다이아 · 별 부탁 +2 · 보관 칸 2).
const String kRemoveAdsProductId = 'garden_pass_1m';

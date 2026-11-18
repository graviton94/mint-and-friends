import 'package:flutter/foundation.dart';

/// AdMob 광고 단위 ID.
/// 디버그 빌드는 항상 Google 공식 테스트 ID를 쓴다 (실광고 클릭 → 계정 정지 위험 방지).
/// 출시 전 아래 _prod* 값과 android/app/src/main/AndroidManifest.xml 의 APPLICATION_ID 를 교체할 것.
class AdIds {
  static const _prodBanner = 'ca-app-pub-3940256099942544/9214589741';
  static const _prodInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const _prodRewarded = 'ca-app-pub-3940256099942544/5224354917';

  static const _testBanner = 'ca-app-pub-3940256099942544/9214589741';
  static const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const _testRewarded = 'ca-app-pub-3940256099942544/5224354917';

  static String get banner => kReleaseMode ? _prodBanner : _testBanner;
  static String get interstitial => kReleaseMode ? _prodInterstitial : _testInterstitial;
  static String get rewarded => kReleaseMode ? _prodRewarded : _testRewarded;
}

/// Play Console 에 등록할 구독 상품 ID.
const String kRemoveAdsProductId = 'remove_ads_1m';

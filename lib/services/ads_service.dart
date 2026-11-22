import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../game/config.dart';
import 'ad_ids.dart';

/// 광고 로딩/표시 담당. adFree 이면 전면·배너는 띄우지 않고 보상형은 즉시 보상.
class AdsService extends ChangeNotifier {
  AdsService({required this.isAdFree});

  final bool Function() isAdFree;

  bool _initialized = false;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _loadingRewarded = false;
  DateTime _startedAt = DateTime.now();
  DateTime? _lastInterstitial;

  bool get rewardedReady => isAdFree() || _rewarded != null;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _startedAt = DateTime.now();
    await _gatherConsent();
    await MobileAds.instance.initialize();
    _loadInterstitial();
    _loadRewarded();
  }

  /// UMP 동의 (EEA/영국 사용자 필수, 그 외 지역은 자동 통과).
  Future<void> _gatherConsent() {
    final c = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((_) {
          if (!c.isCompleted) c.complete();
        });
      },
      (_) {
        if (!c.isCompleted) c.complete();
      },
    );
    return c.future.timeout(const Duration(seconds: 8), onTimeout: () {});
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) {
          _interstitial = null;
          Future.delayed(const Duration(seconds: 30), _loadInterstitial);
        },
      ),
    );
  }

  void _loadRewarded() {
    if (_loadingRewarded || _rewarded != null) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingRewarded = false;
          _rewarded = ad;
          notifyListeners();
        },
        onAdFailedToLoad: (_) {
          _loadingRewarded = false;
          _rewarded = null;
          notifyListeners();
          Future.delayed(const Duration(seconds: 20), _loadRewarded);
        },
      ),
    );
  }

  /// 자연스러운 휴식 지점(정원 작업 완료 등)에서 호출. 빈도 제한은 여기서 처리.
  void maybeShowInterstitial() {
    if (isAdFree()) return;
    final now = DateTime.now();
    if (now.difference(_startedAt) < GameConfig.interstitialGrace) return;
    if (_lastInterstitial != null &&
        now.difference(_lastInterstitial!) < GameConfig.interstitialGap) {
      return;
    }
    final ad = _interstitial;
    if (ad == null) return;
    _interstitial = null;
    _lastInterstitial = now;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        _loadInterstitial();
      },
    );
    ad.show();
  }

  /// 보상형 광고. 보상을 받았으면 true. 광고제거 구독자는 광고 없이 즉시 true.
  Future<bool> showRewarded() async {
    if (isAdFree()) return true;
    final ad = _rewarded;
    if (ad == null) {
      _loadRewarded();
      return false;
    }
    _rewarded = null;
    notifyListeners();
    final done = Completer<bool>();
    var earned = false, dismissed = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadRewarded();
        // 일부 기기 · 광고는 '보상' 알림이 창을 닫은 뒤에 온다: 잠깐 더 기다린다
        dismissed = true;
        if (earned) {
          if (!done.isCompleted) done.complete(true);
        } else {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (!done.isCompleted) done.complete(earned);
          });
        }
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        _loadRewarded();
        if (!done.isCompleted) done.complete(false);
      },
    );
    await ad.show(
      onUserEarnedReward: (_, _) {
        earned = true;
        // 창을 닫은 뒤에 온 보상 알림: 기다리던 것을 바로 끝낸다
        if (dismissed && !done.isCompleted) done.complete(true);
      },
    );
    return done.future;
  }
}

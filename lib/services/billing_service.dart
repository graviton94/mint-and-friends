import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_ids.dart';

/// 광고제거 1개월 구독.
/// 앱 시작 시 restorePurchases 로 활성 구독을 다시 받아 확인한다.
/// (MVP: 클라이언트 검증. 매출이 붙으면 서버 영수증 검증 추가 권장)
class BillingService extends ChangeNotifier {
  static const _cacheKey = 'ad_free_cache';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool available = false;
  bool adFree = false;
  bool purchasing = false;
  ProductDetails? product;
  bool _seenActiveThisSession = false;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    adFree = prefs.getBool(_cacheKey) ?? false; // 오프라인 대비 캐시
    notifyListeners();

    available = await _iap.isAvailable();
    if (!available) return;

    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (_) {});

    final resp = await _iap.queryProductDetails({kRemoveAdsProductId});
    if (resp.productDetails.isNotEmpty) product = resp.productDetails.first;
    notifyListeners();

    await _iap.restorePurchases();
    // 복원 결과가 스트림으로 도착할 시간을 준 뒤, 활성 구독이 없으면 해제.
    Future.delayed(const Duration(seconds: 6), () async {
      if (!_seenActiveThisSession && adFree) {
        await _setAdFree(false);
      }
    });
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.productID != kRemoveAdsProductId) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _seenActiveThisSession = true;
          await _setAdFree(true);
          break;
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          break;
        case PurchaseStatus.pending:
          break;
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
    purchasing = false;
    notifyListeners();
  }

  Future<void> _setAdFree(bool v) async {
    adFree = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cacheKey, v);
    notifyListeners();
  }

  Future<void> buyRemoveAds() async {
    final p = product;
    if (p == null || purchasing) return;
    purchasing = true;
    notifyListeners();
    try {
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: p),
      );
    } catch (_) {
      purchasing = false;
      notifyListeners();
    }
  }

  Future<void> restore() => _iap.restorePurchases();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

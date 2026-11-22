import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/config.dart';
import 'ad_ids.dart';
import 'analytics_service.dart';

/// 광고제거 1개월 구독 + 다이아 팩(소모형).
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

  /// 다이아 팩 상품 (스토어에 등록된 것만).
  final Map<String, ProductDetails> gemProducts = {};

  /// 다이아 결제가 끝나면 게임에 다이아를 넣는다 (main 이 연결).
  void Function(GemPack pack)? onGems;

  /// 새싹 정원 패키지 (소모형으로 팔고, 한 번만 지급은 게임이 막는다).
  ProductDetails? starter;
  void Function()? onStarter;

  /// 광고 제거를 새로 샀을 때 (복원은 제외).
  void Function()? onAdFree;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    adFree = prefs.getBool(_cacheKey) ?? false; // 오프라인 대비 캐시
    notifyListeners();

    available = await _iap.isAvailable();
    if (!available) return;

    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (_) {});

    final resp = await _iap.queryProductDetails({
      kRemoveAdsProductId,
      Starter.productId,
      for (final p in Gems.packs) p.id,
    });
    for (final d in resp.productDetails) {
      if (d.id == Starter.productId) {
        starter = d;
      } else if (d.id == kRemoveAdsProductId) {
        product = d;
      } else {
        gemProducts[d.id] = d;
      }
    }
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
      if (p.status == PurchaseStatus.canceled) {
        Analytics.instance.iapCancel(p.productID);
      } else if (p.status == PurchaseStatus.error) {
        Analytics.instance.iapError(p.productID, p.error?.code ?? 'unknown');
      }
      if (p.productID == Starter.productId) {
        if (p.status == PurchaseStatus.purchased) {
          Analytics.instance.purchase(p.productID);
          onStarter?.call();
        }
        if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        continue;
      }
      final pack = Gems.pack(p.productID);
      if (pack != null) {
        // 소모형: 결제 완료 시 한 번만 지급 (autoConsume 이 소비 처리)
        if (p.status == PurchaseStatus.purchased) {
          Analytics.instance.purchase(p.productID);
          onGems?.call(pack);
        }
        if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        continue;
      }
      if (p.productID != kRemoveAdsProductId) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
          Analytics.instance.purchase(p.productID);
          _seenActiveThisSession = true;
          final wasFree = adFree;
          await _setAdFree(true);
          if (!wasFree) onAdFree?.call();
          break;
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
    Analytics.instance.iapBegin(p.id);
    try {
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: p),
      );
    } catch (_) {
      purchasing = false;
      notifyListeners();
    }
  }

  Future<void> buyStarter() async {
    final d = starter;
    if (d == null || purchasing) return;
    purchasing = true;
    notifyListeners();
    Analytics.instance.iapBegin(d.id);
    try {
      await _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: d));
    } catch (_) {
      purchasing = false;
      notifyListeners();
    }
  }

  Future<void> buyGems(GemPack pack) async {
    final d = gemProducts[pack.id];
    if (d == null || purchasing) return;
    purchasing = true;
    notifyListeners();
    Analytics.instance.iapBegin(d.id);
    try {
      await _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: d));
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

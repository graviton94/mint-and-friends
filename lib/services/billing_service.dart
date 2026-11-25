import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/config.dart';
import 'ad_ids.dart';
import 'analytics_service.dart';

/// 소모형 결제를 지급했는지 기억한다 (purchaseID 기준, 기기에 저장).
/// 같은 결제가 purchased · restored 로 여러 번 와도 한 번만 지급한다.
class ConsumableLedger {
  static const key = 'iap_granted_ids';
  ConsumableLedger(this._prefs);
  final SharedPreferences _prefs;

  /// 결제를 구분하는 값 (주문 번호, 없으면 결제 토큰).
  static String idOf(PurchaseDetails p) {
    final id = p.purchaseID;
    return id != null && id.isNotEmpty
        ? id
        : p.verificationData.serverVerificationData;
  }

  bool granted(String id) =>
      (_prefs.getStringList(key) ?? const []).contains(id);

  Future<void> mark(String id) async {
    final list = _prefs.getStringList(key) ?? <String>[];
    if (list.contains(id)) return;
    list.add(id);
    // 너무 길어지지 않게 오래된 것부터 버린다 (소비가 끝난 결제는 다시 오지 않는다)
    if (list.length > 200) list.removeRange(0, list.length - 200);
    await _prefs.setStringList(key, list);
  }
}

/// 광고제거 1개월 구독 + 다이아 팩(소모형).
/// 앱 시작 시 restorePurchases 로 활성 구독과 아직 소비되지 않은 소모형 결제를 다시 받는다.
/// (MVP: 클라이언트 검증. 매출이 붙으면 서버 영수증 검증 추가 권장)
class BillingService extends ChangeNotifier {
  static const _cacheKey = 'ad_free_cache';

  BillingService({
    @visibleForTesting Future<void> Function(PurchaseDetails p)? complete,
    @visibleForTesting Future<void> Function(PurchaseDetails p)? consume,
  }) : _completeOverride = complete,
       _consumeOverride = consume;

  late final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final Future<void> Function(PurchaseDetails p)? _completeOverride;
  final Future<void> Function(PurchaseDetails p)? _consumeOverride;

  bool available = false;
  bool adFree = false;
  bool purchasing = false;
  ProductDetails? product;
  bool _seenActiveThisSession = false;

  /// 다이아 팩 상품 (스토어에 등록된 것만).
  final Map<String, ProductDetails> gemProducts = {};

  /// 다이아 결제가 끝나면 게임에 다이아를 넣는다 (main 이 연결).
  /// 연결 전에 도착한 결제(시작 때 복원 등)는 연결되는 순간 처리한다.
  void Function(GemPack pack)? get onGems => _onGems;
  set onGems(void Function(GemPack pack)? f) {
    _onGems = f;
    _flushWaiting();
  }

  void Function(GemPack pack)? _onGems;

  /// 새싹 정원 패키지 (소모형으로 팔고, 한 번만 지급은 게임이 막는다).
  ProductDetails? starter;
  void Function()? get onStarter => _onStarter;
  set onStarter(void Function()? f) {
    _onStarter = f;
    _flushWaiting();
  }

  void Function()? _onStarter;

  /// 지급한 소모형 결제 (주문번호, 상품): 환불 확인용으로 서버에 남긴다.
  void Function(String orderId, String product)? onRecord;

  /// 지급할 곳이 아직 연결되지 않아 기다리는 소모형 결제.
  final List<PurchaseDetails> _waiting = [];

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

    // 활성 구독 + 아직 소비되지 않은 소모형 결제(대기 뒤 완료 · 앱 종료 등)를 다시 받는다
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('restore failed: $e');
      return; // 복원 결과를 모르면 광고 제거를 풀지 않는다
    }
    // 복원 결과가 스트림으로 도착할 시간을 준 뒤, 활성 구독이 없으면 해제.
    Future.delayed(const Duration(seconds: 6), () async {
      if (!_seenActiveThisSession && adFree) {
        await _setAdFree(false);
      }
    });
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) =>
      handlePurchases(list);

  @visibleForTesting
  Future<void> handlePurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.status == PurchaseStatus.canceled) {
        Analytics.instance.iapCancel(p.productID);
      } else if (p.status == PurchaseStatus.error) {
        Analytics.instance.iapError(p.productID, p.error?.code ?? 'unknown');
      }
      if (p.productID == Starter.productId || Gems.pack(p.productID) != null) {
        await _onConsumable(p);
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
      if (p.pendingCompletePurchase) await _complete(p);
    }
    purchasing = false;
    notifyListeners();
  }

  /// 소모형(다이아 팩 · 새싹 정원): purchased 든 restored 든 한 번만 지급하고,
  /// 지급한 뒤에 직접 소비해서 다시 살 수 있게 한다.
  Future<void> _onConsumable(PurchaseDetails p) async {
    final ok =
        p.status == PurchaseStatus.purchased ||
        p.status == PurchaseStatus.restored;
    if (!ok) {
      // 대기 중(pending)은 아직 돈이 안 들어왔다: 지급 · 소비하지 않는다
      if (p.status != PurchaseStatus.pending && p.pendingCompletePurchase) {
        await _complete(p);
      }
      return;
    }
    final isStarter = p.productID == Starter.productId;
    final pack = Gems.pack(p.productID);
    if ((isStarter ? _onStarter : _onGems) == null) {
      // 게임이 아직 연결되지 않았다: 소비하지 않고 기다린다
      if (!_waiting.any((w) => _sameId(w, p))) _waiting.add(p);
      return;
    }
    final ledger = ConsumableLedger(await SharedPreferences.getInstance());
    final id = ConsumableLedger.idOf(p);
    if (!ledger.granted(id)) {
      // 먼저 기록하고 지급 (지급 도중 앱이 꺼져도 두 번 주지 않게)
      await ledger.mark(id);
      Analytics.instance.purchase(p.productID);
      if (isStarter) {
        _onStarter?.call();
      } else {
        _onGems?.call(pack!);
      }
      // 환불 확인용 기록 (주문번호 GPA.… 가 있을 때만, D-066)
      final order = p.purchaseID;
      if (order != null && order.startsWith('GPA.')) {
        onRecord?.call(order, p.productID);
      }
    }
    if (p.pendingCompletePurchase) await _complete(p);
    await _consume(p);
  }

  static bool _sameId(PurchaseDetails a, PurchaseDetails b) =>
      ConsumableLedger.idOf(a) == ConsumableLedger.idOf(b);

  void _flushWaiting() {
    if (_waiting.isEmpty) return;
    final ready = [
      for (final p in _waiting)
        if ((p.productID == Starter.productId ? _onStarter : _onGems) != null)
          p,
    ];
    if (ready.isEmpty) return;
    _waiting.removeWhere(ready.contains);
    unawaited(handlePurchases(ready));
  }

  Future<void> _complete(PurchaseDetails p) async {
    final f = _completeOverride;
    if (f != null) return f(p);
    try {
      await _iap.completePurchase(p);
    } catch (e) {
      debugPrint('completePurchase failed: $e');
    }
  }

  /// Android 소모형은 소비해야 다시 살 수 있다 (iOS 는 completePurchase 로 끝).
  Future<void> _consume(PurchaseDetails p) async {
    final f = _consumeOverride;
    if (f != null) return f(p);
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final r = await _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
          .consumePurchase(p);
      if (r.responseCode != BillingResponse.ok) {
        debugPrint('consume failed: ${r.responseCode}'); // 다음 복원 때 다시
      }
    } catch (e) {
      debugPrint('consume failed: $e');
    }
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
      // 소비는 지급한 뒤에 직접 한다 (자동 소비는 지급 전에 소비해 버린다)
      await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: d),
        autoConsume: false,
      );
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
      // 소비는 지급한 뒤에 직접 한다 (자동 소비는 지급 전에 소비해 버린다)
      await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: d),
        autoConsume: false,
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

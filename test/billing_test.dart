import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/services/billing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

PurchaseDetails buy(String product, String id, PurchaseStatus status) =>
    PurchaseDetails(
      purchaseID: id,
      productID: product,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: 'token-$id',
        source: 'google_play',
      ),
      transactionDate: '0',
      status: status,
    )..pendingCompletePurchase = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> completed, consumed;
  late List<GemPack> gems;
  late int starters;

  BillingService make() {
    final b = BillingService(
      complete: (p) async => completed.add(p.purchaseID!),
      consume: (p) async => consumed.add(p.purchaseID!),
    );
    b.onGems = gems.add;
    b.onStarter = () => starters++;
    return b;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    completed = [];
    consumed = [];
    gems = [];
    starters = 0;
  });

  final pack = Gems.packs.first;

  test('복원(restored)으로 온 소모형 결제도 지급하고 소비한다', () async {
    final b = make();
    await b.handlePurchases([buy(pack.id, 'o1', PurchaseStatus.restored)]);
    await b.handlePurchases([
      buy(Starter.productId, 'o2', PurchaseStatus.restored),
    ]);
    expect(gems, [pack]);
    expect(starters, 1);
    expect(consumed, ['o1', 'o2']);
    expect(completed, ['o1', 'o2']);
  });

  test('같은 결제가 여러 번 와도 (앱을 다시 켜도) 한 번만 지급한다', () async {
    await make().handlePurchases([
      buy(pack.id, 'o1', PurchaseStatus.purchased),
    ]);
    await make().handlePurchases([buy(pack.id, 'o1', PurchaseStatus.restored)]);
    expect(gems, [pack]);
    expect(consumed, ['o1', 'o1']); // 소비는 다시 시도해도 괜찮다
  });

  test('대기(pending) 결제는 지급 · 소비하지 않고, 완료되면 지급한다', () async {
    final b = make();
    await b.handlePurchases([buy(pack.id, 'o1', PurchaseStatus.pending)]);
    expect(gems, isEmpty);
    expect(consumed, isEmpty);
    await b.handlePurchases([buy(pack.id, 'o1', PurchaseStatus.purchased)]);
    expect(gems, [pack]);
    expect(consumed, ['o1']);
  });

  test('게임이 연결되기 전에 온 결제는 연결될 때 지급한다', () async {
    final b = BillingService(
      complete: (p) async => completed.add(p.purchaseID!),
      consume: (p) async => consumed.add(p.purchaseID!),
    );
    await b.handlePurchases([buy(pack.id, 'o1', PurchaseStatus.restored)]);
    expect(consumed, isEmpty);
    b.onGems = gems.add;
    await pumpEventQueue();
    expect(gems, [pack]);
    expect(consumed, ['o1']);
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 환불된 결제 되돌리기 (D-066).
/// - 지급할 때 purchases/{주문번호} 에 uid · 상품 · 준 다이아를 남긴다.
/// - tool/refunds.py (매시간)가 Play 환불 목록과 맞춰 revocations/{uid}/items/{주문번호} 를 만든다.
/// - 앱은 접속할 때 그것을 읽어 되돌리고 지운다.
class PurchaseGuard {
  PurchaseGuard._();
  static final instance = PurchaseGuard._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<void> record(
    String uid,
    String orderId,
    String product,
    int gems,
  ) async {
    if (orderId.isEmpty || orderId.length > 200 || orderId.contains('/'))
      return;
    try {
      await _db.collection('purchases').doc(orderId).set({
        'uid': uid,
        'product': product,
        'gems': gems,
        'at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('purchase record failed: $e');
    }
  }

  /// 되돌릴 결제들 (주문번호, 상품, 준 다이아).
  Future<List<(String, String, int)>> pending(String uid) async {
    try {
      final q = await _db
          .collection('revocations')
          .doc(uid)
          .collection('items')
          .limit(50)
          .get();
      return [
        for (final d in q.docs)
          (
            d.id,
            d.data()['product'] as String? ?? '',
            (d.data()['gems'] as num?)?.toInt() ?? 0,
          ),
      ];
    } catch (e) {
      debugPrint('revocations read failed: $e');
      return const [];
    }
  }

  Future<void> done(String uid, Iterable<String> ids) async {
    final b = _db.batch();
    final col = _db.collection('revocations').doc(uid).collection('items');
    for (final id in ids) {
      b.delete(col.doc(id));
    }
    try {
      await b.commit();
    } catch (e) {
      debugPrint('revocations delete failed: $e');
    }
  }
}

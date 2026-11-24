import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'crash_service.dart';

/// 게임 안 '문제 알리기': 사용자가 쓴 글 + 진단(앱 버전 · 언어 · 레벨 · 구역 · 로그인 상태)을
/// Firestore feedback/ 에 남긴다 (규칙: 쓰기만, 읽기는 운영 도구만). 같은 내용을 Crashlytics 기록으로도.
/// 연결이 안 되면 기기에 모아 두었다가 다음에 보낸다 (CrashService.issue).
class FeedbackService {
  FeedbackService._();

  static const int maxText = 1000;

  /// 보냈으면 true, 기기에 모아 두었으면 false (다음 연결 때 전송).
  static Future<bool> send(String text, Map<String, String> diag) async {
    final t = text.trim();
    final d = diag.entries.map((e) => '${e.key}=${e.value}').join(' | ');
    final short = t.length > maxText ? t.substring(0, maxText) : t;
    final user = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('feedback')
            .add({
              'from': user.uid,
              'text': short,
              'diag': d.length > 2000 ? d.substring(0, 2000) : d,
              'at': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 10));
        await CrashService.issue('user_report', {
          'text': short.length > 200 ? short.substring(0, 200) : short,
          ...diag,
        });
        return true;
      } catch (e) {
        debugPrint('feedback failed: $e');
      }
    }
    await CrashService.issue('user_report', {'text': short, ...diag});
    return false;
  }
}

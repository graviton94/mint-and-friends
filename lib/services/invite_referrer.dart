import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Play 설치 추천인 (D-045): 초대 링크(`…&referrer=code%3DABCD1234`)로 설치하면
/// 첫 실행 때 Google Play 가 `code=ABCD1234` 를 넘겨 준다. 한 번만 읽어 두고,
/// 로그인 · 친구 기능이 준비되면 [SocialService.applyInvite] 로 쓴 뒤 지운다.
class InviteReferrer {
  static const _kChecked = 'referrer_checked';
  static const _kPending = 'referrer_code';
  static const _ch = MethodChannel('mint/referrer');

  /// 설치 추천인을 (처음 한 번) 읽어 저장해 둔다. 실패해도 조용히.
  static Future<void> capture(SharedPreferences prefs) async {
    if (prefs.getBool(_kChecked) ?? false) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final r = await _ch
          .invokeMethod<String>('get')
          .timeout(const Duration(seconds: 8));
      final code = parse(r);
      if (code != null) await prefs.setString(_kPending, code);
      await prefs.setBool(_kChecked, true);
    } catch (e) {
      debugPrint('install referrer: $e'); // 다음 실행 때 다시
    }
  }

  /// 'code=ABCD1234&utm_source=…' 에서 코드만.
  static String? parse(String? referrer) {
    if (referrer == null || referrer.isEmpty) return null;
    final q = Uri.splitQueryString(
      referrer.contains('%3D') ? Uri.decodeComponent(referrer) : referrer,
    );
    final c = q['code']?.trim().toUpperCase();
    return c == null || c.isEmpty ? null : c;
  }

  static String? pending(SharedPreferences prefs) => prefs.getString(_kPending);
  static Future<void> clear(SharedPreferences prefs) => prefs.remove(_kPending);
}

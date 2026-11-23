import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 게스트 로그아웃은 진행을 지우지 않는다: 로그인 화면으로만 가고, 다시 게스트로 시작하면 이어서.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('게스트 로그아웃 → 로그인 화면, 다시 게스트로 시작하면 같은 게스트', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AuthService();
    await a.init();
    await a.signInGuest();
    expect(a.signedIn, isTrue);
    await a.parkGuest();
    expect(a.signedIn, isFalse);
    // 앱을 껐다 켜도 로그인 화면 (게스트 기록은 남아 있음)
    final b = AuthService();
    await b.init();
    expect(b.signedIn, isFalse);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool('local_guest'), isTrue);
    await b.signInGuest();
    expect(b.signedIn, isTrue);
  });
}

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';

import 'app_config.dart';

enum LoginProvider { guest, google, kakao }

class AuthException implements Exception {
  final String code; // 'cancelled' | 'already_linked' | 'failed' | 'timeout'
  /// 어느 단계에서 무엇이 실패했는지 (화면에 작게 보여 준다: 예 "kakao token KOE101").
  final String detail;
  AuthException(this.code, [this.detail = '']);
  @override
  String toString() => 'AuthException($code $detail)';
}

/// 로그인 담당.
///
/// - 게스트: Firebase 익명 로그인 (Firebase 설정이 없으면 기기 전용 게스트).
/// - Google: Google ID 토큰 → Firebase. 게스트 상태면 같은 계정(uid)에 연결해 진행도가 그대로 이어진다.
/// - 카카오: 카카오 액세스 토큰 → Cloud Function(login)이 검증 후 커스텀 토큰 발급 → Firebase.
///   익명 계정에 커스텀 토큰을 직접 연결할 수 없어서, 로그인 후 CloudSave 가 기기 데이터를 옮긴다.
class AuthService extends ChangeNotifier {
  static const _localGuestKey = 'local_guest';
  static const _parkedKey = 'guest_parked';

  /// 게스트가 로그아웃한 상태: 로그인 화면으로 돌아가지만 게스트 계정 · 진행은 기기에 그대로 둔다.
  /// 다시 '게스트로 시작'하면 이어서, 구글로 로그인하면 그 계정에 연결된다.
  bool _parked = false;

  bool ready = false;
  bool busy = false;
  User? user;
  bool _localGuest = false;
  StreamSubscription<User?>? _sub;

  bool get firebaseEnabled => AppConfig.firebaseEnabled;
  bool get googleEnabled => AppConfig.googleEnabled;
  bool get kakaoEnabled => AppConfig.kakaoEnabled;

  /// 로그인 화면을 건너뛸 수 있는 상태인지.
  bool get signedIn => !_parked && (user != null || _localGuest);
  String? get uid => user?.uid;

  LoginProvider get provider {
    final u = user;
    if (u == null) return LoginProvider.guest;
    if (u.uid.startsWith('kakao:')) return LoginProvider.kakao;
    if (u.providerData.any((p) => p.providerId == 'google.com'))
      return LoginProvider.google;
    return LoginProvider.guest;
  }

  bool get isGuest => provider == LoginProvider.guest;

  /// 초기화 중 실패한 단계 (진단 화면에 보인다).
  final List<String> initErrors = [];

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _localGuest = prefs.getBool(_localGuestKey) ?? false;
    _parked = prefs.getBool(_parkedKey) ?? false;
    if (firebaseEnabled) {
      // 단계마다 따로: 하나가 실패해도 나머지(특히 게스트)는 살린다.
      try {
        // 안드로이드는 앱 리소스(google_app_id 등)로 기본 앱을 먼저 만들어 둔다 (Analytics 용).
        // 그 기본 앱이 있으면 그대로 쓴다: 옵션이 조금이라도 다르면 'duplicate-app' 으로 실패해
        // 로그인이 모두 막혔다 (1.0.9).
        try {
          await Firebase.initializeApp(options: AppConfig.firebaseOptions);
        } on FirebaseException catch (e) {
          if (e.code != 'duplicate-app') rethrow;
          await Firebase.initializeApp();
        }
        user = FirebaseAuth.instance.currentUser;
        _sub = FirebaseAuth.instance.authStateChanges().listen((u) {
          user = u;
          notifyListeners();
        });
      } catch (e) {
        initErrors.add('firebase ${_reason(e)}');
        debugPrint('Firebase init failed: $e');
      }
      if (googleEnabled) {
        try {
          await GoogleSignIn.instance.initialize(
            serverClientId: AppConfig.googleServerClientId,
          );
        } catch (e) {
          initErrors.add('google init ${_reason(e)}');
        }
      }
      if (kakaoEnabled) {
        try {
          await kakao.KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);
        } catch (e) {
          initErrors.add('kakao init ${_reason(e)}');
        }
      }
    }
    ready = true;
    notifyListeners();
  }

  /// 로그인이 안 될 때 원인을 찾는 정보 (비밀값 없음: 공개 키 일부 · 서명 해시 · 패키지).
  /// 카카오 '키 해시'와 Firebase 지문은 이 기기에서 실제로 돌고 있는 앱의 서명이다.
  Future<String> diagnostics() async {
    String mask(String v) => v.length <= 8
        ? (v.isEmpty ? '-' : v)
        : '${v.substring(0, 4)}…${v.substring(v.length - 4)}';
    final lines = <String>[
      'fb ${firebaseEnabled ? AppConfig.firebaseProjectId : 'off'} app ${mask(AppConfig.firebaseAppId)} ready ${Firebase.apps.isNotEmpty}',
      'google ${googleEnabled ? mask(AppConfig.googleServerClientId) : 'off'}',
      'kakao ${kakaoEnabled ? mask(AppConfig.kakaoNativeAppKey) : 'off'}',
    ];
    if (kakaoEnabled) {
      try {
        final info = kakao.KakaoSdk.platformInfo;
        lines.add('pkg ${info.packageName ?? '-'}');
        lines.add('keyhash ${info.origin}');
      } catch (e) {
        lines.add('keyhash ? ${e.runtimeType}');
      }
    }
    if (initErrors.isNotEmpty) lines.add('init: ${initErrors.join(' / ')}');
    if (lastGuestError != null) lines.add('anon: $lastGuestError');
    return lines.join('\n');
  }

  /// 마지막 익명 로그인 실패 이유 (기기 전용 게스트로 대신 시작했을 때).
  String? lastGuestError;

  Future<T> _run<T>(Future<T> Function() body) async {
    busy = true;
    notifyListeners();
    try {
      final r = await body();
      // 로그인 · 로그아웃이 끝나면 게스트 대기 상태는 풀린다
      await _setParked(false);
      return r;
    } on AuthException {
      rethrow;
    } on TimeoutException {
      throw AuthException('timeout');
    } catch (e) {
      debugPrint('auth error: $e');
      throw AuthException('failed', _reason(e));
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// 실패 사유를 짧게: 어느 쪽이 거절했고 코드가 무엇인지 (myhomes 와 같은 방식).
  static String _reason(Object e) => switch (e) {
    FirebaseFunctionsException() => 'server ${e.code}',
    FirebaseAuthException() => 'auth ${e.code}',
    kakao.KakaoAuthException() => 'kakao ${e.error.name}',
    kakao.KakaoApiException() => 'kakao api ${e.code.name}',
    kakao.KakaoClientException() => 'kakao ${e.reason.name}',
    PlatformException() =>
      '${e.code}${e.message == null ? '' : ': ${e.message}'}',
    _ => e.runtimeType.toString(),
  };

  /// 외부 앱 · 브라우저에 다녀오는 단계: 돌아왔는데 결과가 오지 않으면 무한 대기하지 않는다.
  /// 앱이 다시 앞으로 온 뒤 [grace] 안에 결과가 없으면 'cancelled'.
  Future<T> _awayStep<T>(
    Future<T> Function() step, {
    Duration grace = const Duration(seconds: 6),
  }) {
    final done = Completer<T>();
    var wentAway = false;
    Timer? graceTimer;
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(
      onHide: () => wentAway = true,
      onResume: () {
        if (!wentAway || done.isCompleted) return;
        graceTimer?.cancel();
        graceTimer = Timer(grace, () {
          if (!done.isCompleted) done.completeError(AuthException('cancelled'));
        });
      },
    );
    step().then(
      (v) {
        if (!done.isCompleted) done.complete(v);
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
    );
    return done.future.timeout(const Duration(seconds: 90)).whenComplete(() {
      graceTimer?.cancel();
      listener.dispose();
    });
  }

  /// 게스트 시작은 실패하지 않는다: Firebase 익명 로그인이 안 되면 기기 전용 게스트로 바로 들어가고
  /// (진행은 기기에 저장), 나중에 설정에서 계정을 연결한다.
  Future<void> signInGuest() async {
    busy = true;
    notifyListeners();
    await _setParked(false);
    try {
      if (_localGuest) return;
      // Play 출시 전 보고서 · Test Lab 로봇은 기기 전용 게스트로: 계정 · 클라우드 저장을 만들지 않아
      // 테스터 숫자에 섞이지 않게 (D-101)
      if (Analytics.instance.isTestDevice) {
        _localGuest = true;
        return;
      }
      if (firebaseEnabled && Firebase.apps.isNotEmpty) {
        if (FirebaseAuth.instance.currentUser != null) return;
        try {
          await FirebaseAuth.instance.signInAnonymously().timeout(
            const Duration(seconds: 10),
          );
          lastGuestError = null;
          return;
        } catch (e) {
          lastGuestError = e is TimeoutException ? 'timeout' : _reason(e);
          debugPrint('anonymous sign-in failed, local guest: $e');
        }
      }
      _localGuest = true;
      try {
        (await SharedPreferences.getInstance()).setBool(_localGuestKey, true);
      } catch (_) {}
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Google 로그인. 익명 계정이면 연결(link)해서 uid 를 유지한다.
  Future<void> signInGoogle() => _run(() async {
    if (!googleEnabled) throw AuthException('failed');
    final GoogleSignInAccount account;
    try {
      account = await _awayStep(GoogleSignIn.instance.authenticate);
    } on GoogleSignInException catch (e) {
      throw AuthException(
        e.code == GoogleSignInExceptionCode.canceled ? 'cancelled' : 'failed',
        'google ${e.code.name}${e.description == null ? '' : ': ${e.description}'}',
      );
    }
    final idToken = account.authentication.idToken;
    final cred = GoogleAuthProvider.credential(idToken: idToken);
    final current = FirebaseAuth.instance.currentUser;
    if (current != null && current.isAnonymous) {
      try {
        await current.linkWithCredential(cred);
        await current.reload();
        user = FirebaseAuth.instance.currentUser;
        return;
      } on FirebaseAuthException catch (e) {
        // 이미 다른 진행도가 있는 Google 계정 → 그 계정으로 전환 (CloudSave 가 어느 쪽을 쓸지 묻는다)
        if (e.code != 'credential-already-in-use') rethrow;
        await FirebaseAuth.instance.signInWithCredential(e.credential ?? cred);
        return;
      }
    }
    await FirebaseAuth.instance.signInWithCredential(cred);
  });

  /// 카카오 로그인 → Cloud Function 으로 Firebase 커스텀 토큰을 받아 로그인.
  Future<void> signInKakao() => _run(() async {
    if (!kakaoEnabled) throw AuthException('failed');
    final accessToken = await _kakaoToken();
    final fn = FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion)
        .httpsCallable(
          'login',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
        );
    final res = await fn.call<Map<String, dynamic>>({
      'provider': 'kakao',
      'token': accessToken,
    });
    final customToken = res.data['token'];
    if (customToken is! String)
      throw AuthException('failed', 'no custom token');
    await FirebaseAuth.instance
        .signInWithCustomToken(customToken)
        .timeout(const Duration(seconds: 20));
  });

  /// 카카오톡 앱 로그인 → 안 되면 카카오계정(웹) 로그인. 사용자가 물러나면 'cancelled'.
  Future<String> _kakaoToken() async {
    try {
      final api = kakao.UserApi.instance;
      if (await kakao.isKakaoTalkInstalled()) {
        try {
          return (await _awayStep(api.loginWithKakaoTalk)).accessToken;
        } catch (e) {
          // 카카오톡 안에서 취소: 멈춘다. 그 밖(카카오톡에 계정 미연결 등): 웹 로그인으로.
          if (e is PlatformException && e.code == 'CANCELED') {
            throw AuthException('cancelled');
          }
          if (e is kakao.KakaoClientException &&
              e.reason == kakao.ClientErrorCause.cancelled) {
            throw AuthException('cancelled');
          }
        }
      }
      return (await _awayStep(api.loginWithKakaoAccount)).accessToken;
    } on kakao.KakaoClientException catch (e) {
      if (e.reason == kakao.ClientErrorCause.cancelled) {
        throw AuthException('cancelled');
      }
      rethrow;
    } on kakao.KakaoAuthException catch (e) {
      if (e.error == kakao.AuthErrorCause.accessDenied) {
        throw AuthException('cancelled');
      }
      rethrow;
    }
  }

  Future<void> _setParked(bool v) async {
    _parked = v;
    try {
      final p = await SharedPreferences.getInstance();
      v ? await p.setBool(_parkedKey, true) : await p.remove(_parkedKey);
    } catch (_) {}
  }

  /// 게스트 로그아웃: 계정 · 기기 진행은 지우지 않고 로그인 화면으로만 돌아간다.
  Future<void> parkGuest() async {
    await _setParked(true);
    notifyListeners();
  }

  Future<void> signOut() => _run(() async {
    if (firebaseEnabled && Firebase.apps.isNotEmpty) {
      if (provider == LoginProvider.google) {
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
      }
      if (provider == LoginProvider.kakao) {
        try {
          await kakao.UserApi.instance.logout();
        } catch (_) {}
      }
      await FirebaseAuth.instance.signOut();
    }
    _localGuest = false;
    (await SharedPreferences.getInstance()).remove(_localGuestKey);
    user = null;
  });

  /// 계정과 클라우드 데이터 삭제 (Play 정책: 앱 안에서 계정 삭제 제공 필수).
  Future<void> deleteAccount() => _run(() async {
    if (firebaseEnabled && user != null) {
      final fn = FirebaseFunctions.instanceFor(
        region: AppConfig.functionsRegion,
      ).httpsCallable('deleteAccount');
      await fn.call<void>();
      if (provider == LoginProvider.kakao) {
        try {
          await kakao.UserApi.instance.unlink();
        } catch (_) {}
      }
      if (provider == LoginProvider.google) {
        try {
          await GoogleSignIn.instance.disconnect();
        } catch (_) {}
      }
      await FirebaseAuth.instance.signOut();
    }
    _localGuest = false;
    (await SharedPreferences.getInstance()).remove(_localGuestKey);
    user = null;
  });

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

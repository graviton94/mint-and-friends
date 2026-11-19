import 'package:firebase_core/firebase_core.dart';

/// 빌드 시 주입되는 외부 서비스 설정.
///
/// CI   :  GOOGLE_SERVICES_JSON 시크릿(google-services.json 통째)에서 FB_* · GOOGLE_WEB_CLIENT_ID 를 뽑고,
///          KAKAO_NATIVE_APP_KEY 시크릿을 더해 --dart-define 으로 넘긴다 (app.yml / aab.yml).
/// 로컬:  flutter run --dart-define-from-file=config/app_config.json (config/app_config.example.json 참고)
/// 값이 비어 있으면 해당 기능은 꺼진다 (Firebase 없으면 게스트·기기 저장만 동작).
class AppConfig {
  static const firebaseApiKey = String.fromEnvironment('FB_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FB_APP_ID');
  static const firebaseProjectId = String.fromEnvironment('FB_PROJECT_ID');
  static const firebaseSenderId = String.fromEnvironment('FB_SENDER_ID');
  static const firebaseStorageBucket = String.fromEnvironment(
    'FB_STORAGE_BUCKET',
  );

  /// Firebase 콘솔 > Authentication > Google 의 "웹 클라이언트 ID" (Android Google 로그인에 필요).
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  /// 카카오 디벨로퍼스 > 앱 키 > 네이티브 앱 키.
  static const kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
  );

  /// Cloud Functions 리전 (functions/ 와 같아야 함).
  static const functionsRegion = String.fromEnvironment(
    'FUNCTIONS_REGION',
    defaultValue: 'us-central1',
  );

  static bool get firebaseEnabled =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;
  static bool get googleEnabled =>
      firebaseEnabled && googleServerClientId.isNotEmpty;
  static bool get kakaoEnabled =>
      firebaseEnabled && kakaoNativeAppKey.isNotEmpty;

  static FirebaseOptions get firebaseOptions => const FirebaseOptions(
    apiKey: firebaseApiKey,
    appId: firebaseAppId,
    projectId: firebaseProjectId,
    messagingSenderId: firebaseSenderId,
    storageBucket: firebaseStorageBucket,
  );
}

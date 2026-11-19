# 설정과 배포

## 1. 서명 키 (한 번만)

GitHub Secrets 두 개로 서명합니다.

| Secret | 용도 |
|---|---|
| `ANDROID_UPLOAD_PASSPHRASE` | `android/keystores/upload.jks.gpg` 를 풀고, 키스토어/키 비밀번호로 사용 → Play 업로드용 AAB |
| `SIDELOAD_PASSPHRASE` | `android/keystores/sideload.jks.gpg` 를 풀고, 키스토어/키 비밀번호로 사용 → 직접 배포용 APK |

만들기 (JDK 의 keytool, gpg 필요):
```bash
ANDROID_UPLOAD_PASSPHRASE='…' SIDELOAD_PASSPHRASE='…' tool/make_keystores.sh
git add android/keystores/*.jks.gpg && git commit -m "서명 키 추가"
```
- 원본 `.jks` 는 `~/mint-and-friends-keys/` 에 남습니다. 안전한 곳에 백업하세요. 저장소에는 `.gpg` 만 올라갑니다.
- 스크립트가 출력하는 **SHA-1 / SHA-256** 은 2, 3단계에서 씁니다.
- 이미 쓰는 키스토어가 있으면 `~/mint-and-friends-keys/upload.jks` 자리에 두고 실행하세요. 새로 만들지 않고 암호화만 합니다. 별칭은 `upload` / `sideload` 여야 합니다. 다르면 Secrets 에 `ANDROID_UPLOAD_ALIAS` / `SIDELOAD_ALIAS` 를 추가하고 workflow 의 env 에 넘겨주세요.

## 2. Firebase (Blaze)

1. Firebase 콘솔에서 프로젝트를 만들고 Blaze 요금제로 전환합니다.
2. Android 앱을 추가합니다. 패키지는 `com.graviton94.mintandfriends`, SHA-1/SHA-256 은 업로드 키와 사이드로드 키 모두 등록합니다. Play App Signing 을 쓰면 Play Console 의 **앱 서명 키** SHA 도 추가합니다.
3. Authentication → 로그인 방법에서 **익명**, **Google** 을 켭니다. 카카오는 커스텀 토큰이라 따로 켤 필요가 없습니다.
4. Firestore 데이터베이스를 만듭니다 (위치: `asia-northeast3` 서울).
5. 규칙과 함수 배포:
   ```bash
   npm i -g firebase-tools && firebase login
   # .firebaserc 의 YOUR_FIREBASE_PROJECT_ID 를 실제 ID 로 바꾼 뒤
   (cd functions && npm install)
   firebase deploy --only firestore:rules,functions
   ```
   함수가 서비스 계정으로 커스텀 토큰을 만들 수 있게 IAM 에서 *Cloud Functions 런타임 서비스 계정*에 **서비스 계정 토큰 생성자**(`roles/iam.serviceAccountTokenCreator`) 역할을 줍니다.

## 3. 카카오 디벨로퍼스

1. 애플리케이션을 추가하고 **네이티브 앱 키**를 확인합니다.
2. 플랫폼 → Android: 패키지명 `com.graviton94.mintandfriends`, 키 해시는 업로드·사이드로드·Play 앱 서명 키 3개를 등록합니다.
   키 해시 = SHA-1 을 base64 로 바꾼 값입니다:
   `echo <SHA1 콜론포함> | tr -d ':' | xxd -r -p | base64`
3. 카카오 로그인을 활성화하고, 동의항목에서 닉네임(필수) 정도만 받습니다.

## 4. 앱 설정 (`APP_CONFIG_JSON`)

`config/app_config.example.json` 을 채워 **GitHub Secret `APP_CONFIG_JSON`** 에 JSON 통째로 넣습니다.
로컬 실행은 같은 내용을 `config/app_config.json` 에 두고 `flutter run --dart-define-from-file=config/app_config.json`.

| 키 | 위치 |
|---|---|
| `FIREBASE_API_KEY` / `FIREBASE_APP_ID` / `FIREBASE_PROJECT_ID` / `FIREBASE_MESSAGING_SENDER_ID` / `FIREBASE_STORAGE_BUCKET` | Firebase 콘솔 → 프로젝트 설정 → 내 앱 (Android) 의 google-services.json 값 |
| `GOOGLE_SERVER_CLIENT_ID` | Authentication → Google → 웹 SDK 구성의 **웹 클라이언트 ID** |
| `KAKAO_NATIVE_APP_KEY` | 카카오 네이티브 앱 키 |

값이 비어 있으면 해당 로그인 버튼이 숨겨지고, Firebase 가 없으면 게스트(기기 저장)로만 동작합니다.

## 5. AdMob, 구독

- `android/app/src/main/AndroidManifest.xml` 의 AdMob `APPLICATION_ID`, `lib/services/ad_ids.dart` 의 `_prod*` 3개를 교체합니다.
- Play Console → 수익 창출 → 구독: 상품 ID `remove_ads_1m`, 기본 요금제 1개월 자동 갱신. 첫 AAB 를 비공개 테스트 트랙에 올린 뒤 만들 수 있습니다.

## 6. 빌드와 배포

| 동작 | 결과 |
|---|---|
| 아무 브랜치 push | 분석·테스트 → `mint-and-friends-<버전>-sideload.apk`, `-upload.aab` (Actions → Artifacts) |
| 태그 `v1.0.0` push | 위와 같음 + GitHub Release 에 APK·AAB 첨부 |

키 Secrets 가 없으면 파일 이름이 `-debugsigned` 로 나옵니다 (설치 테스트용, Play 업로드 불가).
`versionCode` = Actions 실행 번호 + 100, `versionName` = 태그(없으면 pubspec).

## 데이터 구조

- 기기: SharedPreferences `save_v3` (JSON). Android 자동 백업(Google 백업) 대상은 이 파일만입니다 (`res/xml/*backup*`).
- 클라우드: Firestore `users/{uid}` = `{ data: <저장 JSON 문자열>, level, area, progress, updatedAt, schema }`
  - 게스트 = Firebase 익명 계정. Google 연결 시 같은 uid 로 이어집니다.
  - 카카오 = `kakao:<회원번호>` uid. 게스트에서 넘어오면 기기 데이터를 옮기고, 양쪽에 진행도가 있으면 사용자에게 고르게 합니다.
- 계정 삭제: 설정 → 계정 및 데이터 삭제 → Cloud Function `deleteAccount` (Play 정책 필수 항목).

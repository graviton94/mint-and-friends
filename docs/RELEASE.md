# 설정과 배포

키 생성, 빌드, 함수 배포가 모두 GitHub Actions 안에서 일어납니다. 로컬에는 키도 암호도 두지 않습니다.

## 0. GitHub Secrets

| Secret | 용도 | 필수 |
|---|---|---|
| `SIDELOAD_PASSPHRASE` | 시험용 APK 키(`android/keystore/sideload.jks.gpg`)를 잠그고 푸는 암호. 키스토어/키 비밀번호로도 쓴다 | 예 |
| `ANDROID_UPLOAD_PASSPHRASE` | Play 업로드 키(`android/keystore/upload.jks.gpg`) 암호 | 스토어 배포 시 |
| `GOOGLE_SERVICES_JSON` | Firebase 콘솔에서 받은 `google-services.json` 통째. 빌드 때 `FB_*` · `GOOGLE_WEB_CLIENT_ID` 를 여기서 뽑는다 (`tool/ci_defines.py`) | 로그인·클라우드 저장 쓸 때 |
| `KAKAO_NATIVE_APP_KEY` | 카카오 네이티브 앱 키 (앱 dart-define + 매니페스트 `kakao<키>` 스킴) | 카카오 로그인 쓸 때 |
| `KAKAO_APP_ID` | 카카오 앱의 숫자 ID. 함수가 다른 카카오 앱의 토큰을 거부하는 데 쓴다 | 권장 |
| `FIREBASE_SERVICE_ACCOUNT` | 배포용 서비스 계정 JSON 키 (functions.yml). 프로젝트 ID 도 여기서 읽는다 | 함수 배포 시 |

- 두 패스프레이즈는 16자 이상, 서로 달라야 합니다.
- Actions → **Secrets check** 를 실행하면 값은 찍지 않고 상태만 요약합니다 (패키지 등록 여부, SHA 등록 여부, 프로젝트 일치 등).

## 1. 서명 키 (키마다 한 번)

Actions → **Android signing key (one time)** 를 `sideload`, `upload` 로 한 번씩 실행합니다.
키를 만들어 암호화한 `.jks.gpg` 를 커밋하고, 실행 요약에 **SHA-1 / SHA-256** 을 찍습니다. 이 값은 2, 3단계에서 씁니다.
이미 있는 키는 `replace` 를 켜야만 바뀝니다 (바꾸면 시험 폰은 지우고 다시 설치해야 함).

## 2. Firebase (Blaze)

1. 프로젝트를 만들고 Blaze 요금제로 전환합니다.
2. Android 앱 추가: 패키지 `io.github.graviton94.mintandfriends`. SHA-1/SHA-256 은 sideload, upload, 그리고 Play Console 의 **앱 서명 키** 3개를 등록합니다. 등록 후 `google-services.json` 을 다시 받아 `GOOGLE_SERVICES_JSON` 에 넣습니다.
3. Authentication → 로그인 방법: **익명**, **Google** 을 켭니다. 카카오는 커스텀 토큰이라 켤 것이 없습니다.
4. Firestore 데이터베이스를 만듭니다.
5. 배포용 서비스 계정 키를 만들어 `FIREBASE_SERVICE_ACCOUNT` 에 넣습니다. 필요한 역할: Firebase Admin, Cloud Functions Admin, Service Account User, Service Usage Admin, Firebase Rules Admin.
6. Actions → **Functions** 실행 (또는 `functions/` 변경 push 시 자동). `login`, `deleteAccount` (Python, us-central1) 와 Firestore 규칙이 배포됩니다.
   마지막 단계가 경고하면, 함수 실행 계정(`<번호>-compute@developer.gserviceaccount.com`)에 **Service Account Token Creator** 역할을 줍니다. 없으면 카카오 로그인이 실패합니다.

## 3. 카카오 디벨로퍼스

1. 앱 추가 → **네이티브 앱 키** → `KAKAO_NATIVE_APP_KEY`, **앱 ID**(숫자) → `KAKAO_APP_ID`.
2. 플랫폼 → Android: 패키지 `io.github.graviton94.mintandfriends`, 키 해시 3개(sideload, upload, Play 앱 서명 키).
   키 해시 = SHA-1 을 base64 로 바꾼 값: `echo <SHA1 콜론포함> | tr -d ':' | xxd -r -p | base64`
3. 카카오 로그인 활성화, 동의항목은 닉네임 정도만.

## 4. 빌드

| 워크플로 | 언제 | 결과 |
|---|---|---|
| **App** (`app.yml`) | 앱 코드 push 마다 | 분석 · 테스트 → sideload 키로 서명한 arm64 APK → Releases `android-latest` |
| **Store AAB** (`aab.yml`) | 직접 실행 ("릴리즈하자" 이후) | upload 키로 서명한 AAB, versionCode = 1000 + 실행 번호 → 초안 Release |
| **Functions** (`functions.yml`) | `functions/` · 규칙 변경 push, 직접 실행 | 함수 · Firestore 규칙 배포 |
| **Launch smoke test** (`smoke.yml`) | 안드로이드 설정 · 플러그인 · 서비스 변경 push, 직접 실행 | 릴리스 빌드를 에뮬레이터에서 실행해 바로 꺼지는지 확인, 크래시 로그 |
| **Server logs** (`diag.yml`) | 직접 실행 | 로그인 · 계정 삭제 함수 로그, Firestore · 익명 로그인 상태 (로그인 문제 진단) |
| **Login button assets** | 직접 실행 | 카카오 · Google 공식 로그인 버튼 리소스를 `design/login/official/` 에 커밋 |

sideload 키가 아직 없으면 App 은 디버그 키로 서명하고 경고만 남깁니다.
로컬 실행: `config/app_config.example.json` 을 `config/app_config.json` 으로 복사해 채우고 `flutter run --dart-define-from-file=config/app_config.json`. 값이 비면 해당 로그인 버튼이 숨고, Firebase 가 없으면 게스트(기기 저장)로만 동작합니다.

### 새 버전을 테스터 · 사용자에게 올린 뒤
- 원격 설정 `latest_version_code` 를 올린 버전 코드로: Actions → **Remote Config** → `latest_version_code=1023`
  (Claude 가 관리한다. Play 가 새 버전을 늦게 알려 줘도 앱이 'Play 스토어에서 업데이트' 창을 띄운다, 1.0.6 부터)
- 같은 워크플로로 `order_quota_per_friend=5` 처럼 경제 값도 바꿀 수 있다 (tool/remote_config_set.py 가 아는 키만)

## 5. AdMob, 구독

- `AndroidManifest.xml` 의 AdMob `APPLICATION_ID`, `lib/services/ad_ids.dart` 의 `_prod*` 3개를 실제 값으로 교체합니다 (지금은 테스트 ID).
- Play Console → 수익 창출 → 구독: 상품 ID `garden_pass_1m`, 1개월 자동 갱신. 첫 AAB 를 비공개 테스트 트랙에 올린 뒤 만들 수 있습니다.

## 데이터 구조

- 기기: SharedPreferences `save_v3` (JSON). Android 자동 백업(Google 백업)은 이 파일만 (`res/xml/*backup*`).
- 클라우드: Firestore `users/{uid}` = `{ data: <저장 JSON 문자열>, level, area, progress, updatedAt, schema }`
  - 게스트 = Firebase 익명 계정. Google 연결 시 같은 uid 로 이어집니다.
  - 카카오 = `kakao:<회원번호>` uid (`login` 함수가 토큰 확인 후 커스텀 토큰 발급). 게스트에서 넘어오면 기기 데이터를 옮기고, 양쪽에 진행도가 있으면 사용자에게 고르게 합니다.
- 계정 삭제: 설정 → 계정 및 데이터 삭제 → `deleteAccount` 함수 (Play 정책 필수 항목).

## 친구 · 공지

- 데이터: `profiles/{uid}` 공개 프로필, `codes/{코드}` → uid (8자리, 만들기만), `users/{uid}/friends/{친구uid}`, `inbox/{uid}/items/*` 받은 선물 (`sendGift` 함수만 씀), `notices/{id}` 운영 공지 (읽기 전용). 규칙: `firestore.rules`.
- 배포: **Functions** 워크플로가 `sendGift` 와 규칙을 함께 배포합니다. 따로 할 일 없음.
- (선택) 선물 기록 자동 정리: Firestore → TTL 정책에서 컬렉션 그룹 `gifts`, `giftCounts` 의 `expireAt` 필드를 켭니다 (3일 뒤 삭제).
- 공지 올리기 (Firebase 콘솔 → 프로젝트 설정 → 서비스 계정 → 새 비공개 키):
  ```
  pip install firebase-admin
  python3 tool/post_notice.py --key sa.json --ko "점검 보상" --en "Maintenance gift" --ja "メンテナンスのお詫び" --coins 500 --energy 20 --days 7
  python3 tool/post_notice.py --key sa.json --list        # 목록,  --delete <id> 로 삭제
  ```
  앱은 시작 · 복귀 때(30분 간격) 진행 중인 공지를 쪽지함에 넣고, 같은 공지는 한 번만 받습니다. 키 파일은 커밋하지 마세요.

### 1.0.7 출시 때 한 번 더
찻잎 · 별가루 단계가 바뀌어 1.0.6 이 1.0.7 저장을 읽으면 값이 틀려 보인다. 출시 확인 뒤 `latest_version_code` 와 함께 `min_version_code` 도 1.0.7 의 버전 코드로 (Actions → Remote Config: `latest_version_code=NNNN min_version_code=NNNN`).

### 자동 출시 (2026-11-23부터)
Play Console 앱 권한을 받은 서비스 계정으로 CI 가 직접 올린다. Actions → Store AAB:
- `version` = 1.0.8, `track` = `alpha`(비공개 테스트) / `internal` / `production`, `rollout` = 정식 단계 비율(예 0.2), `min_version` = true 면 강제 업데이트까지.
- 빌드 → 트랙 업로드(출시 노트는 `patch.<version>` 4개 언어, Play 한도 500자에 맞춰 줄 단위로 자름) → 출시 → 원격 설정 `latest_version_code`(+ `min_version_code`).
- 권한 확인: Actions → Play check (트랙 · 리뷰 읽기만).
- 정식(production) 출시는 사장님 확인 뒤에만.

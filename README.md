# 블룸 가든 (가제)

머지 + 방치형 꽃 정원 게임. Flutter, Android 전용.

## 게임 루프
- 바구니가 자동으로 씨앗을 만든다 (탭하면 더 빨리 만든다)
- 같은 꽃 2개를 드래그해서 합치면 다음 단계로 올라간다 (15종 x 일반/황금/다이아 = 45단계)
- 보드 위의 꽃은 초당 코인을 만든다. 오프라인일 때도 쌓인다
- 코인으로 **강화**(생성 속도, 수익, 자동 합치기, 씨앗 품질, 오프라인 시간)와 **정원 복구**(영구 수익 보너스)를 산다

## 수익 구조
| 위치 | 종류 |
|---|---|
| 수익 2배 10분 (최대 60분 누적) | 보상형 |
| 코인 주머니 (4분 쿨다운) | 보상형 |
| 오프라인 보상 2배 | 보상형 |
| 정원 작업 완료 시 (3분 간격, 앱 시작 후 2분 유예) | 전면 |
| 하단 | 적응형 배너 |
| `remove_ads_1m` 구독 | 배너·전면 광고 제거, 보상형 보상은 광고 없이 즉시 지급 |

## 구조
```
lib/game/config.dart       밸런스 수치, 아이템, 강화, 정원 데이터 (튜닝은 여기서)
lib/game/game_state.dart   게임 규칙과 저장 (UI와 분리, 테스트 있음)
lib/services/              AdMob, Play Billing
lib/ui/                    화면
test/                      규칙 단위 테스트
tool/balance_sim_test.dart 밸런스 시뮬레이터 (flutter test tool/balance_sim_test.dart)
```

## 빌드
GitHub Actions(`.github/workflows/android.yml`)가 push 할 때마다 APK와 AAB를 빌드한다. 결과물은 Actions 실행 페이지의 Artifacts에서 받는다.
업로드 키 Secrets가 없으면 디버그 키로 서명된다. 이 빌드는 기기 설치 테스트만 가능하고 Play 업로드는 안 된다.

로컬 빌드: `flutter build appbundle --release`

## 출시 전 체크리스트
1. **업로드 키 생성**
   `keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
   GitHub Secrets 등록: `ANDROID_KEYSTORE_BASE64` (`base64 -w0 upload.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
2. **AdMob**: 앱 생성 후 다음 두 곳을 교체한다.
   - `android/app/src/main/AndroidManifest.xml`의 `APPLICATION_ID`
   - `lib/services/ad_ids.dart`의 `_prod*` 3개
   디버그 빌드는 항상 테스트 광고 ID를 쓴다.
3. **Play Console 구독**: 상품 ID `remove_ads_1m`, 기본 요금제 1개월 자동 갱신
4. 구독 상품은 앱이 비공개 테스트 트랙에 한 번 업로드된 뒤에 생성할 수 있다. 그래서 첫 AAB를 먼저 올린다.
5. 개인정보처리방침 URL과 데이터 보안 양식 작성 (AdMob이 광고 ID를 수집함)
6. `applicationId` = `com.graviton94.bloomgarden` (출시 후 변경 불가)

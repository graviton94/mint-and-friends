# iOS 이전 계획 (안드로이드 시장성 검증 뒤)

결정: 안드로이드 출시로 KPI(D1 40 · D7 15 · D30 6 · 결제 전환 2%)를 확인한 뒤 iOS. 애플 개발자 연 $99 는 그때부터.
규모: 중간 (약 1~2주). 게임 로직 · 화면 · 그림 · 소리 · 저장 · 분석 · 원격 설정은 그대로.

## 이미 해 둔 것 (11-28)
- 안드로이드 전용 코드는 모두 플랫폼 확인으로 감싸 있다 (iOS 에서 죽지 않고 건너뜀):
  테스트 기기 감지(mint/device) · 설치 경로 초대 코드(mint/referrer) · 앱 내 업데이트(mint/update) · 결제 소비(consumePurchase) · 알림(NotifyService._supported).
- 결제 상품 목록 · 4개 언어 설명은 docs/store/store.json 하나에 있다 (App Store Connect 등록 도구가 그대로 읽으면 된다).

## 그때 할 일
1. `flutter create --platforms ios .` → Bundle ID, Firebase iOS 앱 추가(GoogleService-Info.plist는 CI 비밀값으로).
2. **Sign in with Apple** (심사 필수: 구글 · 카카오 로그인을 주면 애플 로그인도 줘야 한다) → Firebase Auth 공급자 + 게스트/계정 연결 흐름에 추가.
3. 결제: App Store Connect 상품 12개(소모형 11 + 구독 1) 등록 도구(play_api.py 처럼), StoreKit 2 테스트, 구독 복원.
   환불 회수: App Store Server Notifications v2 → Cloud Functions → revocations/{uid} (지금 Play voidedpurchases 와 같은 자리).
4. 광고: ATT(추적 허용) 팝업 · Info.plist SKAdNetworkItems · AdMob iOS 앱 ID.
5. 카카오 · 구글 로그인 iOS 키 · URL 스킴.
6. 알림: flutter_local_notifications iOS 설정(DarwinInitializationSettings) 후 _supported 를 iOS 까지.
7. 계절 아이콘(tool/launcher_icon.py)에 iOS AppIcon 세트 추가.
8. CI: GitHub macOS 러너 + fastlane(또는 xcodebuild) → TestFlight. Mac 없이 가능.
9. 스토어: iPhone 6.7"/6.5" 스크린샷, 개인정보 라벨(데이터 보안 답안 재사용), 연령 등급, 심사 메모(테스트 계정).

## 사용자가 할 일 (그때)
애플 개발자 가입 · App Store Connect API 키(.p8) · 테스트 아이폰 또는 TestFlight 테스터.

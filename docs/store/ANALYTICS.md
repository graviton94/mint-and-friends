# 분석 이벤트 · 콘솔 연결 (D-044)

게임은 Firebase Analytics 로 이벤트를 보낸다. 새로 깔 것은 없고, 아래 **콘솔 연결 3개**만 한 번 해 두면
결제 · 광고 매출까지 Firebase 한 곳에서 본다.

## 1. 콘솔 연결 (사용자, 한 번)

| 순서 | 어디서 | 무엇을 | 얻는 것 |
|---|---|---|---|
| 1 | Firebase 콘솔 → 프로젝트 설정 → **통합 → Google Play → 연결** | Play Console 계정 · 이 앱 선택 | 인앱 결제 · 구독 매출이 `in_app_purchase` 로 자동 집계 (금액 · 통화 포함) |
| 2 | AdMob → 앱 → Mint & Friends → **앱 설정 → Firebase 연결** (또는 Firebase → 통합 → AdMob) | 같은 Firebase 프로젝트 · Android 앱 | 광고 노출 · 광고 매출이 `ad_impression` 으로 집계 |
| 3 | Firebase 콘솔 → Analytics → **맞춤 정의 → 맞춤 측정기준 만들기** (이벤트 범위) | `what` · `product` · `kind` · `from` · `code` · `level` | 아래 이벤트를 "어디에 · 어떤 상품 · 어떤 광고"별로 나눠 보기 |

선택: 주요 이벤트(전환)로 표시 → `iap_purchase` · `area_complete` · `tutorial_complete`.
테스트 기기에서 바로 보기(DebugView): `adb shell setprop debug.firebase.analytics.app io.github.graviton94.mintandfriends`

## 2. 보내는 이벤트

| 이벤트 | 언제 | 값 |
|---|---|---|
| `first_open` · `user_engagement` (자동) | 처음 실행 · 사용 시간 | D1 · D7 리텐션 |
| `tutorial_begin` · `tutorial_complete` | 튜토리얼 | 완료율 |
| `level_up` | 플레이어 레벨업 | level (사용자 속성 `player_level`) |
| `area_complete` | 구역 완성 | area · level (사용자 속성 `area`) |
| `friend_joined` · `max_merge` | 친구 합류 · 최고 단계 합치기 | friend |
| `energy_empty` | 에너지 0 | level |
| `ad_reward` | 보상형 광고 보상 받음 | kind (energy · boost · coinBag · refresh · quota · gems · market …) · level |
| `ad_unavailable` | 광고를 보려 했는데 준비된 광고가 없음 | — (채움률) |
| **`shop_open`** | 상점 열기 | gems · level · starter(패키지 보임 1/0) |
| **`starter_view`** | 새싹 정원 패키지 노출 | from(shop · popup) · level · shows |
| **`iap_begin`** | 결제 버튼 누름 | product |
| `iap_purchase` | 결제 완료 | product |
| **`iap_cancel`** · **`iap_error`** | 결제 취소 · 오류 | product · code |
| **`gems_spend`** + `spend_virtual_currency`(표준) | 다이아 사용 | what(energy_refill · boost_* · coin_pack_* · featured · season_effect · vault · outfit · style · season_decor · season_set · market · bubble) · amount · left · level |

## 3. 비공개 테스트 · 소프트런칭에서 볼 것
- **결제 퍼널**: shop_open → starter_view → iap_begin → iap_purchase (단계별 전환율), iap_cancel 비율
- **다이아 소비처**: gems_spend 를 what 별 합계 → 안 팔리는 상품 · 너무 잘 팔리는 상품 (경제 카탈로그와 비교)
- **광고**: ad_reward kind 별 횟수 · ad_unavailable 비율 · ad_impression 매출
- **리텐션 · 진행**: D1 · D7, tutorial_complete, area_complete(area=0) 비율, energy_empty 뒤 이탈

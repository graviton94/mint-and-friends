# 행동 분석 준비 (D-118)

GA 속성 565225845 (Firebase `mintandfriends-3bb24`). 테스트 기기(Play 사전 보고서 · Test Lab)는 수집을 끈다.
분석 요약: Actions → Insights. GA 설정(맞춤 측정기준 · 보관 14개월 · BigQuery): Actions → Analytics setup (apply=true).

## 질문별로 볼 이벤트

| 질문 | 이벤트 · 속성 |
|---|---|
| 첫날 어디서 떠나나 | `funnel_*` (login_view → login_ok → home_view → first_spawn → first_merge → first_order), `tutorial_step` |
| 며칠 남나 (D1 · D7 · D30) | Firebase 자동 `first_open` · `session_start` + 코호트, `daily_snapshot` |
| 어느 레벨 · 구역에서 멈추나 | `level_up`, `area_complete`, `decor_place`, 사용자 속성 `player_level` · `area` |
| 막히는 순간 | `energy_empty`, `orders_done`(하루 한도 다 씀, 시각), `ad_unavailable` |
| 하루 몇 번 오나 | `session_start`(자동), `event_quest` kind=visit |
| 경제 흐름 | `daily_snapshot`(다이아 · 별 · 에너지 · 코인 자릿수 · 저금통), `gems_spend`(소비처), `spend_virtual_currency` |
| 무엇을 쓰나 | `upgrade_buy` · `upgrade_max`, `boost_on`, `market_buy`, `coin_pack`, `vault_buy`, `menu_tap`, `discover` |
| 결제 퍼널 | `shop_open` → `offer_view`(id · from) → `iap_begin` → `iap_purchase`(krw) / `iap_cancel` / `iap_error` |
| 매출 · ARPU · LTV | Firebase 표준 `purchase`(KRW 값), 광고 `ad_impression`(AdMob 추정 수익), 사용자 속성 `payer` |
| 결제 묶음 | `piggy_ready` · `piggy_full` · `piggy_break`, `energy_bundle`, `milestone_open` · `milestone_bundle`, `special_set` · `outfit_set` |
| 월간 이벤트 | `event_open`, `event_quest`, `event_step`, `event_claim`, `event_pass`, 사용자 속성 `event_pass` |
| 광고 | `ad_reward`(kind = 자리), `ad_impression` |
| 공유 · 초대 | `share_open` · `share_done`, `invite_applied` · `invite_reward` |
| 환불 | `refund_revoke` |

사용자 속성: `payer` · `pass`(none · timed · sub) · `lang` · `renew` · `area` · `player_level` · `event_pass`.

## GA 설정 상태 (11-28)
- 맞춤 측정기준 38개 등록 완료 (이벤트 매개변수 31 + 사용자 속성 7). 새 매개변수를 쓰면 tool/ga_setup.py 목록에 넣고 Actions → Analytics setup.
- 이벤트 데이터 보관 14개월 완료.
- BigQuery 일일 내보내기: 서비스 계정에 클라우드 프로젝트 소유자 권한이 없어 API 로는 못 함 → GA 관리 → 제품 링크 → BigQuery 링크에서 직접 연결 (프로젝트 mintandfriends-3bb24, 서울, 매일).

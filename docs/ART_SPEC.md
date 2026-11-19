# 아트 명세

파일 이름 규칙에 맞는 PNG 를 아래 경로에 넣으면 **코드 수정 없이** 바로 반영됩니다.
없는 파일은 이모지 임시 그림으로 그려집니다 (`lib/art/art.dart`).
`pubspec.yaml` 의 `assets:` 에 폴더를 한 번만 등록하면 됩니다 (아트를 처음 넣을 때 같이 등록).

## 발주 방식 (시트)
비슷한 에셋은 한 장의 그리드 이미지(스프라이트 시트)로 받습니다. 그래야 그림체와 크기가 서로 맞습니다.
발주서 아티팩트에 14장의 시트 프롬프트가 있습니다 (꽃 5×3, 간식 5×3, 친구 기본 3×3, 친구 기쁨 4×2, 장식 구역별 4×2 ×4, 배경 4장, UI 3×2, 앱 아이콘).
받은 시트는 `tool/slice_sheet.py` 로 흰 배경을 지우고 칸별로 잘라 아래 파일 이름으로 넣습니다.

```bash
python3 tool/slice_sheet.py flower_sheet.png 5 3 assets/art/items/flower_{01..15}.png
python3 tool/slice_sheet.py yard.png 1 1 assets/art/areas/yard_bg.png --keep-bg
```

## 공통 규칙
- 형식: PNG, 투명 배경 (배경 이미지 제외), sRGB
- 스타일 (확정): **B 말랑 스티커**. 굵은 짙은 갈색 외곽선, 밝은 파스텔 단색 면, 셀 음영 1단 + 작은 흰 하이라이트, 통통한 형태. 기준 이미지 = `assets/art/friends/bori_idle.png`
- 배경만 **C 플랫 파스텔** (외곽선 없음). 선 있는 캐릭터·장식이 앞으로 떠 보이게 하기 위함
- 여백: 캔버스 가장자리에서 약 6% 띄우기 (칸 안에서 꽉 차 보이지 않게)
- 시선/방향: 캐릭터는 **왼쪽을 바라보게**. 오른쪽으로 걸을 때는 코드가 좌우 반전합니다

## 렌더링 레이어

정원 씬 (`lib/ui/garden/garden_scene.dart`). 아래에서 위 순서로 그립니다:

| 레이어 | 내용 | 아트 |
|---|---|---|
| L0 배경 | 하늘 + 땅 | `areas/<구역>_bg.png` 한 장 (없으면 단색) |
| L1 월드 | 장식, 친구, 손님. 발 위치(y) 기준으로 앞뒤를 정렬 | `decor/*`, `friends/*` |
| L2 이펙트 | 말풍선, 하트·코인 숫자 | 코드 |
| L3 UI | 구역 이름, 메뉴 버튼 | `ui/*` |

머지 보드 (`lib/ui/board/board_view.dart`):

| 레이어 | 내용 | 아트 |
|---|---|---|
| L0 칸 | 바닥 타일, 잠긴 칸 자물쇠 | `ui/lock.png` |
| L1 아이템 | 아이템, 비눗방울, 선택 테두리 | `items/*`, `ui/bubble.png` |
| L2 드래그 | 손가락을 따라오는 아이템 | 같은 아이템 그림 |
| L3 이펙트 | 합치기 반짝임 | 코드 |

## 파일 목록

### 아이템 (30개): `assets/art/items/`
512×512. 대상이 캔버스의 약 80% 를 차지하게.

| 파일 | 내용 |
|---|---|
| `flower_01.png` ~ `flower_15.png` | 씨앗, 새싹, 클로버, 어린 잎, 화분, 데이지, 튤립, 벚꽃, 장미, 히비스커스, 해바라기, 연꽃, 꽃다발, 무지개꽃, 황금 꽃 |
| `snack_01.png` ~ `snack_15.png` | 체리, 딸기, 사과, 복숭아, 레몬, 쿠키, 컵케이크, 도넛, 팬케이크, 파이, 푸딩, 조각 케이크, 파르페, 생일 케이크, 피크닉 도시락 |

레벨이 올라갈수록 크기감과 장식(반짝임, 리본 등)이 조금씩 화려해지게.

### 친구 (8명 × 2장 + 손님 1장): `assets/art/friends/`
512×512, 2등신 SD, 전신, 바닥에 서 있는 자세. 발이 캔버스 아래 8% 지점에 닿게 (그림자는 코드가 그림).

| 파일 | 캐릭터 |
|---|---|
| `bori_idle.png`, `bori_happy.png` | 보리 (토끼) |
| `dubu_idle.png`, `dubu_happy.png` | 두부 (곰) |
| `kwak_idle.png`, `kwak_happy.png` | 꽥이 (오리) |
| `nabi_idle.png`, `nabi_happy.png` | 나비 (고양이) |
| `dotori_idle.png`, `dotori_happy.png` | 도토리 (다람쥐) |
| `mochi_idle.png`, `mochi_happy.png` | 모찌 (판다) |
| `danpung_idle.png`, `danpung_happy.png` | 단풍 (여우) |
| `kongtteok_idle.png`, `kongtteok_happy.png` | 콩떡 (햄스터) |
| `visitor_idle.png` | 깜짝 손님 (고슴도치) |

`idle` 은 기본 표정, `happy` 는 눈을 감고 웃는 표정 + 양팔을 든 자세. 두 장의 크기와 위치가 같아야 바꿔 그려도 흔들리지 않습니다.

### 장식 (32개): `assets/art/decor/`
512×512, 3/4 정면 시점(살짝 위에서 내려다봄). 물체의 바닥이 캔버스 아래쪽 10% 지점에 오게.

| 구역 | 파일 |
|---|---|
| 햇살 앞마당 | `big_tree` `bench` `mailbox` `veggie_patch` `lantern` `bird_feeder` `hut` `fountain` |
| 반짝 연못 | `stepping_stones` `water_lily` `fishing_spot` `rowboat` `reeds` `log_chair` `tent` `wooden_bridge` |
| 꽃향기 온실 | `glasshouse` `cactus` `mushroom_bed` `watering_can` `sunflower_field` `tea_table` `bamboo` `wind_chime` |
| 별빛 언덕 | `telescope` `camp_tent` `campfire` `ferris_wheel` `carousel` `moon_statue` `little_castle` `fireworks` |

(각각 `.png`)

### 구역 배경 (4장): `assets/art/areas/`
1080×720 (3:2), 투명 아님. 위쪽 28% 는 하늘, 그 아래는 땅. 장식 자리 위치는 `lib/game/config.dart` 의 `DecorDef(x, y)` 를 따릅니다. 배경에는 물체를 그리지 말고 지형(잔디, 길, 물가)만 그립니다.

`yard_bg.png`, `pond_bg.png`, `greenhouse_bg.png`, `starry_hill_bg.png`

### UI (6개): `assets/art/ui/`
256×256.

`coin.png` `star.png` `basket.png` `lock.png` `bubble.png`(투명한 비눗방울 테두리만) `gift.png`

### 앱 아이콘
1024×1024 한 장을 주시면 Android 적응형 아이콘(전경/배경)으로 변환해 넣습니다.

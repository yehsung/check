# 아잉체크 랜딩 — 에셋 매니페스트 · 내보내기 레시피

작성 2026-10-12 · 범위: 읽기·분석·설계(저장소 파일은 하나도 고치지 않았다)
소재 원본: `/Users/yesung/aing-check-promo/public/assets`(아래에서는 `A/`로 줄인다) · 앱 아이콘 `/Users/yesung/check/packaging/appicon/icon-1024.png`
실측 스크립트(설계 초안, 실제로 돌려서 바이트를 쟀다): `design/export-assets.mjs` · 시험 출력: `design/probe/landing/public/assets/`

---

## 0. 결정 요약

1. **캐릭터 움직임은 알파 영상 두 벌로 낸다.** 크롬·엣지·파이어폭스는 VP9 알파 `.webm`, 사파리와 모든 iOS 브라우저는 HEVC 알파 `.mov`(hvc1). 포스터는 webp 한 장. 스프라이트 시트는 쓰지 않는다. 근거는 §6.3의 실측이다. 14.4초 진짜 루프를 30fps 시트로 만들면 4.1MB에 디코드 메모리가 358MB인데, 영상은 664KB에 메모리도 거의 들지 않는다.
2. **스크린샷은 `@3x → @2x`(pt × 2) webp로 낸다.** 데스크톱에서는 1 CSS px = 1 pt로 보여 준다. 그러면 팝오버가 실제 맥에서 보이는 크기와 같아진다. 한 장에 30~50KB다.
3. **히어로 = 실제 3D 아잉 루프 + 실제 메뉴바 라벨 + 실제 팝오버.** [근무 시작]을 누르면 앱 렌더 그대로 반응한다. 아잉이 폴짝 뛰며 360° 돌고, "오늘도 화이팅!" 말풍선과 몸통 위 00:00 라벨이 뜨고, 팝오버의 초가 1초씩 흐른다. 전부 앱 렌더 그대로이고, 손으로 그린 상태는 하나도 없다.
4. **아이폰은 코드로 그린 셸 + 다크 스크린샷(폭 600)으로 한다.** MockupSnap 3D 폰은 쓰지 않는다(라이선스 불명).
5. **3D 맥북 격자는 '선택'으로 둔다.** 모델 라이선스(MIT)는 깨끗하다. 다만 화면에 무엇을 띄우든 "가짜 데스크톱"이 되기 쉬워서 사용자 확인이 필요하다(§8).
6. **예상 무게(크롬 기준 실측 합산): 첫 화면 약 1.03MB(사파리 1.15MB), 페이지 전체 약 3.7MB(선택 항목을 다 넣으면 4.4MB).** 예산은 첫 화면 1.5MB, 전체 4.5MB(상한 6MB)로 잡는다.

---

## 1. 소재 실측 — 크기·알파·프레임 (sips + 매니페스트로 직접 확인)

| 묶음 | 경로 | 픽셀 | 알파 | 프레임 / fps | 비고 |
|---|---|---|---|---|---|
| 맥 팝오버(@3x) | `A/v4/mac/ui/popover_main_*@3x.png` | 1242×1959 (414×653pt) | PNG 알파 있음, 실제는 불투명 | 정지 | 앱 0.3.38 렌더. 배경 #1d202b~#232431 |
| 근무 시작 틱 | `A/v4/mac/ui/tick/popover_tick_on_00…11@3x.png` | 1242×1959 | 불투명 | 12장 · 1초 간격 | 장마다 바뀌는 곳은 열 하나뿐(@3x 차분 bbox (291,146)-(555,1654)) |
| 메뉴바 라벨 | `A/v4/mac/ui/menubar/menubar_aing_*_{dark,light}_alpha@10x.png` | 615×220 / 772×220 (22pt 높이) | **투명** | 정지 | 바탕을 흉내 내지 않은 투명판. dark = 흰 글자 |
| 메뉴바 아이콘 | `A/v4/mac/ui/menubar/menubar_aing_icon_*@10x.png` | 260×260 | 투명 | 정지 | 빨간 점 판 따로 있음 |
| 말풍선 | `A/v4/mac/ui/bubble/bubble_*@8x.png` | 예: poked 1040×344, ultra 1912×513 | 투명 | 정지 | 고정 폭 130pt에 사방 여백 10pt라 **오른쪽이 많이 비어 있다** → 알파 bbox로 잘라 쓴다 |
| 기록 | `A/v4/mac/ui/insights_full@3x.png` | 1020×2342 (340×781pt) | 불투명 | 정지 | 회고·리듬·12주 잔디 둘 |
| 순위(팀 리그) | `A/v4/mac/ui/league_week@3x.png` | 1242×1800 | 불투명 | 정지 | 우리 팀 2위 |
| 콕 | `A/v4/mac/ui/poke_list@3x.png` · `poke_row_mint@6x.png` | 1242×1962 · 1824×324 | 불투명 | 정지 | ⚡3 · "3초 꾹 = 울트라" |
| 메시지 | `A/v4/mac/ui/message_thread_gureum_read@3x.png` | 1242×1809 | 불투명 | 정지 | "24시간이 지난 메시지는 사라져요" |
| 미니게임 | `A/v4/mac/ui/minigame_window_flappy_playing_8rows@3x.png` | 2100×1168 | 불투명 | 정지 | **8rows 판만**(9번째 빈 줄 판 금지) |
| 오목 | `A/v4/mac/ui/gomoku_playing@3x.png` | 3720×2100 (1240×700pt) | 불투명 | 정지 | 원본 6.9MB → webp 1600w에서 39KB |
| 울트라 충전 | `A/v4/mac/ui/ultra_charge@3x.png` | 1242×1689 | 불투명 | 정지 | "3시간 채웠어요 — 루비 +3" |
| 캐릭터 고르기 | `A/v4/mac/ui/character_pick_aing@3x.png` | 1242×1485 | 불투명 | 정지 | 6종이 한꺼번에 보이는 유일한 판(한 번만 노출) |
| 할 일 보드 | `A/v4/mac/ui/todo_board_today_opaque@3x.png` | 900×1200 | **반투명 창** | 정지 | 캐릭터를 클릭하면 열리는 것(앱 기본 동작) |
| 아잉 idle_long | `A/v4/char/aing/idle_long/%04d.png` | 2100×2625 | 투명(가장자리 페더 140px) | **432f / 30fps(14.4초, 진짜 루프)** | body bbox [540,1144,1563,2111] · 깜빡 f40·166·265·382 |
| 아잉 face_left/right | `A/v4/char/aing/face_{left,right}/` | 2100×2625 | 투명 | 108f / 30 | 드래그 방향 보기(앱은 즉시 스냅) · body [652,1140,1495,2107] / [560,1140,1451,2111] |
| 아잉 angle_top | `A/v4/char/aing/angle_top/` | 2100×2625 | 투명 | 108f / 30 | **앱에 없는 카메라 → 랜딩 금지** |
| 아잉 ultra_charged | `A/v4/char/aing/ultra_charged/` | 2100×2625 | 투명 | 102f / 30 | 파란 흡수 스파크 54f · body [460,1040,1675,2187] |
| 아잉 ultra_poked | `A/v4/char/aing/ultra_poked/` | **2160×2160(ultra 캔버스)** | 투명(페더 0) | 165f / 30(5.5초) | body [268,56,1935,1519] · 12.5Hz 떨림이라 30fps에서 맥놀이처럼 보인다 |
| 아잉 v3 반응 | `A/v3/mac/char/aing/{commute_start 45, commute_end 36, poked 90, hit 36, greeting 42, milestone 72, goal_achieved 96, drowsy_wake 132, idle 108}` | 2100×2625 | 투명 | 괄호 안 프레임 / 30fps | 모든 시퀀스의 0번 = idle 위상 262의 같은 자세 |
| 캐릭터 5종 | `A/v3/mac/char/{fox,shiba,jellyfish,ghost,squirrel}/…` | 2100×2625 (shiba/ultra 1620²) | 투명 | §3 표 | 2D 스프라이트(그림 한 장) |
| 앱 UI 층 | `A/v3/mac/char/_ui/{bubble_00…06,timer_00-00…04-00}.png` · `A/v4/char/aing/_ui/bubble_00.png` | 2100×2625 | 투명 | 정지 | 앱 배치 그대로 그린 층. 말풍선 그림자 상자 좌상단 = (323,981), 근무 라벨 = (787,1686) 527×239 |
| 아이폰 화면 | `A/v4/ios/screens/*_{light,dark}@3x.png` | 1206×2622 (402×874pt, iPhone 17 Pro) | **불투명(알파 없음)** | 정지 | 공개 1.0.1(빌드 9) 렌더 · 상태 막대 14:05 · **다이내믹 아일랜드 없음** |
| 위젯 | `A/v4/ios/widgets/promo_*_{dark,light}@3x.png` | S 510×510 · M 1092×510 · L 1092×1146 | 투명(모서리 알파 0) | 정지 | 위젯 판 바탕 #23252f 근처 |
| 잔디 | `A/v4/ios/grass/*` + `grass.json` | 크롭들 | — | 정지 | 칸 좌표 있음(점등 연출 가능) |
| 화면 녹화 | `A/v4/ios/flows/*.mov` + 프레임 폴더 | 1206×2622 H.264 | — | 30fps, 12~21초 | 4~11.6MB → 랜딩에는 무겁다 |
| 3D 맥북 | `A/v4/laptop/frames/p{pitch}_y{yaw}_{lid,base}.webp` | 4800×4200 캔버스 크롭(예: lid 2561×1819 · base 3126×794) | 투명(무손실) | 493각도 × 2층 = 986장 · 47.98MB | 요 −21~+21 · 피치 −9~+15, 1.5° 간격 |
| 3D 아이폰 | `A/v4/phone3d/frames/p{pitch}_y{yaw}.webp` | 3840×2160 캔버스 크롭(예: 861×1830) | 투명 | 1701장 · 126MB | **MockupSnap GLB — 라이선스 불명 → 금지** |
| 인트로 방 | `A/v4/intro/{R1…R4,N0…N3}/final.png` | 1672×941 | 불투명(크로마키 초록 화면) | 정지 | **Codex image_gen 생성 이미지** · 밝은 클레이 방 → 랜딩 금지 |
| 앱스토어 | `A/v4/appstore/icon_512_squircle.png` · `screenshot_*.jpg` | 512² · 660×1434 | 아이콘만 알파 | 정지 | 스크린샷은 **옛 인물(새벽 커피단·민트·라임)** → 금지 |
| 브랜드 | `A/v3/brand/appstore-badge-ko-black.svg` · `qr-appstore.svg` · `icon-mac-1024.png`(= check 아이콘과 같은 바이트) · `icon-ios-1024.png` | SVG · 1024² | 맥 아이콘 알파 / iOS 불투명 | — | 배지는 애플 공식 원본 바이트 그대로 |
| 2D 얼굴 | `A/brand/aing-neutral.png` · `aing-negative.png` | 192×192 | 투명 | — | 메뉴바·헤더·폰에 쓰이는 2D 초상(웃음/시무룩) |
| 폰트 | `/Users/yesung/aing-check-promo/public/fonts/Pretendard-*.woff2` · `JetBrainsMono-*.woff2` + LICENSE | Pretendard 정적 766~794KB · Variable 2.06MB · JBM 92~95KB | — | — | **원본은 `assets/` 밑이 아니라 `public/fonts`에 있다** |
| 소개 영상 | `/Users/yesung/aing-check-promo/out/v4/aing-check-v4.mp4` · `thumbnail.png`(·`-640`) | 1920×1080 H.264 + AAC · 69.6초 · 16.2MB | — | — | 썸네일에 **재현 화면(앱스토어 검색·터미널)** 이 들어 있다 |

---

## 2. 추천 에셋 표 (랜딩 용도별)

출력 경로는 모두 `landing/public/assets/` 기준이다. 바이트는 `export-assets.mjs`를 실제로 돌려 잰 값이고, 추정치에는 "≈"를 붙였다.

| 용도 | 원본(절대 경로) | 출력 · 픽셀 | 알파 | 프레임 / fps | 바이트 | 주의점 |
|---|---|---|---|---|---|---|
| **히어로 캐릭터(상시)** | `/Users/yesung/aing-check-promo/public/assets/v4/char/aing/idle_long/%04d.png` | `char/aing-idle.{webm,mov}` · 654×790(HERO 박스, S 0.5) + `aing-idle-poster.webp` | 알파 영상 | 432f / 30fps 루프 | webm 664KB(crf46) · mov 782KB(q30) · 포스터 17KB | 포스터를 먼저 칠하고 영상은 load 뒤에 붙인다. 모바일·Save-Data에서는 15fps판(webm 358KB / mov 530KB) |
| 히어로 — [근무 시작] 반응 | `…/v3/mac/char/aing/commute_start/%04d.png` | `char/aing-commute-start.{webm,mov}` · 654×790 | 알파 | 45f / 30 | ≈135KB / ≈130KB(crf40 실측 148/143) | 끝나면 idle_long의 (45 mod 432)=45번으로 이어진다(앱 연속성 규칙) |
| 히어로 — 말풍선 | `…/v4/mac/ui/bubble/bubble_commute_start@8x.png`(·`first_arrival`·`autostart`) | `ui/bubble-commute-start.webp` 242×89(@3x) + `ui/bubbles.json` | 투명 | — | 5.8KB | 앱 배치: 그림자 상자 좌상단 = 캔버스 (323,981), 캔버스 px = @3x px × 3.5 |
| 히어로 — 몸통 근무 라벨 | `…/v3/mac/char/_ui/timer_00-00.png`(·`00-01`) | `ui/timer-00-00.webp` 264×120 | 투명 | — | 11.9KB | 박스 좌표 (181.5, 571)px(S 0.5). HH:MM이라 데모 1분 동안은 00:00 |
| **메뉴바 데모** | `…/v4/mac/ui/menubar/menubar_aing_{off,working_0000,working_0345,working_0345_newmsg,working_0642}_dark_alpha@10x.png` | `ui/menubar-*.webp` · 높이 132(22pt를 3배로 보여 주는 크기의 2x) | 투명 | — | 5.9~8.6KB | 투명판이다. 메뉴바 띠를 그리려면 단색 하나만 쓰고 다른 메뉴 항목은 흉내 내지 않는다 |
| **팝오버 데모** | `…/v4/mac/ui/popover_main_off_1020@3x.png` → `tick/popover_tick_on_00@3x.png` → `on_01…11` | `ui/popover-off.webp` · `ui/popover-on.webp` 828×1306 + `ui/popover-tick-strip.webp` 2160×1010(180×1010 × 12칸) | 불투명 | 13상태 · 1초 | 38.9 + 40.1 + 89.3KB | 틱 칸은 on 판의 (192,96)에 덮는다(@2x 정수 좌표). off→on 사이에는 [근무 시작]→[근무 종료], 4명→5명, 새벽 행 순서가 바뀐다 — 실측 확인함 |
| 팝오버(한낮·새 메시지) | `…/popover_main_working_1405@3x.png` · `…_1405_newmsg@3x.png` | `ui/popover-working.webp` · `ui/popover-newmsg.webp` 828×1306 | 불투명 | — | 40.5 · 40.6KB | 9월 AI 토큰 2,376,382,712(가상 값) |
| **찌르기** | `…/v4/mac/ui/poke_list@3x.png` · `poke_row_mint@6x.png` · `poke_focus_stage1@3x.png` | `ui/poke-list.webp` 828×1308 · `ui/poke-row-mint.webp` 608×108 · `ui/poke-focus.webp` | 불투명 | — | 43.3 · 3.8 · 46.4KB | 줄 하나(민트별)가 클릭 대상으로 딱 맞는 크기다 |
| 찌르기 — 반응 | `…/v3/mac/char/aing/poked/%04d.png` + `bubble_poked_mint@8x.png` | `char/aing-poked.{webm,mov}` 654×790 + `ui/bubble-poked-mint.webp` 239×125 | 알파 | 90f / 30(2.35초+) | 296 / 275KB · 7.6KB | 클릭하면 f6부터 재생한다(f0~5는 idle과 같은 자세). 끝나면 idle_long 90번으로 이어진다. 1:1 메시지 수신도 같은 동작이다 |
| **울트라** | `…/v4/char/aing/ultra_poked/%04d.png` + `bubble_ultra_mint@8x.png` | `char/aing-ultra.{webm,mov}` 840×738 + 포스터 + `ui/bubble-ultra-mint.webp` 717×189 | 알파 | 165f / 30 | 757 / 762KB · 20.5 · 14.6KB | 가장 무겁다 → 절 진입 600px 전에 받는다. 앱 사실: 받는 사람 화면을 **보낸 사람 캐릭터**가 5초 덮는다. 민트별 = 아잉 착용자라 "민트별님의 울트라 찌르기!"와 맞는다 |
| 울트라 충전·루비 | `…/v4/char/aing/ultra_charged/%04d.png` · `…/v4/mac/ui/ultra_charge@3x.png` · `shop_ruby@3x.png` | `char/aing-ultra-charged.{webm,mov}` 614×580 · `ui/ultra-charge.webp` 828×1126 · `ui/shop-ruby.webp` | 알파 / 불투명 | 102f / 30 | ≈265 / ≈290KB(crf40 실측 295/317) · 29.3 · 36.2KB | "루비 +3!" 말풍선(v4 `_ui/bubble_00.png`) |
| **캐릭터 6종** | `…/v4/char/aing/idle_long/0000.png` · `…/v3/mac/char/{fox,shiba,jellyfish,ghost,squirrel}/idle/0000.png` | `char/still-{aing,fox,shiba,jellyfish,ghost,squirrel}.webp` · 높이 400 | 투명 | 정지 | 14.0 / 24.0 / 18.4 / 23.1 / 12.5 / 23.3KB | 정지 1장 + CSS 부유면 충분하다(§3). 고르기 화면은 `ui/character-pick.webp`(35KB) 한 번만 |
| 캐릭터 걷기(선택) | `…/v3/mac/char/{5종}/walk/{0000,0005,0009,0013}.png` | `char/walk-*.webp` · 4포즈 가로 띠, 높이 300 | 투명 | 4포즈 × 140ms(앱 아틀라스 그대로) | 27~63KB(5종 255KB) | 아잉은 3D라 걷기가 없다. 왼쪽으로 걸을 때는 수평 반전(앱도 같은 프레임을 미러) |
| **기록** | `…/v4/mac/ui/insights_full@3x.png` | `ui/insights.webp` 680×1561 | 불투명 | — | 45.9KB | 잔디 점등 연출은 `insights/work_grass_{empty,wk01,final}@3x.png` + `grass_light.json` |
| **순위** | `…/v4/mac/ui/league_week@3x.png` | `ui/league.webp` 828×1200 | 불투명 | — | 49.3KB | AI 토큰 순위판(`token_board_month@3x.png`)도 같은 규칙 |
| **미니게임** | `…/v4/mac/ui/minigame_window_flappy_playing_8rows@3x.png` | `ui/minigame.webp` 1400×779 | 불투명 | — | 34.7KB | 아래 가장자리가 캔버스를 가른다 → 아래쪽 페이드 마스크 |
| **오목** | `…/v4/mac/ui/gomoku_playing@3x.png` | `ui/gomoku.webp` 1600×903 + `ui/gomoku-sm.webp` 900w | 불투명 | — | 38.8 · 18.1KB | 원본 6.9MB. 차례 링 22초 |
| 메시지 | `…/v4/mac/ui/message_thread_gureum_read@3x.png`(·`unread`·`composing`) | `ui/message-thread.webp` 828×1206 | 불투명 | — | 36.3KB | 폰 대화(`conv-gureum_*`)와 말·시각이 같다 |
| 할 일 보드 | `…/v4/mac/ui/todo_board_today_opaque@3x.png` | `ui/todo-board.webp` 600×800 | 반투명 | — | 22.3KB | 히어로 아잉을 클릭하면 이것이 열리는 게 앱 사실이다("아얏!"은 설정으로 끈 경우) |
| **아이폰** | `…/v4/ios/screens/{now,now_s2,messages,conv-gureum_read,rankings-league,games,gomoku-match,me,me_records,me-characters}_dark@3x.png` | `ios/*.webp` 600×1304 | 불투명 | — | 24.5~40.7KB(10장 332KB) | 셸은 코드로 그린다(§9). 아일랜드는 CSS로 덮는다 |
| **위젯** | `…/v4/ios/widgets/promo_{today-small,working-medium,todos-large,todos-medium}_dark@3x.png` | `ios/widget-*.webp` · S 340² · M 728×340 · L 728×764 | 투명 | — | 9.0 / 14.4 / 19.5 / 11.0KB | 표시 = pt 크기(170 / 364 CSS px 폭) |
| 3D 맥북(선택) | `…/v4/laptop/frames/p+03.0_y{−21…+21 step 3}_{lid,base}.webp` | `laptop/p3_y*.webp` × 30장(K 0.5) | 투명 | 15포즈 | 384KB(층 분리) / 510KB(합친 고정 상자 2026×1366) | §8. 화면 내용이 "가짜 데스크톱"이 되지 않게 할 것 |
| 3D 폰 | `…/v4/phone3d/frames/*` | — | — | — | — | **쓰지 않는다**(라이선스 불명) |
| **아이콘** | `/Users/yesung/check/packaging/appicon/icon-1024.png` | `brand/icon-{128,256}.webp` · `app/icon.png` 512 · `app/apple-icon.png` 180(#15172a로 평탄화) · `favicon-32.png` | 투명(스퀴클) | — | 3.0 · 6.8 · 152.7 · 28.4 · 2.0KB | icon.png는 256으로 줄이면 ≈45KB |
| **App Store 배지** | `…/v3/brand/appstore-badge-ko-black.svg` | `brand/appstore-badge-ko-black.svg` | SVG | — | 9.0KB | 바이트 그대로 둔다. 수정·기울이기·애니메이션 금지, 최소 높이 40px, 여백 = 높이의 1/4 |
| QR(선택) | `…/v3/brand/qr-appstore.svg` | — | — | — | — | payload가 `/kr/` 붙은 URL이다. 쓸 거면 `https://apps.apple.com/app/id6812768622`로 다시 만든다 |
| 소개 영상(선택) | `/Users/yesung/aing-check-promo/out/v4/aing-check-v4.mp4` | `video/promo-720.mp4` 1280×720 · H.264 CRF 24 · AAC 128k | — | 69.6초 | ≈7~9MB | `preload="none"`, 누를 때만 받는다(무게 예산 밖) |

App Store 링크: **`https://apps.apple.com/app/id6812768622`**. `docs/appstore.md` §6의 결정에 따라 지역 코드는 넣지 않는다(판매 지역 175개라 애플이 보는 사람 지역으로 보낸다). 출처는 저장소 `docs/appstore.md:365`와 `A/v4/appstore/source.json`(trackId 6812768622, 이름 '아잉체크', 부제 '팀 근무 현황 · 메시지 · 미니게임')이다.

---

## 3. 다른 캐릭터 5종 — 시퀀스 목록과 랜딩 판단

모두 2100×2625 알파 PNG, 30fps이고 kind는 `sprite`(그림 한 장짜리 2D 평면)다. 바운딩 박스는 `alphaBBoxUnion` [x0,y0,x1,y1]이다.

| 캐릭터(이름) | 동작과 프레임 | idle bbox | walk bbox | 비고 |
|---|---|---|---|---|
| 여우 fox | idle 108 · walk 108 · poked 90 · commute_start 45 · commute_end 36 · goal_achieved 96 · milestone 72 · drowsy_wake 132 · **hit 36 · greeting 42** | [590,1031,1498,2098] | [450,1035,1680,2123] | hit·greeting은 여우만 있다 |
| 강아지 shiba | 위 8종 + **ultra 165(1620² ultra 캔버스)** | [607,994,1496,2131] | [483,996,1688,2152] | 가상 인물 호두과자. 울트라 판에서 귀가 정사각 위 경계에 닿아 잘리는 프레임이 있다(앱도 같다) |
| 해파리 jellyfish | 8종 | [607,1041,1504,2093] | [454,1043,1695,2090] | 다리가 없어 옆을 보고 떠서 걷는다 |
| 유령 ghost | 8종 | [469,932,1653,2181] | [487,931,1667,2190] | 같은 이유 |
| 다람쥐 squirrel | 8종 | [603,931,1514,2173] | [518,932,1592,2193] | — |

- **idle은 정지 1장 + CSS 부유로 충분하다.** 실측해 보니 프레임 0 대비 13·27·54·81번의 차이가 세로 이동 −2~+46px(캔버스 2625 기준 1.7%)과 크기 −1% 정도다. 그림 자체는 같은 평면이 떠다니는 것뿐이다. 그래서 `translateY(±0.9%) · 3.6초 ease-in-out` 루프로 거의 같게 보인다. 아잉(3D)도 캐릭터 절에서는 정지 1장이면 된다(살랑이는 미세한 움직임).
- **walk는 실제 그림 4장뿐이다.** 앱 아틀라스가 4프레임 × 140ms이고, 30fps 렌더의 알파 차분을 보면 포즈는 5·9·13·17번에서 바뀐다(실측). 그래서 0·5·9·13번 4장을 가로 띠로 뽑아 `steps(4)` 560ms로 돌리면 앱과 같은 타이밍이 된다. 5종을 합쳐도 255KB다.
- poked·goal_achieved의 금빛 스파크, milestone의 색종이 같은 반응은 캐릭터 절의 필수 요소가 아니다. 넣는다면 아잉 판(3D)만 영상으로 낸다. 스프라이트 반응은 앱에서 "기울고 늘어나는" 2D 동작이고, v3 렌더는 사용자 결정('2D는 입체 움직임 없게')을 따른 판이다(v3 manifest knownIssues 참조).
- 캐릭터 6종이 한꺼번에 보이는 앱 화면은 `character_pick_aing@3x`와 폰 `me-characters`뿐이다. 매니페스트 규칙("한 번 노출용")을 지킨다.

---

## 4. 쓰지 말 것 (이유)

- `A/char/*`, `A/v2/**`, `A/v3/mac/ui`, `A/v3/ios/**`: 옛 소재다(아잉 몸통 709px·512 텍스처, 나 = 여우였던 v3 인물). 대체판은 v3/v4 같은 이름 폴더에 있다.
- `A/v4/appstore/screenshot_*.jpg`: 실제 스토어 이미지지만 **옛 인물 이름**(새벽 커피단·민트·라임)이 섞여 있어 v4 인물 세트와 충돌한다. 게다가 상단 캡션이 구워져 있다.
- `A/v4/char/aing/angle_top`: 앱에 없는 카메라다.
- `A/v4/mac/ui/header/*_goal_done_1405`, `goalbar/*_goal_done_1405`, `popover_banner_retro`, `banner_retro`: 매니페스트가 "장부 밖 가정 판"이라고 표시한 것이다.
- `A/v4/mac/ui/minigame_window_flappy_playing@3x.png`·`_ready`: 9번째 빈 줄이 남아 있다. 8rows 판만 쓴다.
- `A/v4/mac/ui/settings/*`: 전역 단축키는 소개하지 않는다는 규칙이 있다. 단축키가 안 보이게 자른 판만 있고, 아래 가장자리가 카드 중간에서 잘려 있다.
- `A/v4/intro/**`, `A/v3/gen/**`: Codex image_gen(gpt-6-astra)으로 생성한 클레이 방과 소품이다. 밝은 크림 톤이라 다크 랜딩과 맞지 않고, "식상한 템플릿·가짜 데스크톱"에 가깝다.
- `A/v4/phone3d/**`, `A/v3/mockup/**`: MockupSnap 페이지의 three.js 장면(GLB)을 렌더한 것이다. 모델 라이선스 표기가 없다.
- `out/v4/thumbnail*.png`을 랜딩 그림으로 쓰는 것: 앱스토어 검색 화면과 터미널을 **재현해** 그린 판이다(`src/v4/AppStoreSearch.tsx`). 영상 포스터로만 쓴다.
- `A/v4/ios/flows/*.mov`: 4~11.6MB다. 폰 절은 정지 화면 교차로 충분하다.

---

## 5. 라이선스 메모

| 대상 | 출처·라이선스 | 랜딩에서 할 일 |
|---|---|---|
| 앱 스크린샷(맥·폰·위젯)과 캐릭터 렌더 전부 | 자사 앱 코드를 ImageRenderer·SCNRenderer·시뮬레이터로 그린 것이다. 가상 인물만 나오고 실사용자 0명(각 매니페스트 rules) | 표기할 것 없음 |
| 캐릭터 3D 모델·스프라이트 | 앱 번들 자산(aing.scn·아틀라스) | 앱과 같다 |
| 3D 맥북 프레임 | pmndrs/examples `multiple-views-with-uniform-controls/public/mac.glb` — **MIT, © 2024 Poimandres**. 파일 안에 저작자 표기 없음(pmndrs market CC0 계열로 보임). 조명·렌더러 설정만 MockupSnap 페이지를 따랐다. `A/v4/laptop/NOTICE.txt` | 쓴다면 NOTICE 문구를 `/licenses`나 푸터 '오픈소스 고지'에 싣는다. 애플 로고는 이 격자 각도에서 보이지 않는다 |
| 3D 아이폰 프레임 | MockupSnap iPhone 16 Pro 페이지의 GLB·장면. **라이선스 명시 없음** | 쓰지 않는다. 셸은 CSS로 그린다 |
| Pretendard | SIL OFL 1.1(`public/fonts/LICENSE-Pretendard.txt`) | 서브셋·재배포 가능. 이름을 바꾸지 않는 한 그대로 쓴다. 고지 파일을 함께 둔다 |
| JetBrains Mono | SIL OFL 1.1(`LICENSE-JetBrainsMono.txt`) | 쓴다면 위와 같다. 권장은 `ui-monospace` 시스템 글꼴(0바이트) |
| App Store 배지 | 애플 마케팅 툴박스 공식 SVG(source_url은 `v3/brand/manifest.json`) | 애플 가이드라인을 따른다. 수정 금지, 페이지당 하나 |
| 생성 소품(v3/gen G1~G8)·인트로 방(v4/intro) | Codex CLI 0.154.0 image_gen(gpt-6-astra)으로 사용자 세션에서 생성(프롬프트·시각·sha256 기록) | 쓰지 않는 것을 권한다. 쓰더라도 캐릭터 생성물이 아니라 소품뿐이다 |
| 소개 영상 | 자사 Remotion 렌더(음악·효과음 출처는 `aing-check-promo/public/audio`·`sfx` 쪽 기록 확인 필요) | 영상을 넣으면 음원 라이선스를 별도로 확인한다 |

---

## 6. 내보내기 레시피 (Node + sharp)

### 6.1 실행 환경

- 스크립트: `design/export-assets.mjs`(초안, 실측에 쓴 그대로). 구현 때 `landing/scripts/export-assets.mjs`로 옮기고 `sharp`를 devDependency로 둔다.
- 입력은 `/Users/yesung/aing-check-promo/public/assets`(+ 아이콘)에서 **읽기만** 한다. 출력은 `landing/public/assets/`(+ `landing/app/icon.png` 등)이고, **결과물은 커밋한다.** Vercel(리눅스) 빌드에서는 돌리지 않는다. `hevc_videotoolbox`가 macOS 전용이기 때문이다.
- ffmpeg: brew `ffmpeg`(libvpx-vp9 + hevc_videotoolbox), 또는 이 맥에 이미 있는 `/Users/yesung/aing-check-promo/node_modules/@remotion/compositor-darwin-arm64/ffmpeg`(`DYLD_LIBRARY_PATH`를 같은 폴더로). Remotion 판은 **pad·select 필터가 빠진 축소판**이라 짝수 크기 맞춤과 크롭은 sharp에서 한다.
- 명령: `OUT=landing/public/assets FFMPEG=$(which ffmpeg) node scripts/export-assets.mjs [--only=char,ui,ios,stills,brand]`. 시퀀스 일부만 다시 뽑을 때는 `SEQ=aing-idle,aing-poked`.
- 소요 시간: 스크린샷·정지·브랜드 22초, 캐릭터 영상 6종 43초(M 계열 맥 실측).

### 6.2 규칙(입력 → 출력 → 크기 → 포맷 → 품질)

| 종류 | 입력 | 출력 이름 | 크기 규칙 | 포맷 · 품질 |
|---|---|---|---|---|
| 맥 스크린샷 | `v4/mac/ui/*@3x.png` | `ui/<짧은이름>.webp` | **@3x → @2x**(폭 = pt × 2). 예: 팝오버 1242 → 828. 큰 창(오목 1240pt)은 표시 최대 800 CSS px의 2배인 1600w, 모바일용 900w | webp q80, smartSubsample, effort 6(반투명 창은 alphaQuality 90) |
| @6x·@8x·@10x 조각 | `poke_row@6x` · `bubble@8x` · `menubar@10x` | `ui/poke-row-mint.webp` · `ui/bubble-*.webp` · `ui/menubar-*.webp` | 행 = pt × 2. 말풍선 = 알파>8 bbox로 자른 뒤 @3x. 메뉴바 = 높이 132(22pt를 3배로 크게 보여 주는 크기의 2x) | webp q90, alphaQuality 100(글자 가장자리) |
| 근무 시작 틱 | `tick/popover_tick_on_00…11@3x.png` | `ui/popover-tick-strip.webp` | @3x 영역 (288,144) 270×1515 → @2x (192,96) 180×1010, 12칸 가로 띠 | webp q82 |
| 아이폰 | `v4/ios/screens/*_dark@3x.png` | `ios/<slug>.webp` | 폭 600(표시 300 CSS px × 2). 원본 @3x 1206의 0.4975배 | webp q80 |
| 위젯 | `v4/ios/widgets/promo_*_dark@3x.png` | `ios/widget-*.webp` | pt × 2(S 340, M·L 728) | webp q85, alphaQuality 100 |
| 캐릭터 정지 | idle 0번 | `char/still-<id>.webp` | 자기 idle alphaBBoxUnion으로 자르고 높이 400 | webp q82, alphaQuality 90 |
| 걷기 | walk 0·5·9·13번 | `char/walk-<id>.webp` | walk bbox로 자르고 높이 300, 4칸 가로 띠 | webp q82 |
| **캐릭터 시퀀스** | `…/%04d.png` | `char/<name>.webm` + `.mov` + `-poster.webp` + `char/sequences.json` | 고정 박스로 크롭 → **S = 0.5**(캔버스 px 2개가 출력 1px). 박스 w·h는 4의 배수라 결과가 짝수 | VP9 `-pix_fmt yuva420p -crf 40~46 -b:v 0 -auto-alt-ref 0 -row-mt 1` / HEVC `hevc_videotoolbox -alpha_quality 0.6 -q:v 30~35 -tag:v hvc1 -pix_fmt bgra -movflags +faststart` |
| 아이콘 | `check/packaging/appicon/icon-1024.png` | `brand/icon-{128,256}.webp`, `app/icon.png`, `app/apple-icon.png` | 128/256/512/180/32 | webp q90 / png(apple-icon은 #15172a로 평탄화) |
| 배지 | `v3/brand/appstore-badge-ko-black.svg` | 같은 이름 | — | **복사만** |

시퀀스 박스(캔버스 좌표 [x, y, w, h] → 출력 크기):

| 이름 | 원본 | 박스 | 출력 | 프레임 | VP9 crf / HEVC q | 실측 webm / mov |
|---|---|---|---|---|---|---|
| aing-idle | v4 idle_long | HERO [424,544,1308,1580] | 654×790 | 432 | 46 / 30 | 664KB / 782KB |
| aing-commute-start | v3 commute_start | HERO | 654×790 | 45 | 42 / 35 | ≈135 / ≈130KB |
| aing-poked | v3 poked | HERO | 654×790 | 90 | 42 / 35 | 296 / 275KB |
| aing-hit(선택) | v3 hit | HERO | 654×790 | 36 | 42 / 35 | ≈107 / ≈103KB |
| aing-face-left/right(선택) | v4 face_* | HERO | 654×790 | 108 | 44 / 32 | 162 / 197KB(각) |
| aing-ultra-charged | v4 ultra_charged | [452,1032,1228,1160] | 614×580 | 102 | 44 / 35 | ≈265 / ≈290KB |
| aing-ultra | v4 ultra_poked | [260,48,1680,1476](ultra 캔버스) | 840×738 | 165 | 46 / 30 | 757 / 762KB |

- **HERO 박스 하나를 같이 쓰는 이유**: idle·출근·때리기·콕·드래그 반응을 같은 박스, 같은 배율로 굽는다. 그러면 영상을 겹쳐 두고 보이기만 바꿔도 위치가 맞는다(좌표 계산 0). 박스는 6개 시퀀스 `alphaBBoxUnion` (430,548)-(1727,2118)의 합집합에 여백을 준 것이다. idle만 보면 위쪽 37%가 비지만, 투명 영역은 VP9에서 거의 공짜다. idle만 꽉 맞춘 480px판(872KB@crf42)과 HERO판(904KB@crf40)이 비슷했다.
- **이어 붙이기(앱 연속성 규칙)**: 모든 main 시퀀스의 0번은 idle 위상 262의 같은 자세다. 반응이 N프레임 동안 재생되면 idle_long의 (N mod 432)번에서 다시 시작한다. 그러면 부유와 살랑이 모두 맞는다. 클릭이 idle 중간에 들어오면 부유 위상이 최대 약 7px(출력 기준) 어긋난다. 반응 영상을 f6(동작 요청 프레임)부터 틀면 첫 움직임 속에 묻힌다.
- **말풍선·라벨 좌표**: 출력 px = (캔버스 px − 박스 원점) × S. 말풍선 그림자 상자는 (323−424, 981−544)×0.5 = **(−50.5, 218.5)**, 크기는 `bubbles.json`의 canvasPx × 0.5. 근무 라벨은 (787−424, 1686−544)×0.5 = **(181.5, 571)**, 264×120. 박스 바깥(음수 x)까지 나가므로 무대는 `overflow: visible`로 둔다. 시험 합성(`design/probe/hero_place.png`)이 앱 contact 시트의 배치와 같았다.

### 6.3 시퀀스 포맷 결정 — 근거(실측)

| 후보 | 조건 | 바이트 | 디코드 메모리 | 판정 |
|---|---|---|---|---|
| webp 스프라이트 | v3 idle 108f → 15fps 54f · 420px · q80 | 688KB(1장 3360×2779) | 34MB | ✗ 3.6초짜리가 무겁다 |
| 〃 | 같은 조건 q65 · alpha70 | 442KB | 34MB | △ |
| 〃 | idle_long 432f · 30fps · 480px | **4,121KB(시트 6장)** | **358MB** | ✗ 모바일 사파리 메모리 위험 |
| 〃 | poked 45f · 15fps · 420px | 370KB | 24MB | △ |
| VP9 알파 webm | idle_long 432f · 30fps · 654×790 · crf40 | 904KB | 디코더 버퍼뿐 | ○ |
| 〃 | crf46 | **664KB** | 〃 | **◎ 채택(데스크톱)** |
| 〃 | crf50 | 540KB | 〃 | ○(2배 확대에서 약간 무르다) |
| 〃 | 15fps 216f · crf44 | **358KB** | 〃 | **◎ 채택(모바일·Save-Data)** |
| HEVC 알파 mov | 30fps · q30 | 782KB | 〃 | **◎ 채택(사파리)** |
| 〃 | 15fps · q40 | 530KB | 〃 | ◎ 모바일 사파리 |

- 화질 확인: 같은 프레임(t=7.2s)의 얼굴을 2배 확대해 원본과 비교했다(`design/probe/out/cmp_face.png`). crf46과 crf50에서 눈 하이라이트·볼터치·가장자리 모두 유지됐다. VP9 알파는 ffmpeg libvpx 디코드로 투명 픽셀 수가 원본과 0.3% 안에서 같았다. HEVC 알파는 AVFoundation 포맷 설명에서 `ContainsAlphaChannel` 확장이 있는 것으로 확인했다. ffmpeg의 hevc 디코더는 알파 층을 버려서 그 방법으로는 검증할 수 없다.
- **브라우저 고르기는 `<source>` 순서로 하지 말고 JS로 한다.** 맥 크롬은 HEVC를 디코드하지만 알파를 버린다(검은 바탕). 사파리는 webm VP9를 재생하지만 알파를 버린다. 어느 쪽을 앞에 둬도 한쪽이 깨진다. 규칙은 이렇다.
  `isWebKit = /AppleWebKit/.test(ua) && !/Chrome|Chromium|Edg|OPR|Android/.test(ua) || /iP(hone|ad|od)/.test(ua)` → `.mov`, 아니면 `.webm`. 둘 다 실패하면(`error` 이벤트) 포스터에 머문다.
- 재생 정책: `muted playsinline loop`(반응은 loop 없이). 반응 영상은 `preload="auto"`로 미리 받아 0번에서 멈춰 둔다. `prefers-reduced-motion: reduce`이면 영상 src를 붙이지 않고 포스터만 쓴다. 클릭 반응은 말풍선 페이드만 남긴다. iOS 저전력 모드에서는 autoplay가 막히므로 포스터가 그대로 보이게 설계한다(재생 버튼 UI를 띄우지 않는다).
- 스프라이트를 남기는 곳은 **걷기 4포즈 띠**뿐이다(steps 애니메이션, 255KB).

### 6.4 폰트

| 안 | 내용 | 바이트(실측) |
|---|---|---|
| 원본 그대로 | Pretendard 정적 1웨이트 / Variable | 766~794KB / 2,058KB ✗ |
| KS X 1001 서브셋 | 2,350자 + ASCII | ExtraBold 171KB · Variable 442KB |
| **페이지 글자 서브셋(권장)** | 실제 문구 글자만(README 532자로 모의) | **ExtraBold 47KB** · Variable 132KB |

- 권장: 헤드라인만 Pretendard ExtraBold 페이지 서브셋(≈35~50KB, `next/font/local`, `display: swap`). 본문은 시스템 스택 `-apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Pretendard", system-ui, sans-serif`. 앱이 SF를 쓰고 방문자 대부분이 맥·아이폰이라 앱과 같은 글자가 0바이트로 나온다. 숫자·명령어는 `ui-monospace`(SF Mono).
- 서브셋은 빌드 전 스크립트로 문구에서 글자를 모아 `pyftsubset`(fonttools 4.51 + brotli 확인됨)으로 만든다. 문구가 바뀌면 다시 만들어야 하고, 안 그러면 빠진 글자가 시스템 글꼴로 섞인다.

---

## 7. 무게 예산

### 7.1 첫 화면(히어로, 크롬 / 사파리)

| 항목 | 바이트 |
|---|---|
| HTML + CSS | ≈25KB |
| JS(Next 15 런타임 + React + motion `LazyMotion domAnimation`) | ≈150~170KB(gzip) |
| 헤드라인 폰트 서브셋 | ≈40~50KB |
| `aing-idle-poster.webp`(LCP 후보, `fetchpriority="high"`) | 17KB |
| `aing-idle.webm` / `.mov` | 664KB / 782KB(모바일 15fps판 358 / 530KB) |
| `popover-off.webp` | 39KB |
| 메뉴바 라벨 2장 · 말풍선 · 근무 라벨 | ≈31KB |
| 아이콘 128 · 배지 SVG | 12KB |
| **합계** | **≈1.03MB / ≈1.15MB**(모바일 ≈0.7MB / ≈0.88MB) — 예산 1.5MB 이내 |

[근무 시작] 데모에 쓰는 `popover-on`(40KB) + `popover-tick-strip`(89KB) + `aing-commute-start`(≈135KB) = 264KB는 load 뒤 `requestIdleCallback`에서 미리 받는다(첫 화면 합계 밖).

### 7.2 나머지 절

| 절 | 항목 | 바이트 |
|---|---|---|
| 찌르기 | poke-list 43 · poke-row 4 · bubble 8 · aing-poked 296 | 351KB |
| 울트라·루비 | aing-ultra 757 · 포스터 21 · 말풍선 15 · ultra-charge 29 · aing-ultra-charged ≈265 · 포스터 17 | ≈1,104KB |
| 메시지 | message-thread 36 · popover-newmsg 41 · menubar newmsg 9 | 86KB |
| 기록·순위 | insights 46 · league 49 | 95KB |
| 게임 | minigame 35 · gomoku 39(모바일 18) | 74KB |
| 캐릭터 | still 6장 115 · character-pick 35 · (걷기 255 선택) | 150KB(+255) |
| 아이폰 | 화면 5장 ≈165 · 위젯 4장 54 | ≈219KB |
| 할 일 · CTA | todo-board 22 · icon-256 7 | 29KB |
| **나머지 합계** | | **≈2.1MB(+선택 255KB)** |

**전체 ≈ 1.03 + 0.26 + 2.1 ≈ 3.4~3.7MB**(크롬 기준, 걷기 포함 3.7MB). 사파리는 영상이 조금 더 커서 +≈0.15MB다. 선택 항목(드래그 face 2종 324KB, 3D 맥북 15포즈 384~510KB)을 다 넣어도 ≈4.4MB다. **예산 4.5MB(상한 6MB).** 소개 영상(≈7~9MB)은 클릭할 때만 받으므로 예산 밖이다.

로딩 순서: 포스터·글자 → (load) idle 영상 → (idle) 히어로 반응 → (IntersectionObserver, rootMargin 600px) 각 절의 영상과 이미지. 이미지는 `loading="lazy"` + 명시적 width·height를 준다. Vercel 이미지 최적화를 다시 타지 않게 `next/image unoptimized`(또는 `<img>`)를 쓴다. `public/` 파일은 해시가 붙지 않으므로 `vercel.json`의 headers에서 `/assets/(.*)`에 `Cache-Control: public, max-age=31536000, immutable`을 주고, 파일을 바꿀 때마다 이름에 `-v2` 같은 버전을 붙인다. `.mov`는 `Content-Type: video/quicktime`으로 나가는지 확인한다.

---

## 8. 3D 맥북 프레임 — 스크롤 연동 회전과 화면 합성

### 8.1 좌표계 해석(manifest + `src/v4/Laptop3D.tsx`, 시험 합성으로 검증)

- 캔버스 4800×4200px. 카메라는 z=75에서 −z를 보고, 초점 f=9000px(fovY 26.27°)이다. 투영식은 다음과 같다.
  `project(x,y,z) = (2400 + 9000·x/(75−z), 2100 − 9000·y/(75−z))`
- 회전 중심 GP = groupPosition (0, 2.5, 0)이고 이것이 화면 중심이다. `p' = GP + Rx(pitch)·Ry(yaw)·(p − GP)`(three.js Euler XYZ). 여기서 `x1 = cos(yaw)·vx + sin(yaw)·vz`, `z1 = −sin(yaw)·vx + cos(yaw)·vz`, `y' = cos(pitch)·vy − sin(pitch)·z1`, `z' = sin(pitch)·vy + cos(pitch)·z1`. yaw>0이면 화면이 보는 사람 오른쪽을 향하고, pitch>0이면 위에서 내려다보는 각도가 된다.
- `screenCorners3D`(TL, TR, BR, BL)는 x ±9.9186, y 8.6991 / −3.6991, z 0이다. 화면 내용 좌표계는 **1440×900pt**(16:10)다. 유리는 비율 1.6132라, 높이 맞춤으로 가운데 두면 좌우 5.91pt씩 검정 여백이 남는다(`glassRect` [−5.91, 0, 1451.82, 900]). clip은 유리 사각형 + `clipGrow` 8pt다.
- 투영한 네 귀(실측): 포즈 (0,0) = (1210,1056)·(3590,1056)·(3590,2544)·(1210,2544) → 화면 2380×1488px. (yaw −9, pitch +3) = (1243,1064)·(3606,1040)·(3595,2560)·(1253,2523).
- 프레임 위치: `samples[pi·29 + yi]` = [lid crop x,y,w,h · lid bbox · base crop x,y,w,h · base bbox](캔버스 px). 여기서 `pi = (pitch+9)/1.5`, `yi = (yaw+21)/1.5`. lid webp는 (lidCropX, lidCropY)에, base는 (baseCropX, baseCropY)에 그대로 놓는다. **쌓는 순서: 화면 내용 → lid(화면 구멍 알파 0) → base.**
- 화면 내용 사상: 1440×900 사각형 → 네 귀 사변형을 Heckbert 닫힌 식 호모그래피로 바꾸고 CSS `matrix3d`로 적용한다. `quadHomography`·`css3d` 함수가 `aing-check-promo/src/v4/Laptop3D.tsx`에 있으니 그대로 옮긴다. 이 방식으로 PIL 시험 합성(`design/probe/laptop_m9_p3.png`)을 했고 베젤 안에 정확히 맞았다.
- 표시 배율 k(CSS px / 캔버스 px)일 때는 모든 좌표에 k를 곱한다. 정면 화면 폭은 2380·k다(k 0.3이면 714 CSS px).

### 8.2 가져올 양

| 방식 | 각도 | 파일 | 크기 | 바이트 |
|---|---|---|---|---|
| **권장** | pitch +3.0 고정 · yaw −21~+21 **3° 간격 15포즈** | lid·base 30장(K 0.5 사전 축소, webp q82) | 예: 정면 lid 1281×910 · base 1563×397 | **384KB** |
| 합친 판 | 같은 15포즈, lid+base를 고정 상자(캔버스 (374,886)-(4426,3618))에 합침 | 15장 2026×1366 | 상자가 같아 원점 계산이 필요 없다 | 510KB |
| 부드럽게 | 1.5° 간격 29포즈 | 58장 | 〃 | ≈740KB |

- 스크롤 진행도는 **가장 가까운 격자 각도로 스냅**한다. 화면 내용도 같은 스냅 각도의 호모그래피로 그린다(뚜껑은 이산적인데 화면만 연속이면 어긋난다). 3° 간격이 계단처럼 보이면 이웃 두 포즈를 120ms 교차 페이드하거나 1.5° 간격으로 바꾼다.
- **사용 판단(사용자 확인 필요)**: 화면에 무엇을 띄울지가 문제다. 실제 앱은 메뉴바에서 팝오버가 떨어지는 모습인데, 화면을 채우려면 메뉴바와 바탕화면을 흉내 내야 한다. 이건 사용자가 금지한 "가짜 데스크톱 흉내"다. 쓴다면 화면 = 단색 네이비(#1b1e2e) + 실제 메뉴바 라벨 한 개 + 실제 팝오버 한 장으로만 하고, 다른 메뉴 항목·월페이퍼·창은 그리지 않는다. 그래도 걸리면 **맥북을 빼고 팝오버를 맨몸으로 띄우는 편이 사용자 취향에 맞다.**
- 3D 아이폰(`phone3d`)은 같은 방식(카메라 3840×2160, f 2607.35, z 23, 격자 yaw ±60 / 1.5°, pitch ±20 / 2°, 1701장)이지만 **MockupSnap GLB 라이선스 불명으로 쓰지 않는다.**

---

## 9. 아이폰 — 코드로 그린 셸 + 다크 스크린샷

- 화면 비율은 1206:2622 = **402:874pt**(iPhone 17 Pro)다. `<img>`는 600×1304로, 셸 폭 300 CSS px 기준이다.
- 셸 치수(화면 폭 W 기준 비율): MockupSnap 16 Pro 실측값(Aingo `public/phone/README.md`: 화면 710px에 반경 112, 베젤 약 25, 아일랜드 220×64 @ y+25)을 비율로만 옮겼다. 그림은 가져오지 않는다.
  - 화면 모서리 반경 = **0.155·W**(402pt에서 약 62pt)
  - 베젤 두께 = **0.035·W**, 셸 바깥 반경 = 화면 반경 + 베젤
  - 셸 색 #0a0a0c, 바깥 1px 테두리 rgba(255,255,255,.10), 안쪽 1px 하이라이트 rgba(255,255,255,.06). 측면 버튼은 그리지 않는다(템플릿 티가 난다)
  - **다이내믹 아일랜드는 CSS로 덮는다.** 폭 0.315·W(126pt), 높이 0.093·W(37pt), 화면 위에서 0.028·W(11pt), 완전 둥근 검정. 스틸에 아일랜드가 없어서 덮어야 한다(ios manifest known). 상태 막대 14:05와 아이콘이 이미 아일랜드 좌우 자리에 있다.
  - 구현: `div.shell(padding: bezel; border-radius: outer) > div.screen(border-radius: inner; overflow: hidden) > img + div.island`. 화면 가장자리 2~5px은 원래 안 보이는 영역이다(uvVisible). 그래서 `img`를 1% 키워 `object-fit: cover`로 두면 모서리 틈이 생기지 않는다.
- **다크를 고르는 근거**
  1. 사용자 요구가 "다크 계열 색감"이다. 라이트 스크린샷(#f2f2f7 바탕)은 다크 페이지에서 흰 판으로 튀어 LCP 영역의 시선을 빼앗는다.
  2. 맥 팝오버는 다크다(배경 #1d202b~#232431, 카드 #2b2e3d). 폰 다크(바탕 #1a1c26 근처)와 같은 계열이라 맥과 폰이 한 제품으로 읽힌다.
  3. 다크는 앱에 실제로 있는 화면 모드라(나 → 설정 → 화면 모드) "앱에 없는 상태"가 아니다.
  4. 위젯도 다크판이 페이지 위에서 카드처럼 앉는다.
- 폰 절의 인터랙션: aingo처럼 스티키 스크롤에서 화면 교체(now → messages → rankings-league → games → me)를 할 수 있다. 같은 크기·같은 상태 막대라 교차 페이드만으로 자연스럽다. 메시지 흐름(`conv-gureum_arrived → sent1 → read`)은 '1' 한 칸만 다른 판이라 클릭 데모에 맞는다.

---

## 10. 실제 색 샘플(스크린샷에서 직접 뽑음)

| 요소 | 값 | 출처 |
|---|---|---|
| 팝오버 바탕 | #1d202b ~ #232431 | popover_main_working 가장자리·레일 사이 |
| 카드 | **#2b2e3d**(헤더 카드 #2c303e) | 카드 안쪽(매니페스트 값과 일치) |
| 진행 바 | **#54abff**, 트랙 #20222c | 헤더 진행 바 |
| 근무중 글자 | **#59e0a1** | 헤더 '근무중' |
| 근무중 배지 | #52c692, 칩 바탕 #324b4d | 팀 행 · '5명 근무중' |
| [근무 시작] | #4ed395 → #32b49d | popover_off 버튼 양끝 |
| [근무 종료] | #fd9952 → #f76763 | popover_working 버튼 양끝 |
| 아잉 몸 | #b8a5fe(그늘) · #e4d6fa(하이라이트) | 헤더 초상 |
| 앱 아이콘 | 바탕 #131026 · 링 #3da0ff(파랑) → #8060ff(보라) | icon-1024 |
| 폰 바탕 | #1a1c26 근처 | now_dark |

참고로 프로모 팔레트(mint 89,224,161 · sky 84,171,255 · lavender 184,140,255)가 앱 실측값과 같다. aingo의 #0b0818 계열 바탕과 앱 아이콘 바탕 #131026은 같은 가족이다.

---

## 11. 위험

1. **알파 영상 브라우저 판별**: §6.3의 JS 규칙이 틀리면 크롬 맥에서 검은 사각형이 뜬다. 파이어폭스의 VP9 알파는 실기에서 확인해야 한다. 안 되면 포스터로 떨어지게 해 둔다.
2. **iOS 저전력 모드·감속 모션**에서는 영상이 안 돈다. 포스터만으로도 완결된 화면이어야 한다.
3. **스크린샷 버전 차이**: 맥 소재는 0.3.38, 현행은 0.3.47이다. 0.3.47의 AI 리밋(맥별 보기) 등 최근 기능은 그림이 없다. 아이폰 소재는 1.0.1(빌드 9), 현행은 1.0.5(빌드 15)다. 그 사이 화면이 바뀌었으면 "사실만" 원칙에 걸리므로 출시 전에 현행 앱과 눈으로 대조해야 한다. 재렌더 하네스는 각 manifest의 `how_to_rerun`에 있다.
4. **인물 세트 섞임**: 앱스토어 스크린샷과 v1~v3 소재에는 옛 이름이 남아 있다. v4 세트(새벽·구름빵·달토끼·호두과자·민트별·보리차·솜사탕·초코칩)만 쓴다.
5. **3D 맥북 = 가짜 데스크톱 위험**(§8). 3D 폰과 MockupSnap은 라이선스 불명이라 쓰지 않는다.
6. **폰트 서브셋 누락**: 문구를 고친 뒤 서브셋을 다시 만들지 않으면 빠진 글자가 다른 글꼴로 섞인다.
7. **DMG 링크가 아직 안 올라갔을 수 있다**(오늘 밤 업로드 중). 1차 CTA 옆에 brew 명령과 Releases(zip) 링크를 함께 둔다. 데브서버에서 404가 나도 막히지 않게 한다.
8. **QR payload에 `/kr/`가 붙어 있다.** 쓴다면 지역 없는 URL로 다시 만든다.
9. **울트라 떨림**: 12.5Hz 떨림이 30fps에서 맥놀이처럼 보인다(앱도 같은 한계). 5초 흔들림은 감속 모션 사용자에게 포스터로 대체한다. 자동 재생이 아니라 스크롤 진입이나 버튼으로 트리거하는 편이 안전하다.
10. **인코딩 환경 의존**: HEVC 알파는 macOS videotoolbox에서만 만들 수 있다. 결과물을 커밋해 Vercel 빌드와 분리한다. Remotion 동봉 ffmpeg는 필터 축소판이라 짝수 크기를 sharp에서 맞춘다.
11. **가상 수치가 눈에 띈다**: 팝오버의 "9월 AI 토큰 소모량 2,376,382,712"는 가상 값이지만 숫자가 커서 시선을 끈다. 순위 절에 같은 인물·같은 값(구름빵 50.1억 등)이 나오므로 서로 어긋나지 않게 같은 판끼리 쓴다.
12. **public 파일 캐시**: 해시가 없으니 바꿀 때 파일 이름에 버전을 붙인다. `.mov` MIME도 확인한다.

// components/features/scenes.data.ts — v2.1 장면 6개(brief-v21 §3 표를 그대로 옮긴 상수 · scenes 소유).
// 사용자가 꼽은 핵심 기능 6개만 말한다: 근무 타이머 · 토큰 사용량·리밋 · 메신저 · 근무 리듬·잔디 · 미니게임 · 아이폰·맥 연동.
// 장면마다 라벨(t-kicker) · 제목 2박자(CB ` / ` 위치 — 없으면 쉼표 뒤) · 문장 1개(CB 문장 글자 그대로). H4·둘째 단락 없음
// (장면 6 의 "근무 시작·종료는 맥에서 해요." 만 예외 — 사실 오해 방지, brief-v21 §2).
//
// 렌더는 전부 public/assets 의 '통째 패널'(크롭·페이드·노치 0 — 창은 --r-window + --shadow-window 그대로). 좌표 = 690 폭 캔버스 px
// (x, y, w, h) — 1440 에서 렌더 영역 46–94%(662–1352) 에 배율 1, 1024 는 .71, tab 은 폭에 맞춤(FeatureRow). 높이는 원본 비율 그대로.
// 센터 배지(서울/부산)가 든 패널(token-month · league · minigame)은 표시 배율 ≤ .5(828 → ≤ 414 — CB:293 '크게 보이지 않는 크롭').
// 렌더 상자끼리 겹치지 않는다(교체 짝 제외). 선은 트렁크 1 + 가지 1(장면 1 은 라벨 → 팝오버 트렁크 하나).
// 타임라인(문턱 t=0, ms — SPEC §S4 4.1): 노드 점등 0 → 트렁크 0–200 → 빈 창 120 → 내용 440 → 가지 600 → 보조 700.
// 직렬화 가능한 값만(server Scenes → client FeatureRow).
import { ALT, ROW_TIMING, type AssetKey } from '@/data/fixtures';
import type { FeatureRowProps } from '@/components/features/FeatureRow';

/** alt 문구(SPEC §6.5 식 · fixtures ALT). 장식은 엔진이 alt="" 로 그린다. */
const alt = (k: AssetKey): string => ALT[k] ?? '';

/** 공통 타임라인(SPEC §S4 4.1). */
const AT = { trunk: 0, main: 120, branch: 600, child: 700 } as const;

/** 원본 px → 표시 높이(폭 w 에 맞춘 원본 비율, 소수 반올림). */
const fit = (w: number, srcW: number, srcH: number): number => Math.round((w * srcH) / srcW);

export type SceneProps = Omit<FeatureRowProps, 'mode' | 'railStart'>;

/** 장면 1 `#f-timer` — 근무 타이머. 제목 CB:81 · 문장 CB:82 첫 문장.
 *  주 렌더 = 근무 중 팝오버(828×1306 → 372, .45×) · 보조 = 그 위 메뉴바 라벨(463×132 → 높이 40). 트렁크 = 라벨 → 팝오버(메뉴바에서 내려오는 창). */
const TIMER_POPOVER_H = fit(372, 828, 1306); // 587
export const S1: SceneProps = {
  id: 'f-timer',
  kicker: '근무 타이머',
  title: ['근무 시작.', '버튼 하나, 메뉴바에서.'],
  body: '메뉴바에서 근무 시작을 누르면 오늘 누적 시간이 흘러요.',
  canvas: {
    height: 76 + TIMER_POPOVER_H,
    items: [
      { kind: 'main', asset: 'ui/popover-working', alt: alt('ui/popover-working'), box: [159, 76, 372, TIMER_POPOVER_H], at: AT.main },
      // 라벨은 팝오버 가운데 위(앱이 상태바 항목 아래로 창을 내리는 자리). phone 에서도 주 렌더 위에
      { kind: 'child', asset: 'ui/menubar-0000-lg', alt: alt('ui/menubar-0000-lg'), box: [275, 0, 140, 40], at: 360, stack: { w: 140, before: true } },
    ],
    wires: [{ d: 'M 345 40 V 76', at: AT.trunk }],
  },
};

/** 장면 2 `#f-tokens` — AI 토큰·리밋. 제목 CB:154 ✓v4 · 문장 CB:156(리밋 — 사용자의 핵심 2번) 첫 문장.
 *  주 렌더 = 이번 달 토큰판(828×1364 → 360, .43×) · 보조 = 팀별 리그(828×1200 → 300, .36×) — 두 창 나란히, 뒤 창은 살짝 아래.
 *  선: 두 창 사이 위의 접합점에서 트렁크(→ 토큰판 윗변 가운데) · 가지(→ 리그 윗변 가운데). */
const TOKEN_H = fit(360, 828, 1364); // 593
const LEAGUE_H = fit(300, 828, 1200); // 435
export const S2: SceneProps = {
  id: 'f-tokens',
  kicker: 'AI 사용량',
  title: ['이번 달 AI 토큰,', '전체 순위판.'],
  body: '5시간·주간 리밋이 얼마나 찼는지도 메뉴바에서 바로 보이고, 아이폰과 위젯에서도 봐요.',
  canvas: {
    height: 40 + TOKEN_H,
    items: [
      { kind: 'junction', point: [375, 14], at: AT.trunk },
      { kind: 'main', asset: 'ui/token-month', alt: alt('ui/token-month'), box: [0, 40, 360, TOKEN_H], at: AT.main },
      { kind: 'child', asset: 'ui/league', alt: alt('ui/league'), box: [390, 150, 300, LEAGUE_H], at: AT.child, stack: { w: 300 } },
    ],
    wires: [
      { d: 'M 375 14 H 180 V 40', at: AT.trunk }, // 트렁크: 접합점 → 토큰판 윗변 가운데
      { d: 'M 375 14 H 540 V 150', at: AT.branch }, // 가지: 접합점 → 리그 윗변 가운데
    ],
  },
};

/** 장면 3 `#f-message` — 메시지. 제목 CB:114 ✓v4 · 문장 CB:116 앞 두 문장.
 *  주 렌더 = 1:1 메시지(828×1206 → 372, .45×), 조립 1.5s 뒤 읽음 판으로 교체(내 말 옆 "1"이 사라진다 — 한 번) · 보조 = 말풍선(창 오른쪽 바깥).
 *  선: 창 위 접합점 → 트렁크(창 윗변) · 가지(창 오른쪽 → 말풍선 윗변). */
const MESSAGE_H = fit(372, 828, 1206); // 542
export const S3: SceneProps = {
  id: 'f-message',
  kicker: '콕 / 메시지',
  title: ['하고 싶은 말은,', '메시지로.'],
  body: '할 말은 1:1 메시지로 보내요. 상대가 읽으면 옆의 1이 사라져요.',
  canvas: {
    height: 40 + MESSAGE_H,
    items: [
      { kind: 'junction', point: [246, 12], at: AT.trunk },
      {
        kind: 'main',
        asset: 'ui/message-unread',
        alt: alt('ui/message-unread'),
        box: [60, 40, 372, MESSAGE_H],
        at: AT.main,
        swapTo: { asset: 'ui/message-read', alt: alt('ui/message-read'), at: ROW_TIMING.swapAtMs },
      },
      // "구름빵님: 커피 한잔 해요 ☕️" — 창 곁(겹치지 않게), 문구는 BUBBLE_TEXT 원문(aria-hidden)
      { kind: 'bubble', bubble: 'message-gureum', box: [470, 330, 190, 77], at: AT.child, stack: { w: 190 } },
    ],
    wires: [
      { d: 'M 246 12 V 40', at: AT.trunk }, // 트렁크: 접합점 → 창 윗변 가운데
      { d: 'M 432 290 H 565 V 330', at: AT.branch }, // 가지: 창 오른쪽 → 말풍선 윗변 가운데
    ],
  },
};

/** 장면 4 `#f-rhythm` — 근무 리듬·잔디. 제목 CB:143 ✓v4(12주가 든 2박자) · 문장 CB:144 의 '12주' 문장.
 *  주 렌더 = 내 기록(828×1390 → 372, .45× — 지난주 회고·근무 리듬·12주 근무 잔디) · 보조 = 12주 AI 토큰 잔디(912×519 → 290), 창 오른쪽 아래. */
const INSIGHTS_H = fit(372, 828, 1390); // 624
const GRASS_H = fit(290, 912, 519); // 165
export const S4: SceneProps = {
  id: 'f-rhythm',
  kicker: '기록',
  title: ['12주 잔디,', '지난주 리듬.'],
  body: '최근 12주의 근무와 AI 토큰은 잔디로 쌓여요.',
  canvas: {
    height: 40 + INSIGHTS_H,
    items: [
      { kind: 'junction', point: [186, 12], at: AT.trunk },
      { kind: 'main', asset: 'ui/insights-popover', alt: alt('ui/insights-popover'), box: [0, 40, 372, INSIGHTS_H], at: AT.main },
      { kind: 'child', asset: 'ui/grass-token-final', alt: alt('ui/grass-token-final'), box: [400, 460, 290, GRASS_H], at: AT.child, stack: { w: 300 } },
    ],
    wires: [
      { d: 'M 186 12 V 40', at: AT.trunk }, // 트렁크: 접합점 → 창 윗변 가운데
      { d: 'M 372 410 H 545 V 460', at: AT.branch }, // 가지: 창 오른쪽 → 잔디 윗변 가운데
    ],
  },
};

/** 장면 5 `#f-games` — 미니게임. 제목 CB:169 · 문장 CB:170 첫 문장.
 *  주 렌더 = 미니게임 창(1400×779 → 560, .4× — 순위 아바타의 작은 배지는 허용 범위) · 보조 = 작은 오목 판(700×778 → 150, 판돈 글자 없음), 오른쪽 위.
 *  선: 접합점에서 트렁크(↓ 게임 창 윗변) · 가지(→ 오목 판 왼쪽 가운데) — T 자. */
const GAME_H = fit(560, 1400, 779); // 312
const BOARD_H = fit(150, 700, 778); // 167
export const S5: SceneProps = {
  id: 'f-games',
  kicker: '쉬는 시간',
  title: ['한 판,', '쉬어 가기.'],
  body: '타이밍 바·플래피 아잉·테트리스로 오늘 순위에 도전해요.',
  canvas: {
    height: 200 + GAME_H,
    items: [
      { kind: 'junction', point: [280, 84], at: AT.trunk },
      { kind: 'main', asset: 'ui/minigame', alt: alt('ui/minigame'), box: [0, 200, 560, GAME_H], at: AT.main },
      { kind: 'child', asset: 'ui/gomoku-board-sm', alt: alt('ui/gomoku-board-sm'), box: [540, 0, 150, BOARD_H], at: AT.child, stack: { w: 150 } },
    ],
    wires: [
      { d: 'M 280 84 V 200', at: AT.trunk }, // 트렁크: 접합점 → 게임 창 윗변 가운데
      { d: 'M 280 84 H 540', at: AT.branch }, // 가지: 접합점 → 오목 판 왼쪽 가운데
    ],
  },
};

/** 장면 6 `#f-iphone` — 아이폰·맥 연동. 제목 CB:182 ✓v4 · 문장 CB:183 첫 문장 + 작은 줄 CB:185.
 *  주 렌더 = PhoneShell(화면 240 → 셸 ≈257×539) + 아이폰 지금 탭 · 보조 = 내 오늘 위젯(340×340 → 170), 폰 오른쪽.
 *  선: 폰 위 접합점 → 트렁크(폰 윗변) · 가지(폰 오른쪽 → 위젯 왼쪽 가운데). */
const PHONE_W = 257; // phoneShellMetrics(240).shellW = 256.8
const PHONE_H = 539; // phoneShellMetrics(240).shellH = 538.6
export const S6: SceneProps = {
  id: 'f-iphone',
  kicker: 'iPhone',
  title: ['이제,', '아이폰에서도.'],
  body: '맥에서 켠 근무가 폰에서도 보여요.',
  note: '근무 시작·종료는 맥에서 해요.',
  canvas: {
    height: 40 + PHONE_H,
    items: [
      { kind: 'junction', point: [228, 12], at: AT.trunk },
      { kind: 'phone', screen: 'ios/now', alt: alt('ios/now'), box: [100, 40, PHONE_W, PHONE_H], screenWidth: 240, at: AT.main },
      { kind: 'child', asset: 'ios/widget-today-small', alt: alt('ios/widget-today-small'), box: [450, 225, 170, 170], at: AT.child, stack: { w: 150 } },
    ],
    wires: [
      { d: 'M 228 12 V 40', at: AT.trunk }, // 트렁크: 접합점 → 폰 윗변 가운데
      { d: 'M 357 310 H 450', at: AT.branch }, // 가지: 폰 오른쪽 → 위젯 왼쪽 가운데
    ],
  },
};

/** 문서 순서(섹션 id 순서 = brief-v21 §1: top, f-timer, f-tokens, f-message, f-rhythm, f-games, f-iphone, install, faq, outro). */
export const SCENES: readonly SceneProps[] = [S1, S2, S3, S4, S5, S6];

// components/features/scenes.data.ts — 핵심 기능 6장면의 렌더 구성(docs/v3/brief.md §4.4). 문구는 copy.ts(§8 글자 그대로).
// 렌더 짝은 v2.1 장면 그대로(와이어·노드·조립 타임라인은 버렸다). 예외 하나: 장면 1 은 근무 중 팝오버(03:45 — 히어로가 이미 크게
// 보여 준다) 대신 근무 시작 직후 팝오버(00:00)를 쓴다 — 위에 얹는 메뉴바 라벨(00:00)과 시각이 맞고, 첫 화면 그림을 되풀이하지 않는다.
//
// 좌표 = 구성 px(x, y, w, h) — 구성을 '가장 크게' 보일 때의 CSS px. 무대가 작으면 구성 전체가 같은 비율로 줄어든다(FeatureStage).
// 배율 바닥: 팝오버류 ≤ .5(828 → ≤ 414) · 센터 배지 든 패널(token-month · league · minigame) ≤ .5. 렌더는 통째(크롭·마스크·페이드 0),
// 상자끼리 겹치지 않는다(메시지의 읽음 판 교체 짝만 같은 자리 — 맥 패널·아이폰 화면 둘 다). frame = 창 모서리(10px — 렌더 바깥 여백에만 닿는다) + 그림자,
// 알파가 구워진 렌더(메뉴바 라벨·말풍선·위젯)는 frame 없음.
// 폰(< 768)은 구성 대신 세로 묶음: po 순서로 쌓고 폭 = min(100%, pw). 장면 하나가 화면 높이 1.5배(390×844 → 1,266px)를 넘지 않게 pw 를 고른다(§9.4.5).
//   pair = 폰에서 두 칸 나란히(작은 판 둘) · phoneHide = 폰에서 생략(같은 사실을 다른 렌더가 보여 줄 때).
// v3.1(§9.1 · §9.5): f-tokens = AI 리밋 카드(주인공) + 이번 달 토큰 순위 · f-games = 테트리스·플래피 창 + 체스·오목 판(2×2) ·
//   f-iphone = 폰 + AI 리밋 미디움 위젯 + 내 오늘 스몰 위젯.
import { ALT, type AssetKey } from '@/data/fixtures';
import { FEATURE_COPY, type FeatureCopy, type FeatureId } from './copy';

export type Box = readonly [x: number, y: number, w: number, h: number];

export type CompItem =
  | {
      kind: 'img';
      asset: AssetKey;
      alt: string;
      box: Box;
      frame: boolean;
      /** 폰 세로 묶음: 폭 상한(px) · 순서 */
      pw: number;
      po: number;
      /** 같은 자리에서 스크롤로 바뀌는 짝(메시지 안 읽음 → 읽음). 고정 무대에서만 */
      swap?: { asset: AssetKey; alt: string };
      /** 폰 묶음에서 다음(또는 앞) pair 항목과 두 칸 나란히 */
      pair?: boolean;
      /** 폰 묶음에서 생략 */
      phoneHide?: boolean;
    }
  | {
      kind: 'phone';
      screen: AssetKey;
      alt: string;
      box: Box;
      pw: number;
      po: number;
      /** 같은 자리에서 스크롤로 바뀌는 화면(메시지 안 읽음 → 읽음 — 맥 패널과 함께). 고정 무대에서만 */
      swap?: { screen: AssetKey; alt: string };
    };

export interface Composition {
  w: number;
  h: number;
  items: readonly CompItem[];
}

export interface Scene extends FeatureCopy {
  comp: Composition;
}

const alt = (k: AssetKey): string => ALT[k] ?? '';
/** 원본 px → 폭 w 에 맞춘 높이(원본 비율, 반올림). */
const fit = (w: number, srcW: number, srcH: number): number => Math.round((w * srcH) / srcW);

/** 아이폰 셸(화면 402:874 · 베젤 .035W — components/ui/PhoneShell 과 같은 비율). 화면 폭 W → 셸 폭·높이. */
export const PHONE = { ratio: 874 / 402, bezel: 0.035 } as const;
export const phoneShell = (screenW: number) => ({
  w: Math.round(screenW * (1 + 2 * PHONE.bezel) * 10) / 10,
  h: Math.round((screenW * PHONE.ratio + 2 * PHONE.bezel * screenW) * 10) / 10,
});

// 장면 1 — 타이머: 메뉴바 라벨(463×132 → 140) 바로 아래로 떨어진 팝오버(828×1306 → 372, .45×).
const POP_H = fit(372, 828, 1306); // 587
const S1: Composition = {
  w: 372,
  h: 40 + 14 + POP_H,
  items: [
    { kind: 'img', asset: 'ui/menubar-0000-lg', alt: alt('ui/menubar-0000-lg'), box: [116, 0, 140, 40], frame: false, pw: 140, po: 0 },
    { kind: 'img', asset: 'ui/popover-on', alt: alt('ui/popover-on'), box: [0, 54, 372, POP_H], frame: true, pw: 340, po: 1 },
  ],
};

// 장면 2 — AI 사용량(v3.1 §9.1): AI 리밋 카드(1020×417 → 440 — 주인공, 1440×900 무대에서 배율 1 = 440 css · 1280×800 에서 400) 왼쪽 ·
// 이번 달 토큰 순위(828×1364 → 280, .34×) 오른쪽.
// 카드는 토큰판 세로 가운데. league(팀별 이번 주)는 이 장면에서 뺐다. 폰: 카드(폭 맞춤) → 토큰판.
const LIMITS_W = 440;
const LIMITS_H = fit(LIMITS_W, 1020, 417); // 180
const TOKEN_W = 280;
const TOKEN_H = fit(TOKEN_W, 828, 1364); // 461
const S2: Composition = {
  w: LIMITS_W + 24 + TOKEN_W, // 744
  h: TOKEN_H,
  items: [
    {
      kind: 'img',
      asset: 'ui/ai-limits-card',
      alt: alt('ui/ai-limits-card'),
      box: [0, Math.round((TOKEN_H - LIMITS_H) / 2), LIMITS_W, LIMITS_H],
      frame: true,
      pw: 360,
      po: 0,
    },
    { kind: 'img', asset: 'ui/token-month', alt: alt('ui/token-month'), box: [LIMITS_W + 24, 0, TOKEN_W, TOKEN_H], frame: true, pw: 300, po: 1 },
  ],
};

// 장면 3 — 메시지(v3.1 §9.1): 맥 1:1 메시지(828×1206 → 372, .45×) + 아이폰 셸 안 같은 구름빵 대화(화면 228 → 셸 ≈ 244×512),
// 폰은 오른쪽 · 아랫변을 맞춘다. 장면 안에서 스크롤이 60% 를 넘으면 둘 다 읽음 판으로(내 말 옆 '1'이 사라진다). 말풍선은 뺐다(같은 말을 폰이 보여 준다).
// 흐름(태블릿·폰·감속)에서는 교체 없이 처음 판(안 읽음 1)끼리 짝 — 맥과 폰이 같은 순간을 보인다.
const MSG_H = fit(372, 828, 1206); // 542
const MSG_PHONE = phoneShell(228); // 244 × 511.7
const S3: Composition = {
  w: 372 + 40 + Math.round(MSG_PHONE.w),
  h: MSG_H,
  items: [
    {
      kind: 'img',
      asset: 'ui/message-unread',
      alt: alt('ui/message-unread'),
      box: [0, 0, 372, MSG_H],
      frame: true,
      pw: 300,
      po: 0,
      swap: { asset: 'ui/message-read', alt: alt('ui/message-read') },
    },
    {
      kind: 'phone',
      screen: 'ios/conv-gureum-sent',
      alt: alt('ios/conv-gureum-sent'),
      box: [372 + 40, Math.round((MSG_H - MSG_PHONE.h) * 10) / 10, MSG_PHONE.w, MSG_PHONE.h],
      pw: 206,
      po: 1,
      swap: { screen: 'ios/conv-gureum-read', alt: alt('ios/conv-gureum-read') },
    },
  ],
};

// 장면 4 — 기록: 내 기록(828×1390 → 372, .45× — 지난주 회고·근무 리듬·12주 근무 잔디) + 12주 AI 토큰 잔디(912×519 → 290), 오른쪽 아래.
const INS_H = fit(372, 828, 1390); // 624
const GRASS_H = fit(290, 912, 519); // 165
const S4: Composition = {
  w: 372 + 32 + 290,
  h: INS_H,
  items: [
    { kind: 'img', asset: 'ui/insights-popover', alt: alt('ui/insights-popover'), box: [0, 0, 372, INS_H], frame: true, pw: 340, po: 0 },
    { kind: 'img', asset: 'ui/grass-token-final', alt: alt('ui/grass-token-final'), box: [404, 404, 290, GRASS_H], frame: true, pw: 320, po: 1 },
  ],
};

// 장면 5 — 게임(v3.1 §9.1 — 네 개): 2×2. 왼쪽 열(글자 든 판, 크게) = 1:1 테트리스 두 판(사용자 지정 크롭 1200×865 → 500 — §9.5 마지막 줄) 위 ·
// 플래피 창(1400×779 → 500) 아래, 오른쪽 열(판, 작게) = 체스 판(700 → 220) · 오목 판(700×778 → 220) — 판은 옆 창의 세로 가운데.
// 1440×900 무대에서 배율 1(744×658). 폰: 테트리스·플래피 폭 맞춤 → 체스·오목 판 두 칸 나란히(pair).
const G_LW = 500;
const G_RW = 220;
const TETRIS_H = fit(G_LW, 1200, 865); // 360
const FLAPPY_H = fit(G_LW, 1400, 779); // 278
const CHESS_H = G_RW; // 220
const GOMOKU_H = fit(G_RW, 700, 778); // 245
const G_GAP = 20;
const S5: Composition = {
  w: G_LW + 24 + G_RW,
  h: TETRIS_H + G_GAP + FLAPPY_H,
  items: [
    { kind: 'img', asset: 'ui/tetris-duel', alt: alt('ui/tetris-duel'), box: [0, 0, G_LW, TETRIS_H], frame: true, pw: 360, po: 0 },
    { kind: 'img', asset: 'ui/minigame', alt: alt('ui/minigame'), box: [0, TETRIS_H + G_GAP, G_LW, FLAPPY_H], frame: true, pw: 360, po: 1 },
    {
      kind: 'img',
      asset: 'ui/chess-board',
      alt: alt('ui/chess-board'),
      box: [G_LW + 24, Math.round((TETRIS_H - CHESS_H) / 2), G_RW, CHESS_H],
      frame: true,
      pw: 180,
      po: 2,
      pair: true,
    },
    {
      kind: 'img',
      asset: 'ui/gomoku-board-sm',
      alt: alt('ui/gomoku-board-sm'),
      box: [G_LW + 24, TETRIS_H + G_GAP + Math.round((FLAPPY_H - GOMOKU_H) / 2), G_RW, GOMOKU_H],
      frame: true,
      pw: 180,
      po: 3,
      pair: true,
    },
  ],
};

// 장면 6 — 아이폰(v3.1 §9.1): 아이폰 셸 + 지금 탭(화면 264 → 셸 ≈ 283×592) · 오른쪽 열 = AI 리밋 미디움 위젯(728×340 → 330) 위 ·
// 내 오늘 스몰 위젯(340 → 154 — 미디움과 같은 pt 배율: 170pt ÷ 364pt × 330) 아래 왼쪽 정렬, 열은 폰 세로 가운데.
// 폰: 셸 → 미디움(폭 맞춤). 스몰은 생략(폰 화면이 같은 3:45:00 을 보여 준다 — §9.1).
const SHELL = phoneShell(264);
const W_X = Math.round(SHELL.w) + 44;
const MED_W = 330;
const MED_H = fit(MED_W, 728, 340); // 154
const SMALL = Math.round((MED_W * 170) / 364); // 154
const W_TOP = Math.round((SHELL.h - (MED_H + 20 + SMALL)) / 2);
const S6: Composition = {
  w: W_X + MED_W,
  h: Math.round(SHELL.h),
  items: [
    { kind: 'phone', screen: 'ios/now', alt: alt('ios/now'), box: [0, 0, SHELL.w, SHELL.h], pw: 250, po: 0 },
    {
      kind: 'img',
      asset: 'ios/widget-limits-medium',
      alt: alt('ios/widget-limits-medium'),
      box: [W_X, W_TOP, MED_W, MED_H],
      frame: false,
      pw: 360,
      po: 1,
    },
    {
      kind: 'img',
      asset: 'ios/widget-today-small',
      alt: alt('ios/widget-today-small'),
      box: [W_X, W_TOP + MED_H + 20, SMALL, SMALL],
      frame: false,
      pw: 170,
      po: 2,
      phoneHide: true,
    },
  ],
};

const COMPS: Record<FeatureId, Composition> = {
  'f-timer': S1,
  'f-tokens': S2,
  'f-message': S3,
  'f-rhythm': S4,
  'f-games': S5,
  'f-iphone': S6,
};

/** 문서 순서 = §8 표 순서. 직렬화 가능한 값만. */
export const SCENES: readonly Scene[] = FEATURE_COPY.map((c) => ({ ...c, comp: COMPS[c.id] }));

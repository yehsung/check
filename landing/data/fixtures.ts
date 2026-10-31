// landing/data/fixtures.ts — SPEC v2 §6.3(+ v1 DECISIONS §4 의 손으로 적은 AssetKey · SequenceName · RELEASE_FALLBACK).
// 모든 숫자는 렌더 속에 있다. 에셋 경로·픽셀 크기·캐시 버전은 data/generated/assets.json 에서 온다(asset(key)).
import assetsJson from './generated/assets.json';
import sequences from './generated/sequences.json';
import bubbles from './generated/bubbles.json';

// 인라인 타입(v1 lib/demo/reducer.ts:13–23 에서 그대로 — 상태 기계는 철거됐다).
/** 아잉 위에 뜨는 말풍선. */
export type BubbleId = 'commute-start' | 'autostart' | 'poked-mint' | 'message-gureum' | 'commute-end' | 'ruby';
/** 그림이 있는 말풍선 전부 — BubbleId + 울트라 전용 + 설치 절 정지 그림. */
export type BubbleArtId = BubbleId | 'ultra-mint' | 'update';

/** 에셋 출력 전부(확장자 뺀 경로). 영상(char/aing-*)은 data/generated/sequences.json 에만 메타가 있다.
 *  v2 가 쓰지 않는 키도 남긴다(DECISIONS D11). */
export type AssetKey =
  // 맥 렌더
  | 'ui/popover-off' | 'ui/popover-on' | 'ui/popover-tick-strip' | 'ui/popover-working' | 'ui/popover-newmsg'
  | 'ui/popover-off-1702' | 'ui/league' | 'ui/poke-list' | 'ui/poke-cooldown' | 'ui/poke-focus-1' | 'ui/poke-focus-2'
  | 'ui/message-composing' | 'ui/message-unread' | 'ui/message-read' | 'ui/minigame' | 'ui/gomoku-board' | 'ui/gomoku-board-sm'
  | 'ui/character-pick' | 'ui/todo-board' | 'ui/insights-popover'
  | 'ui/grass-work-empty' | 'ui/grass-work-final' | 'ui/grass-token-empty' | 'ui/grass-token-final'
  | 'ui/token-month' | 'ui/token-last' | 'ui/header-off-1702'
  // 메뉴바 라벨·아이콘·말풍선
  | 'ui/menubar-off' | 'ui/menubar-off-lg' | 'ui/menubar-0000' | 'ui/menubar-0100' | 'ui/menubar-0345'
  | 'ui/menubar-0345-newmsg' | 'ui/menubar-0642' | 'ui/menubar-0642-lg' | 'ui/menubar-icon-dot'
  | 'ui/bubble-commute-start' | 'ui/bubble-autostart' | 'ui/bubble-poked-mint' | 'ui/bubble-message-gureum'
  | 'ui/bubble-commute-end' | 'ui/bubble-ultra-mint' | 'ui/bubble-update' | 'ui/bubble-ruby'
  // 캐릭터 영상(.webm/.mov — 메타는 sequences.json) · 포스터
  | 'char/aing-idle' | 'char/aing-idle-15' | 'char/aing-idle-poster' | 'char/aing-commute-start' | 'char/aing-commute-end'
  | 'char/aing-poked' | 'char/aing-milestone' | 'char/aing-ultra-charged' | 'char/aing-ultra' | 'char/aing-ultra-poster'
  // 아이폰·위젯
  | 'ios/now' | 'ios/messages' | 'ios/rankings-league' | 'ios/games' | 'ios/me-records'
  | 'ios/widget-todos-large' | 'ios/widget-todos-large-checked' | 'ios/widget-today-small'
  | 'ios/conv-gureum-sent' | 'ios/conv-gureum-read'   // v3.1 메시지 장면(맥 패널과 같은 대화 — 안 읽음 1 → 읽음)
  | 'ios/widget-limits-medium'                          // v3.1 아이폰 장면(AI 리밋 미디움 위젯, 728×340)
  // v3.1 새 맥 렌더(docs/v3/brief.md §9.5 — scripts/build-assets.mjs --only=v31)
  | 'ui/ai-limits-card'        // 1020×417 — 팝오버 속 AI 리밋 카드
  | 'ui/chess-board'           // 700×700 — 1:1 체스 판만
  | 'ui/tetris-duel'           // 1200×865 — 1:1 테트리스 두 사람 카드+판(사용자 지정 크롭 — brief §9.5)
  // 브랜드
  | 'brand/appstore-badge-ko-black' | 'brand/qr-appstore' | 'brand/qr-android-beta' | 'brand/icon-64' | 'brand/icon-256'
  // v2 새 키 11개(SPEC §6.3 · §9.2 — 크롭·리사이즈만, docs/v2/requests/assets.md 의 w·h)
  | 'ui/header-on-lg'          // 1264×428
  | 'ui/menubar-0000-lg'       // 463×132
  | 'ui/menubar-icon'          // 66×66
  | 'ui/poke-slice'            // 762×852
  | 'ui/token-slice'           // 472×670
  | 'ui/league-slice'          // 496×427
  | 'ui/message-unread-panel'  // 954×900
  | 'ui/message-read-panel'    // 954×900
  | 'ui/character-panel'       // 954×900
  | 'ui/timer-00-00'           // 264×120
  | 'char/aing-rest-poster';   // 654×790

/** SpritePlayer 가 재생하는 시퀀스 이름. */
export type SequenceName =
  | 'aing-idle' | 'aing-commute-start' | 'aing-commute-end' | 'aing-poked'
  | 'aing-milestone' | 'aing-ultra-charged' | 'aing-ultra' | 'tick';

export type AssetMeta = { src: string; w: number; h: number; bytes: number };
// assets.json 은 assets 에이전트가 덮어쓴다. 키가 빠질 수 있으므로 느슨하게 받는다(v1 DECISIONS §4).
const ASSETS = assetsJson as unknown as Record<string, AssetMeta | undefined>;
/** 키가 없으면 undefined — 읽는 쪽이 개발 모드 경고 + 명시 크기의 빈 <img alt> 로 버틴다. */
export const asset = (k: AssetKey): AssetMeta | undefined => ASSETS[k];
export { sequences, bubbles };

export const PEOPLE = {
  me: { name: '새벽', character: 'aing' },
  team: [
    { name: '구름빵', character: 'jellyfish' }, { name: '달토끼', character: 'fox' },
    { name: '민트별', character: 'aing' }, { name: '호두과자', character: 'shiba' },
  ],
  others: [{ name: '보리차', character: 'squirrel' }, { name: '솜사탕', character: 'ghost' }, { name: '초코칩', character: 'ghost' }],
} as const; // 센터 정보는 넣지 않는다

export const LINKS = {
  download: '/api/download', downloadZip: '/api/download?file=zip',
  dmgLatest: 'https://github.com/yehsung/check/releases/latest/download/aing-check.dmg',
  zipLatest: 'https://github.com/yehsung/check/releases/latest/download/aing-check.zip',
  releases: 'https://github.com/yehsung/check/releases/latest',
  appStore: 'https://apps.apple.com/app/id6812768622', // 지역 코드 넣지 않음(CheckAppLinks.swift:16 과 같음)
  support: 'https://yehsung.github.io/check/', privacy: 'https://yehsung.github.io/check/privacy',
  terms: 'https://yehsung.github.io/check/terms', github: 'https://github.com/yehsung/check',
  issues: 'https://github.com/yehsung/check/issues', licenses: '/licenses',
  install: '/#install', // 폰(< 768)·iOS 의 'Mac용 다운로드'·메뉴바 [다운로드] — DMG 대신 설치 절로(docs/v3/brief.md §9.2 · §9.4)
  // 안드로이드 베타(Play 비공개 테스트 — docs/v3/brief.md §12). 이 순서로만: 구글 그룹 가입 → 웹에서 테스터 되기 → Play 스토어 설치
  // (스토어 페이지는 1·2 를 마친 계정에서만 보인다). 화면 단계 순서는 ANDROID_COPY.steps(data/install-copy.ts)가 이 키로 가리킨다.
  androidGroup: 'https://groups.google.com/g/aingcheck-android-beta',
  androidTesting: 'https://play.google.com/apps/testing/com.yehsung.aingcheck',
  androidStore: 'https://play.google.com/store/apps/details?id=com.yehsung.aingcheck',
  android: '/#android', // 설치 절 안드로이드 카드(폰 첫 화면 '안드로이드 베타 받기' · 선택 창 칩 · 데스크톱 QR)
} as const;
export const APP_STORE_ID = '6812768622';
// upgrade: 앱의 [명령 복사]와 같은 문자열 — 탭이 낡았으면 `brew upgrade` 만으로는 '이미 최신'으로 끝난다(DECISIONS D18).
export const BREW = { install: 'brew install yehsung/check/aing-check', upgrade: 'brew update && brew upgrade --cask aing-check' } as const;

// 말풍선 문구·지속 시간. 키는 그림이 있는 말풍선 전부(상태 BubbleId + 'ultra-mint' + 'update').
export const BUBBLE_TEXT: Record<BubbleArtId, { text: string; ms: number }> = {
  'commute-start':  { text: '오늘도 화이팅!', ms: 5000 },
  'autostart':      { text: '일하는 것 같아서 근무 시작했어요!', ms: 8000 },
  'poked-mint':     { text: '민트별님이 콕 찔렀어요!', ms: 6000 },
  'message-gureum': { text: '구름빵님: 커피 한잔 해요 ☕️', ms: 6000 },
  'commute-end':    { text: '수고했어!', ms: 2000 },
  'ruby':           { text: '루비 +3!', ms: 3200 },
  'ultra-mint':     { text: '민트별님의 울트라 찌르기!', ms: 0 },
  'update':         { text: '새 업데이트가 있어요!', ms: 0 },
}; // 이미지·크기·배치는 generated/bubbles.json(anchorCanvas [323,981], 캔버스 px = @3x px × 3.5)

export const CORNER = { // HERO 박스 출력 654×790 기준. 표시 배율 d = 상자폭/654
  heroOut: [654, 790], boxCorner: [124.6, 150.5], boxInline: [110, 132.9], boxInlineLg: [180, 217.4],
  bubbleAtOut: [-50.5, 218.5], capsuleAtOut: [181.5, 571], capsuleSizeOut: [263.5, 119.5], capsuleFontAtCorner: 12,
  bodyEllipseOut: { cx: 313.75, cy: 541.75, rx: 255.75, ry: 241.75 },
} as const;

/** 렌더 alt(SPEC §6.5 — 렌더를 읽은 서술, HTML 이라 달 이름을 쓰지 않는다). 말풍선은 bubbleText(id) 문장 그대로라 여기 없다.
 *  빈 문자열 = 장식(옆 글이 같은 사실을 말한다 — alt=""). */
export const ALT: Partial<Record<AssetKey, string>> = {
  'ui/menubar-0000-lg': '메뉴바 라벨, 근무 중 00:00',
  'ui/header-on-lg': '근무 시작 직후 헤더 카드: 근무중 00:00, 이번 주 19시간 38분 / 40시간, 49%',
  'ui/poke-slice': '콕 찌르기 목록: 구름빵, 달토끼, 민트별, 보리차 모두 근무중, 울트라 3개',
  'ui/grass-token-final': '최근 12주 AI 토큰 잔디',
  'ui/message-unread-panel': '구름빵과의 1:1 메시지. 보낸 메시지 "좋아요! 배포하고 1층에서요" 옆에 안 읽음 1',
  'ui/message-read-panel': '구름빵과의 1:1 메시지. 구름빵이 읽어 1이 사라짐',
  'ui/character-panel': '캐릭터 고르기: 아잉 착용 중, 여우, 유령, 해파리, 강아지, 다람쥐',
  'ui/minigame': '플래피 아잉 진행 중. 오늘 순위 1위 달토끼 41점, 2위 새벽 23점',
  'ui/gomoku-board-sm': '1:1 오목, 새벽(흑) 대 구름빵(백), 내 차례',
  'ui/token-slice': '이번 달 AI 토큰 순위: 1위 구름빵, 2위 새벽, 3위 민트별, 4위 달토끼',
  'ui/league-slice': '팀별 이번 주: 1위 파도 커피단 평균 36시간 40분, 2위 아잉 데모팀 34시간 20분, 3위 종이 공방 18시간 25분',
  'ios/now': '아이폰 지금 탭: 맥에서 근무 중 3:45:00, 이번 주 23시간 23분, 오늘 할 일 남은 4개',
  'ios/widget-todos-large': '오늘 할 일 위젯: 남은 4개',
  'ios/widget-today-small': '내 오늘 위젯',
  'ui/menubar-off': '메뉴바 라벨, 오프',
  // v2.1 장면의 통째 패널(brief-v21 §3) — 렌더를 읽은 서술(달 이름·센터 배지 글자 없이)
  'ui/popover-working': '근무 중 팝오버: 근무중 03:45, 이번 주 23시간 23분 / 40시간 58%, 아잉 데모팀 5명 근무중',
  // v3 기능 장면 1(docs/v3/brief.md §4.4 — 메뉴바 라벨 00:00 과 짝)
  'ui/popover-on': '근무 시작 직후 팝오버: 근무중 00:00, 이번 주 19시간 38분 / 40시간 49%, 아잉 데모팀 5명 근무중',
  'ui/token-month': '이번 달 AI 토큰 순위: 1위 구름빵, 2위 새벽, 3위 민트별, 4위 달토끼, 5위 호두과자, 6위 초코칩',
  'ui/league': '팀별 이번 주: 1위 파도 커피단 평균 36시간 40분, 2위 아잉 데모팀 34시간 20분, 3위 종이 공방 18시간 25분 외 2팀',
  'ui/message-unread': '구름빵과의 1:1 메시지. 보낸 메시지 "좋아요! 배포하고 1층에서요" 옆에 안 읽음 1',
  'ui/message-read': '구름빵과의 1:1 메시지. 구름빵이 읽어 1이 사라짐',
  'ui/insights-popover': '내 기록: 지난주 42시간 50분 목표 달성, 지난주 요일·시간별 근무 잔디, 최근 12주 근무 잔디',
  // v3.1 메시지 장면(docs/v3/brief.md §9.1) — 아이폰 셸 안 같은 대화
  'ios/conv-gureum-sent': '아이폰 구름빵과의 1:1 메시지. 보낸 메시지 "좋아요! 배포하고 1층에서요" 옆에 안 읽음 1',
  'ios/conv-gureum-read': '아이폰 구름빵과의 1:1 메시지. 구름빵이 읽어 1이 사라짐',
  // v3.1 새 렌더(§9.1 · §9.5) — 화면에 보이는 사실 그대로(세 번째 리밋 줄은 앱 표시대로 안티그래비티)
  'ui/ai-limits-card': 'AI 리밋 카드: 5시간·주간 사용률 Claude 42%·63%, Codex 18%·37%, 안티그래비티 9%·24%',
  'ui/chess-board': '1:1 체스 대국 판. 마지막 수 흑 비숍 b3',
  'ui/tetris-duel': '1:1 테트리스 대결 두 판: 새벽(나) 지운 줄 8·보낸 공격 3·들어올 줄 2, 달토끼 지운 줄 6·보낸 공격 4',
  'ios/widget-limits-medium': '아이폰 AI 리밋 위젯: Claude 42%·63%, Codex 18%·37%, 안티그래비티 9%·24%, AI 토큰 오늘 6,123만·12주 81.5억',
  // 장식
  'char/aing-rest-poster': '',
  'char/aing-idle-poster': '',
  'ui/timer-00-00': '',
  'ui/menubar-icon': '',
  'ui/menubar-icon-dot': '',
  'brand/icon-256': '',
};

export const ANNOUNCE = {
  copied: '복사했어요',
} as const;

export const TIMING = {
  copyResetMs: 2000,
} as const;

/** 히어로 도착(SPEC §S1 · DECISIONS D2). 마감은 내비게이션 시작(performance.now() 0) 기준. */
export const HERO = { arrivalDeadlineMs: 2500, idleLoops: 2, cometMs: 1000, bubbleMs: 5000 } as const;

// ─── 릴리스(PLAN §3.7). 서버 코드(lib/release.ts)가 다시 내보낸다 ─────────────────────────────
export type ReleaseAsset = { name: 'aing-check.dmg' | 'aing-check.zip'; url: string; bytes: number; mb: string };
export type ReleaseInfo = {
  version: string; publishedAt: string | null;
  dmg: ReleaseAsset | null; zip: ReleaseAsset | null;
  source: 'github' | 'fallback';
};
/** 0.3.49 값(DECISIONS D16 · D18 — dmg 30,054,068B = 30.1MB · zip 28,343,288B = 28.3MB). 앱 릴리스마다 갱신한다(PLAN §8). */
export const RELEASE_FALLBACK: ReleaseInfo = {
  version: '0.3.49',
  publishedAt: null,
  dmg: { name: 'aing-check.dmg', url: LINKS.dmgLatest, bytes: 30054068, mb: '30.1' },
  zip: { name: 'aing-check.zip', url: LINKS.zipLatest, bytes: 28343288, mb: '28.3' },
  source: 'fallback',
};

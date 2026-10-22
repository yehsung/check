// components/features/copy.ts — 핵심 기능 6장면 문구(정본: docs/v3/brief.md §8 '핵심 기능' 표, 글자 그대로).
// 칸 = 세그먼트(목차) 칸 이름 · 제목 = 두 줄(줄마다 <br>) · 문장 = 하나. 장면 키커·눈썹 라벨·섹션 머리 제목은 없다(칸 이름이 그 역할).
// id 6개는 내비('기능' → /#f-timer)·다른 절이 링크하므로 바꾸지 않는다. import 0 — copy.test.ts 가 node 로 바로 읽는다.

export type FeatureId = 'f-timer' | 'f-tokens' | 'f-message' | 'f-rhythm' | 'f-games' | 'f-iphone';

export interface FeatureCopy {
  id: FeatureId;
  /** 세그먼트 칸 이름 */
  tab: string;
  /** 제목 두 줄 */
  title: readonly [string, string];
  /** 문장 하나 */
  body: string;
}

export const FEATURE_COPY: readonly FeatureCopy[] = [
  {
    id: 'f-timer',
    tab: '타이머',
    title: ['한 번 클릭으로 시작하고', '다시 클릭으로 마무리해요'],
    body: '메뉴바에 오늘 일한 시간이 숫자로 찍히고, 지금 근무 중인 팀원 목록도 함께 보여요.',
  },
  {
    id: 'f-tokens',
    tab: 'AI 사용량',
    title: ['AI 리밋과 토큰 순위를', '메뉴바에서 바로 봐요'],
    body: 'Claude Code·Codex·Gemini의 5시간·주간 리밋이 몇 % 찼는지 보고, 이번 달 토큰 사용량 순위도 확인해요.',
  },
  {
    id: 'f-message',
    tab: '메시지',
    title: ['팀원에게 할 말이 있을 땐', '메뉴바에서 바로 보내요'],
    body: "메뉴바는 물론 아이폰에서도 1:1 메시지를 전하고, 상대가 읽으면 옆의 '1'이 사라져요.",
  },
  {
    id: 'f-rhythm',
    tab: '기록',
    title: ['일한 시간과 AI 사용량이', '12주 치 잔디로 쌓여요'],
    body: '지난주 어느 요일 몇 시에 일했는지도 잔디로 한눈에 보여요.',
  },
  {
    id: 'f-games',
    tab: '게임',
    title: ['머리 식히고 싶을 땐', '미니게임 한 판 해요'],
    body: '타이밍 바·플래피 아잉으로 오늘 순위를 겨루고, 오목·체스·테트리스는 1:1 대결도 할 수 있어요.',
  },
  {
    id: 'f-iphone',
    tab: '아이폰',
    title: ['근무는 맥에서 켜고', '확인은 아이폰에서 해요'],
    body: '팀 현황·메시지·할 일·게임은 물론 AI 리밋이 몇 % 찼는지도 앱과 홈 화면 위젯에서 봐요.',
  },
];

/** 세그먼트(목차) 접근 이름 */
export const FEATURE_NAV_LABEL = '핵심 기능 목차';
/** 절 접근 이름(보이는 머리 제목은 없다) */
export const FEATURE_SECTION_LABEL = '핵심 기능';

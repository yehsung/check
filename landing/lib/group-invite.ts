// 그룹 초대 링크 페이지(/g/<코드>)의 **순수** 부분 — 코드 정규화 · 서버 응답 해석 · 기기별 행동 · 문구.
// 네트워크는 fetch 를 주입받아 한다(시험은 가짜 fetch 로 잰다).
//
// 근거: 구조 개편 결정 DV-14(초대 링크는 랜딩 주소의 페이지 하나로 열고, 폰은 앱을 열거나 스토어로, 맥은 코드를 보여 줌) ·
//       서버 계약 판 1 §3-2 `team_preview(p_code)` (anon·읽기만·pg_sleep 0.3) · §7-3 A 허용 경로 · §9 랜딩 칸.
// 응답: `{status, team:{name, member_count, weekly_goal_hours, join_policy, visibility}}`
//       status ∈ ok · not_found · expired · used_up · full · not_enabled
//
// 사생활: 그룹 이름은 링크를 받은 사람에게만 보이도록 페이지 본문에만 쓰고, 미리보기(OG)·제목에는 넣지 않는다.
// 페이지는 검색에 올리지 않는다(noindex + robots 에서 /g/ 막기).

import type { DeleteAccountConfig } from './delete-account';

/** 초대 코드 정규화 — 서버 `lookup_team_by_code`·`join_team` 과 같다: 공백·하이픈을 지우고 대문자로. */
export function normalizeInviteCode(raw: string): string {
  let decoded = raw;
  try {
    decoded = decodeURIComponent(raw);
  } catch {
    // 잘못된 % 인코딩은 그대로 둔다 — 아래 모양 검사에서 걸러진다.
  }
  return decoded.replace(/[\s-]/g, '').toUpperCase();
}

/** 서버에 물을 만한 모양인지 — 영문·숫자 4~32자. 아니면 서버를 부르지 않고 '없는 코드'로 본다(pg_sleep 을 헛되이 태우지 않음). */
export function isPlausibleInviteCode(code: string): boolean {
  return /^[A-Z0-9]{4,32}$/.test(code);
}

export type PreviewStatus = 'ok' | 'not_found' | 'expired' | 'used_up' | 'full' | 'not_enabled';
/** 서버까지 가지 못했거나 알아볼 수 없는 답. */
export type PreviewFailure = 'unavailable';

export interface GroupPreview {
  readonly name: string;
  readonly memberCount: number;
  readonly weeklyGoalHours: number | null;
  /** 'approval' 이면 들어가기를 누른 뒤 그룹장 승인을 기다린다. */
  readonly needsApproval: boolean;
}

export type PreviewResult =
  | { readonly status: 'ok'; readonly group: GroupPreview }
  | { readonly status: Exclude<PreviewStatus, 'ok'> | PreviewFailure };

const KNOWN: ReadonlySet<string> = new Set(['ok', 'not_found', 'expired', 'used_up', 'full', 'not_enabled']);

/** RPC 응답(JSON 값) → 결과. 모양이 어긋나면 'unavailable'(지어내지 않는다). */
export function parsePreview(json: unknown): PreviewResult {
  if (!json || typeof json !== 'object') return { status: 'unavailable' };
  const o = json as Record<string, unknown>;
  const status = typeof o.status === 'string' ? o.status : '';
  if (!KNOWN.has(status)) return { status: 'unavailable' };
  if (status !== 'ok') return { status: status as Exclude<PreviewStatus, 'ok'> };
  const t = o.team;
  if (!t || typeof t !== 'object') return { status: 'unavailable' };
  const team = t as Record<string, unknown>;
  const name = typeof team.name === 'string' ? team.name.trim() : '';
  const count = typeof team.member_count === 'number' && Number.isFinite(team.member_count) ? Math.max(0, Math.floor(team.member_count)) : NaN;
  if (!name || Number.isNaN(count)) return { status: 'unavailable' };
  const goal = typeof team.weekly_goal_hours === 'number' && team.weekly_goal_hours > 0 ? Math.floor(team.weekly_goal_hours) : null;
  return { status: 'ok', group: { name, memberCount: count, weeklyGoalHours: goal, needsApproval: team.join_policy === 'approval' } };
}

/** 브라우저·서버 fetch 중 이 파일이 쓰는 모양만. */
export type PreviewFetch = (
  url: string,
  init: { method: string; headers: Record<string, string>; body: string; cache: 'no-store'; signal?: AbortSignal },
) => Promise<{ readonly status: number; json(): Promise<unknown> }>;

/** 서버 렌더에서 부른다. 설정이 없거나(미리보기 배포) 모양이 틀리면 서버를 부르지 않는다. */
export async function fetchGroupPreview(fetchFn: PreviewFetch, config: DeleteAccountConfig | null, code: string, timeoutMs = 4000): Promise<PreviewResult> {
  if (!isPlausibleInviteCode(code)) return { status: 'not_found' };
  if (!config) return { status: 'unavailable' };
  const controller = typeof AbortController === 'function' ? new AbortController() : null;
  const timer = controller ? setTimeout(() => controller.abort(), timeoutMs) : null;
  try {
    const res = await fetchFn(`${config.url}/rest/v1/rpc/team_preview`, {
      method: 'POST',
      headers: { apikey: config.anonKey, Authorization: `Bearer ${config.anonKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_code: code }),
      cache: 'no-store',
      ...(controller ? { signal: controller.signal } : {}),
    });
    if (res.status < 200 || res.status >= 300) return { status: 'unavailable' };
    return parsePreview(await res.json());
  } catch {
    return { status: 'unavailable' };
  } finally {
    if (timer) clearTimeout(timer);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// 기기별 행동

export const APP_PACKAGE = 'com.yehsung.aingcheck';

/**
 * 안드로이드 '앱에서 열기' — intent 주소. 같은 도메인 안에서 누른 https 링크는 앱 링크로 열리지 않으므로 intent 로 연다.
 * 앱이 없으면 브라우저가 Play 스토어(fallback)로 간다.
 */
export function androidIntentUrl(siteHost: string, code: string, fallbackUrl: string): string {
  return `intent://${siteHost}/g/${encodeURIComponent(code)}#Intent;scheme=https;package=${APP_PACKAGE};S.browser_fallback_url=${encodeURIComponent(fallbackUrl)};end`;
}

/** 아이폰 Safari 스마트 배너의 앱 id(App Store 주소에서). 앱이 있으면 배너의 '열기'가 app-argument 주소를 앱에 넘긴다. */
export function smartBannerAppId(appStoreUrl: string): string | null {
  return /\/id(\d+)/.exec(appStoreUrl)?.[1] ?? null;
}

// ---------------------------------------------------------------------------------------------------------------
// 문구 — 랜딩 말투(해요체), 랜딩 금지어(판돈·센터 등)를 쓰지 않는다.

export const INVITE_COPY = {
  title: '아잉체크 그룹 초대',
  description: '아잉체크 그룹 초대 링크예요. 앱에서 이 코드로 그룹에 들어올 수 있어요.',
  eyebrow: '그룹 초대',
  members: (n: number) => `${n}명`,
  goal: (h: number) => `주간 목표 1인당 ${h}시간`,
  approval: '그룹장이 승인하면 함께할 수 있어요.',
  codeLabel: '초대 코드',
  copy: '코드 복사',
  copied: '복사했어요',
  openApp: '앱에서 열기',
  phoneHow: '앱이 열리지 않으면 앱을 받은 뒤 이 링크를 다시 눌러 주세요.',
  macHow: '맥 앱에서 그룹 → 코드로 들어가기에 이 코드를 넣어 주세요.',
  macDownload: 'Mac용 다운로드',
  noApp: '아직 앱이 없다면',
  status: {
    not_found: { title: '없는 초대 코드예요', body: '코드가 바뀌었거나 잘못 적힌 링크일 수 있어요. 그룹장에게 새 링크를 받아 주세요.' },
    expired: { title: '기간이 지난 초대예요', body: '그룹장에게 새 링크를 받아 주세요.' },
    used_up: { title: '쓸 수 있는 횟수가 다 찼어요', body: '그룹장에게 새 링크를 받아 주세요.' },
    full: { title: '그룹 인원이 가득 찼어요', body: '그룹장에게 알려 주세요.' },
    not_enabled: { title: '그룹 기능이 곧 열려요', body: '열리면 이 링크로 바로 들어올 수 있어요. 앱을 미리 받아 두세요.' },
    unavailable: { title: '그룹 정보를 지금 불러오지 못했어요', body: '앱에서 아래 코드를 넣으면 들어올 수 있어요.' },
  },
} as const;

/** 코드를 보여 줄지 — 쓸 수 없는 코드(없음·만료·횟수 끝)는 숨긴다. */
export function showsCode(status: PreviewResult['status']): boolean {
  return status === 'ok' || status === 'not_enabled' || status === 'unavailable';
}

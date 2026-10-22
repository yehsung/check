// lib/keep-dots.ts — 가운뎃점(·)으로 이은 묶음이 '·' 앞뒤에서 줄이 바뀌지 않게 글을 조각낸다(docs/v3/brief.md §9.4.6). 순수 함수, import 0.
// 브라우저(keep-all)는 '·' 앞뒤를 줄바꿈 기회로 본다 — '오목' / '·체스·테트리스는' 처럼 끊겼다(390 실측). 화면 글자는 그대로(조각을 이으면 원문).
// components/ui/KeepDots.tsx 가 nowrap 조각을 <span class="whitespace-nowrap"> 으로 그린다.

export interface TextRun {
  text: string;
  /** 이 조각 안에서는 줄을 바꾸지 않는다 */
  nowrap: boolean;
}

/** 목록이 여기서 끝난다는 표시(조사로 끝나는 낱말 — 'Gemini의' · '테트리스는' · '게임을'). */
const LIST_END = /[의은는을를이가도와과로에]$/;
/** 절의 첫 낱말 판정용(앞 낱말이 이것으로 끝나면 다음 낱말이 절 첫 낱말) */
const CLAUSE_END = /[,.!?]$/;

/**
 * 산문용: 공백으로 나눈 낱말 중 '·' 가 든 낱말은 nowrap. 그리고 이웃 낱말을 같은 묶음으로 붙인다(사이 공백에서도 안 끊김):
 *  - 혼자 선 '·'(' · ' 구분자)는 앞 낱말에 붙는다 — 줄머리에 '·' 가 오지 않게.
 *  - '·' 낱말 바로 앞 낱말이 (a) 절의 첫 낱말이거나 (b) 라틴 대문자로 시작하는 보통 낱말이면 붙는다 — 'Claude Code·…' · '팀 현황·…' · 'Apple Silicon·Intel'.
 *  - '·' 낱말끼리 이어지고 앞 낱말이 조사로 끝나지 않으면 같은 목록 안의 공백이라 붙는다 — '현황·메시지·할 일·게임은' 의 '할 일'.
 */
export function keepDots(text: string): TextRun[] {
  const parts = text.split(/(\s+)/); // [낱말, 공백, 낱말, …] — 앞뒤가 공백이면 빈 낱말이 생긴다
  const words = parts.filter((_, i) => i % 2 === 0);
  const gaps = parts.filter((_, i) => i % 2 === 1);
  const dotted = (w: string) => w.includes('·') && w !== '·';
  // glue[i] = 낱말 i 를 앞 낱말 i-1 에 붙인다
  const glue = words.map((w, i) => {
    if (i === 0 || words[i - 1] === '') return false;
    const prev = words[i - 1];
    if (w === '·') return true;
    if (!dotted(w)) return false;
    if (dotted(prev)) return !LIST_END.test(prev);
    if (prev === '·') return false;
    const clauseFirst = i - 1 === 0 || CLAUSE_END.test(words[i - 2] ?? '');
    return clauseFirst || /^[A-Z]/.test(prev);
  });
  const runs: TextRun[] = [];
  const push = (t: string, nowrap: boolean) => {
    if (!t) return;
    const last = runs.at(-1);
    if (last && !last.nowrap && !nowrap) last.text += t;
    else runs.push({ text: t, nowrap });
  };
  let i = 0;
  while (i < words.length) {
    let j = i;
    let chunk = words[i];
    while (j + 1 < words.length && glue[j + 1]) {
      chunk += gaps[j] + words[j + 1];
      j++;
    }
    push(chunk, j > i || dotted(words[i]));
    if (j < gaps.length) push(gaps[j], false);
    i = j + 1;
  }
  return runs;
}

/**
 * 메타 줄용: 'a · b · c' → ['a ·', ' ', 'b ·', ' ', 'c'] — 항목은 통째로(nowrap), '·' 는 앞 항목 끝에 붙여 줄머리에 오지 않는다.
 * 줄은 항목 사이 공백에서만 바뀐다(설치 절 MetaLine 과 같은 규칙).
 */
export function dotItems(text: string): TextRun[] {
  const items = text.split(' · ');
  const runs: TextRun[] = [];
  items.forEach((it, i) => {
    const last = i === items.length - 1;
    runs.push({ text: last ? it : `${it} ·`, nowrap: true });
    if (!last) runs.push({ text: ' ', nowrap: false });
  });
  return runs;
}

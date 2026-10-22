// node --experimental-strip-types --test components/features/copy.test.ts
// 핵심 기능 문장 계약(docs/v3/brief.md §8 '핵심 기능' 표 · §4.4): 칸·제목 두 줄·문장 = 표 글자 그대로 · id 6개 순서 ·
// 금지어 0 · 맥 동작은 '클릭'(누르다 0) · 근무 기록 칸은 '잔디'(격자 0) · 'AI 토큰 리밋' 0 · 쉼표로 끊는 제목 0.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { FEATURE_COPY } from './copy.ts';

const BRIEF = readFileSync(new URL('../../docs/v3/brief.md', import.meta.url), 'utf8');
const S8 = BRIEF.slice(BRIEF.indexOf('## 8.'));
const table = S8.slice(S8.indexOf('\n핵심 기능'), S8.indexOf('\n설치('));

// 히어로 copy.test 와 같은 결(단, 'Gemini' 는 이 절의 정본 문장에 있다 — §8 f-tokens).
const FORBIDDEN = [
  '오픈소스', '판돈', '베팅', '내기', '걸고', '체험', '눌러 보세요', 'Learn more', '더보기', '작은 팀', 'AI 토큰 리밋',
  '격자', '누르', '눌러', '안티그래비티',
];

test('장면 id 6개 = §8 표 순서(f-timer · f-tokens · f-message · f-rhythm · f-games · f-iphone)', () => {
  assert.deepEqual(
    FEATURE_COPY.map((c) => c.id),
    ['f-timer', 'f-tokens', 'f-message', 'f-rhythm', 'f-games', 'f-iphone'],
  );
});

test('칸 · 제목 두 줄 · 문장 = §8 표의 그 행 글자 그대로', () => {
  for (const c of FEATURE_COPY) {
    const row = table.split('\n').find((l) => l.startsWith(`| ${c.id} |`));
    assert.ok(row, `§8 표에 ${c.id} 행이 없음`);
    const cells = row.split('|').map((s) => s.trim());
    // ['', id, 칸, 제목, 문장, '']
    assert.equal(cells[2], c.tab, `${c.id} 칸`);
    assert.equal(cells[3], `\`${c.title[0]}\` / \`${c.title[1]}\``, `${c.id} 제목`);
    assert.equal(cells[4], `\`${c.body}\``, `${c.id} 문장`);
  }
});

test('제목은 두 줄 · 쉼표로 억지로 끊지 않는다 · 문장은 하나', () => {
  for (const c of FEATURE_COPY) {
    assert.equal(c.title.length, 2);
    for (const line of c.title) assert.ok(!/[,.]$/.test(line), `쉼표·마침표 끝 '${line}'`);
    assert.equal(c.body.split(/(?<=[.!?])\s/).length, 1, `${c.id} 문장이 둘 이상`);
  }
});

test("금지어 0 · '누르다' 0 · '격자' 0", () => {
  const text = FEATURE_COPY.flatMap((c) => [c.tab, ...c.title, c.body]).join('\n');
  for (const w of FORBIDDEN) assert.ok(!text.includes(w), `금지어 '${w}'`);
});

test("기록 장면은 '잔디' · 게임 장면은 1:1 대결 셋(오목·체스·테트리스) · 메시지 장면의 '1' 따옴표 유지", () => {
  const by = Object.fromEntries(FEATURE_COPY.map((c) => [c.id, c]));
  assert.ok(by['f-rhythm'].title.join(' ').includes('잔디'));
  assert.ok(by['f-games'].body.includes('오목·체스·테트리스'));
  assert.ok(by['f-message'].body.includes("'1'"));
});

// node --experimental-strip-types --test lib/keep-dots.test.ts
// 가운뎃점 묶음 줄바꿈(docs/v3/brief.md §9.4.6): 조각을 이으면 원문 · §9.4.6 의 세 묶음은 한 nowrap 조각 안 · ' · ' 의 '·' 는 줄머리에 안 온다.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { dotItems, keepDots, type TextRun } from './keep-dots.ts';

const join = (r: TextRun[]) => r.map((x) => x.text).join('');
/** phrase 가 nowrap 조각 하나 안에 통째로 들어 있는가 */
const keptWhole = (r: TextRun[], phrase: string) => r.some((x) => x.nowrap && x.text.includes(phrase));
/** '·' 앞뒤가 줄바꿈 기회(nowrap 조각의 경계)에 걸리지 않는가 */
function noBreakAtDot(r: TextRun[]) {
  for (const x of r) {
    if (x.nowrap) continue;
    assert.ok(!x.text.includes('·'), `nowrap 밖에 '·': ${JSON.stringify(x.text)}`);
  }
}

const SENTENCES = [
  'Claude Code·Codex·Gemini의 5시간·주간 리밋이 몇 % 찼는지 보고, 이번 달 토큰 사용량 순위도 확인해요.',
  '타이밍 바·플래피 아잉으로 오늘 순위를 겨루고, 오목·체스·테트리스는 1:1 대결도 할 수 있어요.',
  '팀 현황·메시지·할 일·게임은 물론 AI 리밋이 몇 % 찼는지도 앱과 홈 화면 위젯에서 봐요.',
  'macOS 14 이상 맥이면 Apple Silicon·Intel 모두 돼요. 아이폰은 iOS 18 이상이에요. 근무 시작·종료는 맥에서 하고, 아이폰에선 현황·메시지·할 일·게임을 써요.',
  '아니요. 스크린샷·키 입력·마우스 움직임·앱 사용 기록을 모으지 않고, 화면 기록·손쉬운 사용 권한도 요청하지 않아요.',
  '메뉴바는 물론 아이폰에서도 1:1 메시지를 전하고, 상대가 읽으면 옆의 \'1\'이 사라져요.',
];

test('조각을 이으면 원문 그대로 · nowrap 밖에는 \'·\' 가 없다', () => {
  for (const s of SENTENCES) {
    const r = keepDots(s);
    assert.equal(join(r), s);
    noBreakAtDot(r);
  }
  assert.deepEqual(keepDots('가 나 다'), [{ text: '가 나 다', nowrap: false }]);
  assert.equal(join(keepDots(' 앞뒤 공백 ')), ' 앞뒤 공백 ');
});

test('§9.4.6 의 세 묶음은 통째로(첫 항목의 공백 낱말 포함)', () => {
  assert.ok(keptWhole(keepDots(SENTENCES[1]), '오목·체스·테트리스는'));
  assert.ok(keptWhole(keepDots(SENTENCES[0]), 'Claude Code·Codex·Gemini의'));
  assert.ok(keptWhole(keepDots(SENTENCES[2]), '팀 현황·메시지·할 일·게임은'));
  assert.ok(keptWhole(keepDots(SENTENCES[3]), 'Apple Silicon·Intel'));
  assert.ok(keptWhole(keepDots(SENTENCES[3]), '근무 시작·종료는'));
});

test('다른 목록끼리는 붙이지 않는다(조사로 끝난 목록 뒤) — 묶음이 지나치게 길어지지 않게', () => {
  const r = keepDots(SENTENCES[0]);
  assert.ok(!r.some((x) => x.nowrap && x.text.includes('Gemini의 5시간')));
  assert.ok(keptWhole(r, '5시간·주간'));
});

test("메타 줄: 항목 통째 · '·' 는 앞 항목 끝에", () => {
  const r = dotItems('무료 · iOS 18 이상 · macOS 14 이상');
  assert.equal(join(r), '무료 · iOS 18 이상 · macOS 14 이상');
  assert.deepEqual(
    r.filter((x) => x.nowrap).map((x) => x.text),
    ['무료 ·', 'iOS 18 이상 ·', 'macOS 14 이상'],
  );
  for (const x of r) if (!x.nowrap) assert.equal(x.text, ' ');
});

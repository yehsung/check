// node --experimental-strip-types --test components/glass/command-parts.test.ts
// 명령 알약 줄바꿈 조각: 하이픈 낱말은 nowrap · '/'·'&& ' 뒤에만 <wbr> · 글자는 그대로 이어 붙으면 원문.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { commandParts } from './command-parts.ts';

const INSTALL = 'brew install yehsung/check/aing-check';
const UPGRADE = 'brew update && brew upgrade --cask aing-check';

test('조각을 이어 붙이면 원문 그대로(복사·선택 글자 불변)', () => {
  for (const c of [INSTALL, UPGRADE, 'https://github.com/yehsung/check']) {
    assert.equal(commandParts(c).map((p) => p.text).join(''), c);
  }
});

test("설치 명령: 'aing-check' 는 한 덩어리(nowrap), '/' 뒤에만 줄바꿈 기회", () => {
  const parts = commandParts(INSTALL);
  const hy = parts.filter((p) => p.nowrap).map((p) => p.text);
  assert.deepEqual(hy, ['aing-check']);
  const wbr = parts.filter((p) => p.wbrAfter).map((p) => p.text);
  assert.deepEqual(wbr, ['brew install yehsung/', 'check/']);
  // 하이픈이 nowrap 조각 밖에 남지 않는다
  for (const p of parts) if (!p.nowrap) assert.ok(!/\S-\S/.test(p.text), `하이픈이 끊길 수 있는 조각: '${p.text}'`);
});

test("업데이트 명령: '&& ' 뒤에 줄바꿈 기회 · '--cask' · 'aing-check' nowrap", () => {
  const parts = commandParts(UPGRADE);
  assert.deepEqual(parts.filter((p) => p.wbrAfter).map((p) => p.text), ['brew update && ']);
  assert.deepEqual(parts.filter((p) => p.nowrap).map((p) => p.text), ['--cask', 'aing-check']);
  assert.equal(parts.at(-1)?.wbrAfter, false);
});

test("'https://' 의 두 '/' 사이에서는 끊지 않는다", () => {
  const parts = commandParts('https://github.com/x');
  assert.ok(parts.every((p) => !p.text.endsWith('https:/')), JSON.stringify(parts));
});

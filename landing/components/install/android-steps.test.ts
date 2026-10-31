// node --experimental-strip-types --test components/install/android-steps.test.ts
// 안드로이드 베타 카드 '다음 단계 안내'(docs/v3/brief.md §12.6 — 사용자 2026-10-30 "승인되었을때 기준으로 ux적으로 편하게 설치할 수 있게 세팅해줘")의
// 순수 계산(android-steps-logic.ts)을 값으로 확인한다: 클릭 순서 → 주 버튼 단계 · aria-current · 체크 표시 · 저장소 없음/던짐/이상한 값.
// 보이는 결과(클릭 뒤 버튼 모양 · 새로고침 뒤 유지 · 막힌 저장소 · 레이아웃 이동 0 · 하이드레이션 어긋남 0)는 scripts/android-smoke.mjs 가 잰다.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  ANDROID_STEP_COUNT,
  ANDROID_STEP_KEY,
  clampStep,
  clickStep,
  parseStep,
  readStep,
  stepViews,
  writeStep,
  type StepStorage,
} from './android-steps-logic.ts';

/** 메모리 저장소(getItem·setItem 만) */
function memStorage(init: Record<string, string> = {}): StepStorage & { data: Record<string, string> } {
  const data = { ...init };
  return {
    data,
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => {
      data[k] = String(v);
    },
  };
}

/** 모양 요약: 주 버튼 단계 · aria-current 단계 · 체크된 단계 */
function look(state: number) {
  const v = stepViews(state);
  return {
    primary: v.filter((s) => s.primary).map((s) => s.n),
    current: v.filter((s) => s.current).map((s) => s.n),
    done: v.filter((s) => s.done).map((s) => s.n),
  };
}

/** 처음(0)에서 클릭 순서대로 */
const after = (clicks: number[]) => clicks.reduce(clickStep, 0);

test('키 · 단계 수 = 명세 그대로', () => {
  assert.equal(ANDROID_STEP_KEY, 'aing-android-beta-step');
  assert.equal(ANDROID_STEP_COUNT, 3);
});

test('상태 0(서버 HTML · JS 없음) = 1단계 주 버튼 + aria-current · 체크 없음', () => {
  assert.deepEqual(look(0), { primary: [1], current: [1], done: [] });
  assert.deepEqual(
    stepViews(0).map((s) => s.n),
    [1, 2, 3],
  );
});

test('상태별 모양 — 주 버튼은 늘 하나 이하 · aria-current 와 같은 단계 · 체크는 1..상태', () => {
  assert.deepEqual(look(1), { primary: [2], current: [2], done: [1] });
  assert.deepEqual(look(2), { primary: [3], current: [3], done: [1, 2] });
  assert.deepEqual(look(3), { primary: [], current: [], done: [1, 2, 3] }, '3단계 뒤 = 셋 다 체크, 주 버튼 없음');
  for (let s = 0; s <= 3; s++) {
    const v = stepViews(s);
    assert.ok(v.filter((x) => x.primary).length <= 1);
    for (const x of v) {
      assert.equal(x.primary, x.current, `상태 ${s} 단계 ${x.n}: 주 버튼 = aria-current`);
      assert.ok(!(x.done && x.primary), '체크된 단계는 주 버튼이 아니다');
    }
  }
});

test('클릭 순서 → 주 버튼 단계(순서를 막지 않는다 — 클릭한 단계가 곧 새 상태)', () => {
  const cases: [number[], number[], number[]][] = [
    // [클릭 순서, 주 버튼, 체크]
    [[], [1], []],
    [[1], [2], [1]],
    [[1, 2], [3], [1, 2]],
    [[1, 2, 3], [], [1, 2, 3]],
    [[2], [3], [1, 2]], // 1단계를 건너뛰어도 막지 않는다(다른 기기에서 이미 했을 수 있다)
    [[3], [], [1, 2, 3]],
    [[1, 2, 1], [2], [1]], // 1단계를 다시 하면(다른 계정으로 다시 가입) 2단계가 다시 주 버튼
    [[1, 2, 3, 2], [3], [1, 2]], // 3단계에서 안 보여 2단계를 다시 하면 3단계가 다시 주 버튼
    [[3, 1], [2], [1]],
    [[1, 1, 1], [2], [1]],
  ];
  for (const [clicks, primary, done] of cases) {
    const s = after(clicks);
    assert.deepEqual(look(s).primary, primary, `클릭 ${clicks.join('→') || '없음'} 주 버튼`);
    assert.deepEqual(look(s).current, primary, `클릭 ${clicks.join('→') || '없음'} aria-current`);
    assert.deepEqual(look(s).done, done, `클릭 ${clicks.join('→') || '없음'} 체크`);
  }
});

test('clickStep: 범위 밖 단계 번호는 상태를 바꾸지 않는다 · 이상한 이전 상태는 0 으로', () => {
  for (const bad of [0, 4, -1, 1.5, Number.NaN, Infinity]) assert.equal(clickStep(2, bad), 2, `n=${bad}`);
  assert.equal(clickStep(9, 0), 0);
  assert.equal(clickStep(9, 2), 2);
});

test('clampStep · stepViews: 이상한 상태(범위 밖 · 소수 · NaN · 글자)는 0 과 같다', () => {
  for (const bad of [-1, 4, 99, 1.5, Number.NaN, Infinity, '2', null, undefined, {}]) {
    assert.equal(clampStep(bad), 0, String(bad));
    assert.deepEqual(look(bad as number), look(0), String(bad));
  }
  for (const ok of [0, 1, 2, 3]) assert.equal(clampStep(ok), ok);
});

test("parseStep: 정확히 '0'…'3' 만 — 나머지(없음 · 공백 · 소수 · 앞 0 · JSON · 범위 밖)는 0", () => {
  assert.deepEqual(['0', '1', '2', '3'].map(parseStep), [0, 1, 2, 3]);
  for (const bad of [null, undefined, '', ' ', ' 2', '2 ', '2\n', '1.0', '02', '4', '-1', '9', 'abc', 'true', '"2"', '[2]', 'NaN', '٢', 2, true]) {
    assert.equal(parseStep(bad), 0, JSON.stringify(bad));
  }
});

test('readStep: 저장된 값 · 없음 · 저장소 없음 · 접근자가 던짐 · getItem 이 던짐 · 이상한 값 → 0', () => {
  assert.equal(readStep(() => memStorage({ [ANDROID_STEP_KEY]: '2' })), 2);
  assert.equal(readStep(() => memStorage()), 0, '키 없음');
  assert.equal(readStep(() => null), 0, '저장소 null');
  assert.equal(readStep(() => undefined), 0, '저장소 undefined');
  assert.equal(
    readStep(() => {
      throw new Error('SecurityError: The operation is insecure.');
    }),
    0,
    'window.localStorage 접근자가 던짐(사파리 사생활 · 막힌 사이트 데이터)',
  );
  assert.equal(
    readStep(() => ({
      getItem: () => {
        throw new Error('denied');
      },
      setItem: () => {},
    })),
    0,
    'getItem 이 던짐',
  );
  for (const v of ['7', 'abc', '', '1.5', ' 1']) assert.equal(readStep(() => memStorage({ [ANDROID_STEP_KEY]: v })), 0, `이상한 값 ${JSON.stringify(v)}`);
  // 다른 키는 보지 않는다
  assert.equal(readStep(() => memStorage({ 'aing-android-beta': '2' })), 0);
});

test('writeStep: 0–3 글자로 쓴다 · 범위 밖은 0 · 저장소 없음/던짐이면 false(던지지 않는다) · 쓴 값을 readStep 이 그대로 읽는다', () => {
  const m = memStorage();
  assert.equal(writeStep(() => m, 2), true);
  assert.equal(m.data[ANDROID_STEP_KEY], '2');
  assert.equal(readStep(() => m), 2, '왕복');
  assert.equal(writeStep(() => m, 3), true);
  assert.equal(readStep(() => m), 3);
  assert.equal(writeStep(() => m, 9), true);
  assert.equal(m.data[ANDROID_STEP_KEY], '0', '범위 밖은 0 으로');
  assert.equal(writeStep(() => null, 1), false);
  assert.equal(
    writeStep(() => {
      throw new Error('SecurityError');
    }, 1),
    false,
  );
  assert.equal(
    writeStep(
      () => ({
        getItem: () => null,
        setItem: () => {
          throw new Error('QuotaExceededError');
        },
      }),
      1,
    ),
    false,
    'setItem 이 던짐(용량 · 사생활)',
  );
});

test('클릭 → 쓰기 → 새로고침(다시 읽기) = 같은 모양 · 막힌 저장소면 새로고침 뒤 처음 모양', () => {
  const m = memStorage();
  let s = readStep(() => m);
  for (const n of [1, 2]) {
    s = clickStep(s, n);
    writeStep(() => m, s);
  }
  assert.deepEqual(look(readStep(() => m)), { primary: [3], current: [3], done: [1, 2] });
  const blocked = () => {
    throw new Error('SecurityError');
  };
  let b = readStep(blocked);
  b = clickStep(b, 1);
  assert.equal(writeStep(blocked, b), false);
  assert.deepEqual(look(b), { primary: [2], current: [2], done: [1] }, '메모리로는 이어간다');
  assert.deepEqual(look(readStep(blocked)), look(0), '새로고침 뒤 = 서버 HTML 상태');
});

// ─── 소스 계약(client 섬 — 렌더 없이 볼 길이 없다, 꼭 필요한 것만) ──────────────────────────────

const strip = (src: string) =>
  src
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:'"`])\/\/.*$/gm, '$1');
const STEPS = strip(readFileSync(new URL('./AndroidSteps.tsx', import.meta.url), 'utf8'));

test('소스 계약 — AndroidSteps: client 섬 · 서버 스냅숏 0(하이드레이션 어긋남 0) · 저장소는 logic 의 try/catch 함수로만 · 클릭(가운데 클릭 포함) = mark', () => {
  assert.match(STEPS, /^'use client';/);
  assert.match(STEPS, /useSyncExternalStore\(subscribe, snapshot, serverSnapshot\)/);
  assert.match(STEPS, /const serverSnapshot = \(\) => 0;/);
  assert.match(STEPS, /const snapshot = \(\) => \(memory \?\?= readStep\(local\)\);/, '한 번 읽고 메모리에 둔다(스냅숏이 매번 같은 값)');
  // localStorage 를 직접 읽고 쓰지 않는다(getItem/setItem 은 logic 의 try/catch 안에서만)
  assert.ok(!/\.getItem\(|\.setItem\(/.test(STEPS), '직접 getItem/setItem');
  assert.match(STEPS, /writeStep\(local, memory\)/);
  assert.match(STEPS, /onClick=\{\(\) => mark\(v\.n\)\}/);
  assert.match(STEPS, /if \(e\.button === 1\) mark\(v\.n\)/, '가운데 클릭');
  assert.ok(!/preventDefault/.test(STEPS), '새 탭 열기를 막지 않는다');
  assert.equal(/[가-힣]/.test(STEPS), false, '한글 리터럴 0 — 글자는 ANDROID_COPY 에서만(새 글자 없음)');
});

test('소스 계약 — AndroidSteps: 주 버튼/outline 은 같은 크기(s) · aria-current="step" · 체크는 장식(번호는 sr-only) · 폰 버튼 카드 폭 · 48', () => {
  assert.match(STEPS, /glassButtonClass\(v\.primary \? 'primary' : 'glass', 's', BTN\)/, '변형만 바뀌고 크기는 s 그대로');
  assert.match(STEPS, /aria-current=\{v\.current \? 'step' : undefined\}/);
  assert.match(STEPS, /<span className=\{v\.done \? 'sr-only' : undefined\}>\{v\.n\}<\/span>\s*\{v\.done && <CheckGlyph \/>\}/);
  const parts = strip(readFileSync(new URL('./android-parts.tsx', import.meta.url), 'utf8'));
  assert.match(/function CheckGlyph[\s\S]*?<\/svg>/.exec(parts)?.[0] ?? '', /aria-hidden="true"/, '체크 = 장식');
  const btn = /const BTN = '([^']+)'/.exec(STEPS)?.[1] ?? '';
  for (const c of ['phone:w-full', 'phone:[--b-h:48px]', 'phone:col-span-2']) assert.ok(btn.split(' ').includes(c), `폰 버튼 ${c}`);
  // 단계 사이 간격(폰) — 옆 버튼을 잘못 클릭하지 않게
  assert.match(STEPS, /phone:not-first:mt-6 phone:not-first:border-t [^']*phone:not-first:pt-6/);
});

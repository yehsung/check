// node --experimental-strip-types --test components/install/install-copy.test.ts
// data/install-copy.ts 의 installChoice()(숫자 격자 4번 칸 · 설치 주 버튼)와 문장 정리(v1 문장 0)를 고정한다.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { asMbFigure, installChoice, INSTALL_COPY } from '../../data/install-copy.ts';
import type { ReleaseInfo } from '../../data/fixtures.ts';

const dmg = (bytes: number, mb: string) => ({ name: 'aing-check.dmg' as const, url: 'https://x/aing-check.dmg', bytes, mb });
const zip = (bytes: number, mb: string) => ({ name: 'aing-check.zip' as const, url: 'https://x/aing-check.zip', bytes, mb });

// RELEASE_FALLBACK 과 같은 값(fixtures.ts 는 JSON import 가 있어 node 로 못 불러온다 — 아래 소스 대조 테스트가 같은지 본다)
const FALLBACK: ReleaseInfo = {
  version: '0.3.49',
  publishedAt: null,
  dmg: dmg(30054068, '30.1'),
  zip: zip(28343288, '28.3'),
  source: 'fallback',
};

test('installChoice: DMG 가 있으면 dmg · 라벨 · 접근 이름 · 크기 · 버전', () => {
  const r: ReleaseInfo = { version: '0.3.50', publishedAt: null, dmg: dmg(31_250_000, '31.3'), zip: zip(29e6, '29.0'), source: 'github' };
  assert.deepEqual(installChoice(r, FALLBACK), {
    file: 'dmg',
    label: 'aing-check.dmg 다운로드',
    ariaLabel: 'aing-check.dmg 다운로드, 31.3MB',
    mb: '31.3',
    version: '0.3.50',
  });
});

test('installChoice: DMG 없으면 zip 크기(SPEC §S5 4번 칸 "DMG 없으면 zip")', () => {
  const r: ReleaseInfo = { version: '0.3.40', publishedAt: null, dmg: null, zip: zip(28_100_000, '28.1'), source: 'github' };
  const c = installChoice(r, FALLBACK);
  assert.equal(c.file, 'zip');
  assert.equal(c.label, 'aing-check.zip 다운로드');
  assert.equal(c.mb, '28.1');
  assert.equal(c.version, '0.3.40');
});

test('installChoice: 자산이 둘 다 없으면 폴백(0.3.49 · 30.1)', () => {
  const r: ReleaseInfo = { version: '9.9.9', publishedAt: null, dmg: null, zip: null, source: 'github' };
  const c = installChoice(r, FALLBACK);
  assert.equal(c.mb, '30.1');
  assert.equal(c.version, '0.3.49');
  assert.equal(c.ariaLabel, 'aing-check.dmg 다운로드, 30.1MB');
});

test('installChoice: mb 문자열이 이상하면 바이트에서 같은 식(소수 한 자리)으로', () => {
  const r: ReleaseInfo = { version: '0.3.51', publishedAt: null, dmg: dmg(30_054_068, '30,1MB'), zip: null, source: 'github' };
  assert.equal(installChoice(r, FALLBACK).mb, '30.1');
  const r2: ReleaseInfo = { ...r, dmg: dmg(29_959_634, '') };
  assert.equal(installChoice(r2, FALLBACK).mb, '30.0');
});

test('asMbFigure: 숫자.숫자 만 통과', () => {
  assert.equal(asMbFigure('30.1'), '30.1');
  assert.equal(asMbFigure('130.25'), '130.25');
  for (const bad of ['30', '30.', '.1', '30.1MB', '', null, undefined, '3O.1']) assert.equal(asMbFigure(bad), null);
});

test('RELEASE_FALLBACK(fixtures.ts 소스)이 0.3.49 · dmg 30.1 · zip 28.3 이고 위 FALLBACK 과 같다', () => {
  const src = readFileSync(new URL('../../data/fixtures.ts', import.meta.url), 'utf8');
  const block = src.slice(src.indexOf('export const RELEASE_FALLBACK'));
  assert.match(block, /version:\s*'0\.3\.49'/);
  assert.match(block, /name:\s*'aing-check\.dmg',[^}]*bytes:\s*30054068,\s*mb:\s*'30\.1'/);
  assert.match(block, /name:\s*'aing-check\.zip',[^}]*bytes:\s*28343288,\s*mb:\s*'28\.3'/);
});

test('INSTALL_COPY: 업데이트 한 줄 = DECISIONS D18 문장, v1 문장(DMG 덮어쓰기·brew 에서만·installHint) 0', () => {
  assert.equal(
    INSTALL_COPY.updateLine,
    '새 버전이 나오면 메뉴바 아이콘에 작은 점이 떠요. 지금 업데이트 한 번이면 설치하고 다시 켜져요.',
  );
  const src = readFileSync(new URL('../../data/install-copy.ts', import.meta.url), 'utf8');
  for (const gone of ['덮어쓰', 'brew 설치에서만', 'brew로 설치했다면', 'installHint', 'stepsDmg', 'stepsZip', 'retry', '경고 없이']) {
    assert.equal(src.includes(gone), false, `install-copy.ts 에 '${gone}' 이 남아 있다`);
  }
});

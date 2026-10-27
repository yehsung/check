// node --experimental-strip-types --test components/hero/copy.test.ts
// 히어로 문장 계약(docs/v3/brief.md §8): 정본 글자 그대로 · H1 두 줄 · 접근 이름 형식 · 금지어 0.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { HERO_COPY, heroCtaAriaLabel } from './copy.ts';

const BRIEF = readFileSync(new URL('../../docs/v3/brief.md', import.meta.url), 'utf8');
const S8 = BRIEF.slice(BRIEF.indexOf('## 8.'));
const hero = S8.slice(S8.indexOf('\n히어로'), S8.indexOf('\n핵심 기능'));
// v3.1(§9.4.1): 폰(< 768)·iOS 기기의 버튼 줄 아래 메타
const S94 = BRIEF.slice(BRIEF.indexOf('### 9.4'));
const phoneCta = S94.slice(0, S94.indexOf('\n2. '));

const FORBIDDEN = [
  '오픈소스', '판돈', '베팅', '내기', '걸고', '체험', '눌러 보세요', 'Learn more', '더보기', 'Mac 링크 보내기', 'Gemini',
  '작은 팀', 'AI 토큰 리밋',
];

test('H1 = §8 두 줄 그대로(줄마다 <br>), 쉼표로 억지로 끊지 않는다', () => {
  assert.ok(hero.includes(`\`${HERO_COPY.h1[0]}\` / \`${HERO_COPY.h1[1]}\``), '§8 히어로 H1');
  assert.equal(HERO_COPY.h1.length, 2);
  for (const line of HERO_COPY.h1) assert.ok(!/,$/.test(line), `쉼표 끝 '${line}'`);
});

test('리드·주 버튼·메타·작은 링크 = §8 글자 그대로 · 폰/iOS 메타 = §9.4.1 글자 그대로', () => {
  for (const s of [HERO_COPY.lead, HERO_COPY.cta, HERO_COPY.meta, HERO_COPY.install]) {
    assert.ok(hero.includes(`\`${s}\``), `§8 에 없음: ${s}`);
  }
  assert.ok(phoneCta.includes(`\`${HERO_COPY.metaPhone}\``), `§9.4.1 에 없음: ${HERO_COPY.metaPhone}`);
  assert.ok(phoneCta.includes('App Store 배지') && phoneCta.includes('[Mac용 다운로드]'), '§9.4.1 은 배지 + Mac용 다운로드 규칙');
});

test('Hero.tsx: 폰·iOS 는 App Store 배지가 먼저 · Mac용 다운로드는 설치 절로 · brew 알약은 넓은 벌에만', () => {
  const src = readFileSync(new URL('./Hero.tsx', import.meta.url), 'utf8')
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:'"`])\/\/.*$/gm, '$1');
  const wide = src.indexOf('<span className={WIDE}>');
  const narrow = src.indexOf('<span className={NARROW}>');
  assert.ok(wide > 0 && narrow > wide, '두 벌(WIDE · NARROW)');
  const wideBlock = src.slice(wide, narrow);
  const narrowBlock = src.slice(narrow, src.indexOf('</span>', src.indexOf('<GlassFx', narrow)));
  assert.match(wideBlock, /<DownloadCTA[\s\S]*<BrewPill/, '넓은 벌: 주 버튼 → brew 알약');
  assert.ok(narrowBlock.indexOf('<AppStoreBadge') >= 0 && narrowBlock.indexOf('<AppStoreBadge') < narrowBlock.indexOf('LINKS.install'), '좁은 벌: 배지 → Mac용 다운로드');
  assert.ok(!/<BrewPill/.test(narrowBlock), '좁은 벌엔 brew 알약 없음');
  assert.match(src, /const NARROW = '[^']*phone:contents[^']*\[html\[data-platform=ios\]_&\]:contents/, '폰 폭·iOS 기기 모두 같은 규칙');
});

test("brew 알약 복사 접근 이름 = §8 'brew 설치 명령 복사' · 보이는 '복사' 를 포함", () => {
  assert.ok(hero.includes(`\`${HERO_COPY.brewCopyAria}\``));
  assert.ok(HERO_COPY.brewCopyAria.includes('복사'));
});

test("주 버튼 접근 이름: 'Mac용 다운로드, aing-check.dmg {mb}MB' · DMG 없으면 zip · 둘 다 없으면 fallback", () => {
  const asset = (name: 'aing-check.dmg' | 'aing-check.zip', mb: string) => ({ name, url: 'https://x', bytes: 1, mb });
  const base = { version: '9.9.9', publishedAt: null, source: 'github' as const };
  const fb = { ...base, source: 'fallback' as const, dmg: asset('aing-check.dmg', '30.1'), zip: null };
  assert.equal(heroCtaAriaLabel({ ...base, dmg: asset('aing-check.dmg', '31.2'), zip: null }, fb), 'Mac용 다운로드, aing-check.dmg 31.2MB');
  assert.equal(heroCtaAriaLabel({ ...base, dmg: null, zip: asset('aing-check.zip', '28.3') }, fb), 'Mac용 다운로드, aing-check.zip 28.3MB');
  assert.equal(heroCtaAriaLabel({ ...base, dmg: null, zip: null }, fb), 'Mac용 다운로드, aing-check.dmg 30.1MB');
});

test('금지어 0', () => {
  const text = Object.values(HERO_COPY).flat().join('\n');
  for (const w of FORBIDDEN) assert.ok(!text.includes(w), `금지어 '${w}'`);
});

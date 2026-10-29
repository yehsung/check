// node --experimental-strip-types --test lib/seo.test.ts
// SEO 계약(docs/v3/brief.md §10 · docs/v3/seo.md): 문구 = §8 메타·§10 글자 그대로 · 소유 확인 메타는 값이 있을 때만 ·
// JSON-LD 는 화면과 같은 출처(별점·리뷰 0) · sitemap url = canonical · robots 그룹마다 /api/ 막음 · llms.txt 내용 · IndexNow 키 파일 · 금지어 0.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { FEATURE_COPY } from '../components/features/copy.ts';
import { jsonLdHtml } from '../components/faq/jsonld.ts';
import { FAQ_ITEMS } from '../data/faq-items.ts';
import { INSTALL_COPY, metaParts } from '../data/install-copy.ts';
import {
  ALT_NAME,
  CONTENT_UPDATED,
  DELETE_ACCOUNT_PATH,
  DESCRIPTION,
  INDEXNOW_KEY,
  LLMS_SUMMARY,
  LOGO,
  ROBOTS_AGENTS,
  ROBOTS_META,
  TITLE,
  absUrl,
  homeJsonLd,
  kstDate,
  laterDate,
  llmsTxt,
  robotsConfig,
  sitemapEntries,
  verificationFromEnv,
  type SeoChoice,
  type SeoLinks,
} from './seo.ts';

const SITE = 'https://aing-check.vercel.app';
const read = (rel: string) => readFileSync(new URL(rel, import.meta.url), 'utf8');
/** 소스 계약용 — 주석을 걷어낸 본문(faq.test 와 같은 방식). */
const code = (rel: string) =>
  read(rel)
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:"'`])\/\/.*$/gm, '$1');

const BRIEF = read('../docs/v3/brief.md');
const S8 = BRIEF.slice(BRIEF.indexOf('## 8.'), BRIEF.indexOf('## 9.'));
const S10 = BRIEF.slice(BRIEF.indexOf('## 10.'));
const FIXTURES = read('../data/fixtures.ts');
const SITE_LINKS = read('../data/site-links.ts');

/** fixtures.ts 의 LINKS 값(정본 — JSON import 가 있어 node 로 못 불러와 소스에서 읽는다, install-copy.test 와 같은 방식). */
function fixtureLink(key: string): string {
  const m = new RegExp(`\\b${key}: '([^']+)'`).exec(FIXTURES);
  assert.ok(m, `fixtures.ts LINKS.${key} 없음`);
  return m[1];
}
const LINKS: SeoLinks = {
  github: fixtureLink('github'),
  appStore: fixtureLink('appStore'),
  dmgLatest: fixtureLink('dmgLatest'),
  zipLatest: fixtureLink('zipLatest'),
  releases: fixtureLink('releases'),
  privacy: fixtureLink('privacy'),
  terms: fixtureLink('terms'),
  support: fixtureLink('support'),
  licenses: fixtureLink('licenses'),
  install: fixtureLink('install'),
};
const BREW_INSTALL = (/export const BREW = \{\s*install:\s*'([^']+)'/.exec(FIXTURES) ?? [])[1] as string;
/** site-links.ts FOOTER_LINKS · NAV_LINKS(이름 정본)를 소스에서. */
const FOOTER_LINKS = [...SITE_LINKS.matchAll(/\{ id: "(\w+)", label: "([^"]+)", href: LINKS\.(\w+) \}/g)].map((m) => ({
  id: m[1],
  label: m[2],
  href: (LINKS as Record<string, string>)[m[3]] ?? fixtureLink(m[3]),
}));
const NAV_LINKS = [...SITE_LINKS.matchAll(/\{ href: "([^"]+)", label: "([^"]+)" \}/g)].map((m) => ({ href: m[1], label: m[2] }));

const DMG: SeoChoice = { file: 'dmg', label: 'aing-check.dmg 다운로드', version: '0.3.67', mb: '37.7' };
/** 첫 화면 근무 중 팝오버 그림(화면의 <img src> 와 같은 값 — data/generated/assets.json). */
const POPOVER_SRC = (JSON.parse(read('../data/generated/assets.json')) as Record<string, { src: string }>)['ui/popover-working'].src;
const PUBLISHED = '2026-10-29T15:30:00Z'; // KST 10-30 00:30

const FORBIDDEN = ['격자', '작은 팀', '눌러', '누르', 'AI 토큰 리밋', '판돈', '베팅', '안티그래비티', 'brew upgrade'];

// ─── 문구 ───────────────────────────────────────────────────────────────────────────────────────

test('TITLE · DESCRIPTION · LLMS_SUMMARY = 승인 문구 글자 그대로 = brief §8 메타 · §10', () => {
  assert.equal(TITLE, '아잉체크(aing-check): Mac 메뉴바 근무 타이머');
  assert.equal(
    DESCRIPTION,
    '아잉체크는 맥 메뉴바에서 켜는 무료 근무 타이머예요. 근무 시작을 클릭하면 팀원이 근무 중인 걸 보고, Claude Code·Codex·Gemini 리밋과 AI 토큰 사용량 순위, 12주 치 잔디도 봐요.',
  );
  assert.equal(
    LLMS_SUMMARY,
    '아잉체크는 맥 메뉴바에서 켜는 무료 근무 타이머로, 팀원이 근무 중인 걸 보고 Claude Code·Codex·Gemini 리밋과 AI 토큰 사용량 순위, 12주 치 잔디도 봐요.',
  );
  assert.ok(S8.includes(`- title: \`${TITLE}\``), '§8 메타 title');
  assert.ok(S8.includes(`- description: \`${DESCRIPTION}\``), '§8 메타 description');
  for (const s of [TITLE, DESCRIPTION, LLMS_SUMMARY]) assert.ok(S10.includes(`\`${s}\``), `§10 에 ${s.slice(0, 20)}…`);
  for (const s of [TITLE, DESCRIPTION, LLMS_SUMMARY]) for (const w of FORBIDDEN) assert.ok(!s.includes(w), `금지어 '${w}'`);
});

test('layout 메타는 lib/seo 에서 읽는다 · 옛 문구 0 · applicationName · robots · 소유 확인은 값이 있을 때만', () => {
  const layout = code('../app/layout.tsx');
  assert.match(layout, /import \{[^}]*\bDESCRIPTION\b[^}]*\bTITLE\b[^}]*\} from "@\/lib\/seo"/);
  assert.ok(!/const (TITLE|DESCRIPTION) =/.test(layout), 'layout 에 문구를 따로 적지 않는다');
  assert.match(layout, /applicationName: SITE_NAME/);
  assert.match(layout, /robots: ROBOTS_META/);
  assert.match(layout, /verificationFromEnv\(process\.env\)/);
  assert.match(layout, /\.\.\.\(verification \? \{ verification \} : \{\}\)/);
  for (const f of ['../app/layout.tsx', '../app/page.tsx', './seo.ts', '../docs/v3/brief.md']) {
    const s = read(f);
    assert.ok(!s.includes('아잉체크: Mac 메뉴바 근무 타이머'), `${f} 에 옛 title`);
    assert.ok(!s.includes('근무 타이머부터 AI 리밋·토큰 확인'), `${f} 에 옛 description`);
  }
  // 하위 페이지는 자기 제목을 지킨다
  assert.match(code('../app/licenses/page.tsx'), /const TITLE = "아잉체크: 글꼴 라이선스"/);
  assert.match(code('../app/delete-account/page.tsx'), /const TITLE = "아잉체크: 계정 삭제"/);
  // index·follow 는 기본값이라 적지 않는다 — 루트 레이아웃 메타가 404 에도 붙어 'noindex' 옆에 'index, follow' 가 찍히지 않게
  assert.deepEqual(ROBOTS_META, {
    googleBot: { 'max-image-preview': 'large', 'max-snippet': -1, 'max-video-preview': -1 },
  });
  assert.ok(!JSON.stringify(ROBOTS_META).includes('"index"') && !JSON.stringify(ROBOTS_META).includes('"follow"'));
});

// ─── 소유 확인 ───────────────────────────────────────────────────────────────────────────────────

test('verificationFromEnv: 없음·빈 값 → undefined(키 0)', () => {
  assert.equal(verificationFromEnv({}), undefined);
  assert.equal(
    verificationFromEnv({ GOOGLE_SITE_VERIFICATION: '', NAVER_SITE_VERIFICATION: '   ', BING_SITE_VERIFICATION: '\n' }),
    undefined,
  );
  assert.equal(verificationFromEnv({ OTHER: 'x' }), undefined);
});

test('verificationFromEnv: 값 → 정확한 키(google · naver-site-verification · msvalidate.01), 앞뒤 공백 제거', () => {
  assert.deepEqual(
    verificationFromEnv({ GOOGLE_SITE_VERIFICATION: '  g-123  ', NAVER_SITE_VERIFICATION: ' n456\n', BING_SITE_VERIFICATION: 'B789 ' }),
    { google: 'g-123', other: { 'naver-site-verification': 'n456', 'msvalidate.01': 'B789' } },
  );
  assert.deepEqual(verificationFromEnv({ GOOGLE_SITE_VERIFICATION: 'g' }), { google: 'g' });
  assert.deepEqual(verificationFromEnv({ NAVER_SITE_VERIFICATION: 'n' }), { other: { 'naver-site-verification': 'n' } });
  assert.deepEqual(verificationFromEnv({ BING_SITE_VERIFICATION: 'b' }), { other: { 'msvalidate.01': 'b' } });
  // 메타 태그를 통째로 붙여 넣어도 content 만
  assert.deepEqual(
    verificationFromEnv({ NAVER_SITE_VERIFICATION: '<meta name="naver-site-verification" content="abc123" />' }),
    { other: { 'naver-site-verification': 'abc123' } },
  );
  // 값을 감싼 따옴표는 벗긴다(Vercel 화면에 "…" 째로 붙여 넣은 경우) — 짝이 맞을 때만
  assert.deepEqual(verificationFromEnv({ GOOGLE_SITE_VERIFICATION: '"abc123"' }), { google: 'abc123' });
  assert.deepEqual(verificationFromEnv({ BING_SITE_VERIFICATION: " 'B789' " }), { other: { 'msvalidate.01': 'B789' } });
  assert.deepEqual(verificationFromEnv({ NAVER_SITE_VERIFICATION: '`n1`' }), { other: { 'naver-site-verification': 'n1' } });
  assert.deepEqual(verificationFromEnv({ GOOGLE_SITE_VERIFICATION: '"abc' }), { google: '"abc' }, '짝 없는 따옴표는 그대로');
  assert.equal(verificationFromEnv({ GOOGLE_SITE_VERIFICATION: '""' }), undefined, '따옴표뿐이면 빈 값');
});

// ─── JSON-LD ───────────────────────────────────────────────────────────────────────────────────

function graph(choice: SeoChoice = DMG, live = true, screenshot: string = POPOVER_SRC) {
  const ld = homeJsonLd({ links: LINKS, choice, live, screenshot, siteUrl: SITE });
  const byId = new Map(ld['@graph'].map((n) => [n['@id'], n as Record<string, unknown>]));
  return { ld, byId };
}

test('JSON-LD: @graph 넷(WebSite · Organization · Mac 앱 · iPhone 앱)과 @id', () => {
  const { ld, byId } = graph();
  assert.equal(ld['@context'], 'https://schema.org');
  assert.deepEqual(
    ld['@graph'].map((n) => [n['@type'], n['@id']]),
    [
      ['WebSite', `${SITE}/#website`],
      ['Organization', `${SITE}/#organization`],
      ['SoftwareApplication', `${SITE}/#mac-app`],
      ['MobileApplication', `${SITE}/#ios-app`],
    ],
  );
  const site = byId.get(`${SITE}/#website`)!;
  assert.equal(site.url, `${SITE}/`);
  assert.equal(site.name, '아잉체크');
  assert.deepEqual(site.alternateName, ['aing-check']);
  assert.equal(site.inLanguage, 'ko-KR');
  for (const n of ld['@graph'].filter((x) => x['@type'] !== 'Organization')) {
    assert.deepEqual((n as { publisher?: unknown }).publisher, { '@id': `${SITE}/#organization` }, `${n['@type']} publisher`);
  }
});

test('JSON-LD: 영문 이름은 푸터에 보이는 그대로(아잉체크(aing-check))', () => {
  assert.equal(ALT_NAME, 'aing-check');
  assert.ok(code('../components/site/SiteFooter.tsx').includes(`아잉체크(${ALT_NAME})`), '푸터 한 줄');
  assert.ok(TITLE.startsWith(`아잉체크(${ALT_NAME})`));
});

test('JSON-LD: Organization 로고 = public/ 의 정사각 아이콘 · sameAs = 화면의 GitHub · App Store 링크', () => {
  const org = graph().byId.get(`${SITE}/#organization`)!;
  assert.deepEqual(org.logo, { '@type': 'ImageObject', url: `${SITE}${LOGO.path}`, width: 256, height: 256 });
  assert.ok(existsSync(new URL(`../public${LOGO.path}`, import.meta.url)), `public${LOGO.path} 없음`);
  assert.deepEqual(org.sameAs, ['https://github.com/yehsung/check', 'https://apps.apple.com/app/id6812768622']);
  assert.deepEqual(org.sameAs, [LINKS.github, LINKS.appStore]);
});

test('JSON-LD: Mac 앱 = 화면 값(macOS 14 이상 · 무료 · 설치 카드 버전·크기 · 기능 제목 6 · OG 그림 · 화면의 팝오버 스크린샷)', () => {
  const mac = graph().byId.get(`${SITE}/#mac-app`)!;
  assert.equal(mac.name, '아잉체크');
  assert.equal(mac.alternateName, 'aing-check');
  assert.equal(mac.description, DESCRIPTION);
  assert.equal(mac.url, `${SITE}/`);
  assert.equal(mac.operatingSystem, 'macOS 14 이상');
  assert.equal(mac.operatingSystem, INSTALL_COPY.metaTail[0]);
  assert.equal(mac.applicationCategory, 'BusinessApplication');
  assert.deepEqual(mac.offers, { '@type': 'Offer', price: '0', priceCurrency: 'KRW' });
  assert.equal(mac.softwareVersion, '0.3.67');
  assert.equal(`v${mac.softwareVersion}`, metaParts(DMG)[0], '설치 카드 v{ver}');
  assert.equal(mac.fileSize, '37.7MB');
  assert.equal(mac.fileSize, metaParts(DMG)[1], '설치 카드 {mb}MB');
  assert.equal(mac.downloadUrl, LINKS.dmgLatest);
  assert.deepEqual(mac.featureList, FEATURE_COPY.map((c) => `${c.title[0]} ${c.title[1]}`));
  assert.equal((mac.featureList as string[]).length, 6);
  assert.equal(mac.image, `${SITE}/opengraph-image.png`);
  // screenshot = 첫 화면에 실제로 보이는 앱 화면(히어로 <img src>) — OG 합성 그림이 아니다
  assert.match(POPOVER_SRC, /^\/assets\/ui\/popover-working\.webp/);
  assert.equal(mac.screenshot, `${SITE}${POPOVER_SRC}`);
  assert.ok(existsSync(new URL(`../public${POPOVER_SRC.split('?')[0]}`, import.meta.url)), 'public 에 팝오버 그림');
  const noShot = homeJsonLd({ links: LINKS, choice: DMG, live: true, siteUrl: SITE })['@graph'][2];
  assert.ok(!('screenshot' in noShot), '그림이 없으면 screenshot 0');
  // zip 만 있는 릴리스면 받는 주소도 zip(화면 버튼과 같은 파일)
  const zip = graph({ file: 'zip', label: 'aing-check.zip 다운로드', version: '0.3.68', mb: '28.3' }).byId.get(`${SITE}/#mac-app`)!;
  assert.equal(zip.downloadUrl, LINKS.zipLatest);
  assert.equal(zip.fileSize, '28.3MB');
});

test('JSON-LD: 폴백 릴리스(live=false)면 softwareVersion·fileSize 를 싣지 않는다 — 받는 주소는 그대로', () => {
  const fb = graph({ file: 'dmg', label: 'aing-check.dmg 다운로드', version: '0.3.49', mb: '30.1' }, false).byId.get(`${SITE}/#mac-app`)!;
  assert.ok(!('softwareVersion' in fb), 'softwareVersion');
  assert.ok(!('fileSize' in fb), 'fileSize');
  assert.ok(!JSON.stringify(fb).includes('0.3.49') && !JSON.stringify(fb).includes('30.1'), '폴백 숫자 0');
  assert.equal(fb.downloadUrl, LINKS.dmgLatest);
  assert.equal(fb.operatingSystem, 'macOS 14 이상');
});

test('JSON-LD: iPhone 앱 = iOS 18 이상 · 무료 · App Store', () => {
  const ios = graph().byId.get(`${SITE}/#ios-app`)!;
  assert.equal(ios.name, '아잉체크');
  assert.equal(ios.operatingSystem, 'iOS 18 이상');
  assert.ok(INSTALL_COPY.iphoneMeta.startsWith(`${ios.operatingSystem} · `), '아이폰 카드 메타');
  assert.equal(ios.applicationCategory, 'BusinessApplication');
  assert.deepEqual(ios.offers, { '@type': 'Offer', price: '0', priceCurrency: 'KRW' });
  assert.equal(ios.installUrl, LINKS.appStore);
  assert.equal(ios.downloadUrl, LINKS.appStore);
});

test('JSON-LD: 별점·리뷰·평점 0 · 모든 글은 화면 문구에서 · <script> 본문으로 안전(왕복 같음)', () => {
  const { ld } = graph();
  const json = JSON.stringify(ld);
  for (const k of ['aggregateRating', 'review', 'ratingValue', 'ratingCount', 'reviewCount']) assert.ok(!json.includes(k), `'${k}'`);
  // 사람이 읽는 글(주소·스키마 열거값 제외)은 화면 문구 묶음 안에 있다
  const visible = [
    DESCRIPTION,
    `아잉체크(${ALT_NAME})`,
    ...FEATURE_COPY.map((c) => c.title.join(' ')),
    ...metaParts(DMG),
    INSTALL_COPY.iphoneMeta,
  ].join('\n');
  const enums = new Set(['https://schema.org', 'BusinessApplication', 'KRW', '0', 'ko-KR', 'Offer', 'ImageObject']);
  const walk = (v: unknown, key = ''): void => {
    if (typeof v === 'string') {
      if (key.startsWith('@') || enums.has(v) || /^https:\/\//.test(v)) return;
      assert.ok(visible.includes(v), `화면에 없는 글: ${key}=${v}`);
    } else if (Array.isArray(v)) v.forEach((x) => walk(x, key));
    else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) walk(x, k);
  };
  walk(ld);
  const html = jsonLdHtml(ld);
  assert.ok(!html.includes('<'), '< 는 \\u003c 로');
  assert.deepEqual(JSON.parse(html), ld);
});

test('page.tsx: JSON-LD 를 한 번, 설치 카드와 같은 installChoice 값으로 · FAQPage 는 Faq 절 그대로', () => {
  const page = code('../app/page.tsx');
  assert.equal(page.match(/application\/ld\+json/g)?.length, 1);
  assert.match(
    page,
    /homeJsonLd\(\{\s*links: LINKS,\s*choice: installChoice\(release, RELEASE_FALLBACK\),\s*live: release\.source === 'github',\s*screenshot: popover\?\.src,\s*\}\)/,
  );
  assert.match(page, /const popover = asset\('ui\/popover-working'\)/);
  assert.match(page, /jsonLdHtml\(ld\)/);
  assert.match(code('../components/install/Install.tsx'), /installChoice\(release, RELEASE_FALLBACK\)/);
  assert.match(code('../components/faq/Faq.tsx'), /jsonLdHtml\(faqJsonLd\(\)\)/);
});

// ─── sitemap · robots ──────────────────────────────────────────────────────────────────────────

test('sitemap: 페이지 셋, url = 각 페이지 canonical · lastmod 정직(내용 갱신일 vs 최신 릴리스)', () => {
  const entries = sitemapEntries(null, SITE);
  assert.deepEqual(entries.map((e) => e.url), [`${SITE}/`, `${SITE}/licenses`, `${SITE}${DELETE_ACCOUNT_PATH}`]);
  // canonical 과 같은 URL(첫 페이지 canonical 'https://…' 와 'https://…/' 는 WHATWG 정규형이 같다)
  assert.equal(new URL(SITE).href, entries[0].url);
  assert.match(code('../app/layout.tsx'), /alternates: \{ canonical: "\/" \}/);
  assert.match(code('../app/licenses/page.tsx'), /alternates: \{ canonical: "\/licenses" \}/);
  assert.match(code('../app/delete-account/page.tsx'), new RegExp(`alternates: \\{ canonical: "${DELETE_ACCOUNT_PATH}" \\}`));
  assert.ok(existsSync(new URL('../app/licenses/page.tsx', import.meta.url)));
  assert.ok(existsSync(new URL(`../app${DELETE_ACCOUNT_PATH}/page.tsx`, import.meta.url)));
  assert.deepEqual(CONTENT_UPDATED, { home: '2026-10-30', licenses: '2026-10-12', deleteAccount: '2026-10-28' });
  assert.deepEqual(entries.map((e) => e.lastModified), ['2026-10-30', '2026-10-12', '2026-10-28']);
  // 릴리스가 더 늦으면 그 날, 이르면 내용 갱신일
  assert.equal(sitemapEntries('2026-11-02T03:00:00Z', SITE)[0].lastModified, '2026-11-02T03:00:00Z');
  assert.equal(sitemapEntries('2026-10-29T15:30:00Z', SITE)[0].lastModified, '2026-10-30');
  assert.equal(laterDate('2026-10-30', 'not a date'), '2026-10-30');
  for (const e of entries) assert.ok(!Number.isNaN(Date.parse(String(e.lastModified))), String(e.lastModified));
});

test('sitemap.ts · robots.ts 는 lib/seo 생성기를 쓴다 · sitemap 은 1시간 ISR', () => {
  const sm = code('../app/sitemap.ts');
  assert.match(sm, /export const revalidate = 3600/);
  assert.match(sm, /sitemapEntries\(release\.publishedAt\)/);
  assert.match(code('../app/robots.ts'), /robotsConfig\(\)/);
});

test('robots: * + 이름 있는 크롤러 13개, 그룹마다 Disallow /api/ 만(Allow 줄 0 — 순서에 기대지 않는다) · Sitemap 줄', () => {
  const r = robotsConfig(SITE);
  assert.equal(r.sitemap, `${SITE}/sitemap.xml`);
  const rules = Array.isArray(r.rules) ? r.rules : [r.rules];
  assert.deepEqual(rules.map((x) => x.userAgent), ['*', ...ROBOTS_AGENTS]);
  assert.deepEqual([...ROBOTS_AGENTS], [
    'Yeti', 'Bingbot', 'Googlebot', 'GPTBot', 'OAI-SearchBot', 'ChatGPT-User', 'ClaudeBot', 'Claude-SearchBot', 'Claude-User',
    'PerplexityBot', 'Perplexity-User', 'Google-Extended', 'Applebot-Extended',
  ]);
  for (const x of rules) {
    assert.ok(!('allow' in x), `${x.userAgent} allow 없음`);
    assert.equal(x.disallow, '/api/', `${x.userAgent} disallow`);
  }
});

// ─── llms.txt ──────────────────────────────────────────────────────────────────────────────────

function llms(publishedAt: string | null = PUBLISHED, choice: SeoChoice = DMG, live = true) {
  return llmsTxt({
    links: LINKS,
    brewInstall: BREW_INSTALL,
    choice,
    live,
    publishedAt,
    footerLinks: FOOTER_LINKS,
    navLinks: NAV_LINKS,
    siteUrl: SITE,
  });
}

test('llms.txt: llmstxt.org 꼴 — # 이름 · > 요약 · 제목 없는 본문 · H2 는 링크 목록 하나 · 다른 제목 0', () => {
  const t = llms();
  assert.ok(t.startsWith(`# 아잉체크 (aing-check)\n\n> ${LLMS_SUMMARY}\n\n`), t.slice(0, 120));
  const heads = t.split('\n').filter((l) => /^#{1,6} /.test(l));
  assert.deepEqual(heads, ['# 아잉체크 (aing-check)', '## 링크']);
  // H2 아래는 '- [이름](주소)' 줄만(참조 파서가 링크 아닌 줄을 버린다)
  const sec = t.slice(t.indexOf('## 링크\n') + '## 링크\n'.length).split('\n').filter((l) => l.trim());
  for (const l of sec) assert.match(l, /^- \[[^\]]+\]\(https:\/\/[^)]+\)$/, l);
  assert.ok(t.endsWith('\n'));
});

test('llms.txt: 본문 이름표 = 화면 내비 이름(설치 · 기능 · 자주 묻는 질문) · 첫 줄 = 폰 히어로 메타', () => {
  const t = llms();
  const labels = [...t.matchAll(/^\*\*([^*]+)\*\*$/gm)].map((m) => m[1]);
  assert.deepEqual(labels, ['설치', '기능', '자주 묻는 질문']);
  for (const l of labels) assert.ok(NAV_LINKS.some((n) => n.label === l), `내비에 '${l}'`);
  assert.ok(t.includes(`> ${LLMS_SUMMARY}\n\n무료 · iOS 18 이상 · macOS 14 이상\n\n**설치**`));
  assert.ok(read('../components/hero/copy.ts').includes("metaPhone: '무료 · iOS 18 이상 · macOS 14 이상'"));
});

test('llms.txt: 설치 = brew 명령 · DMG(설치 카드 메타 줄 그대로) · App Store · GitHub 릴리스 버전·날(KST)', () => {
  const t = llms();
  assert.equal(BREW_INSTALL, 'brew install yehsung/check/aing-check');
  assert.ok(t.includes(`\n- Homebrew: \`${BREW_INSTALL}\` — ${INSTALL_COPY.sub}\n`));
  assert.ok(t.includes(`\n- DMG: [aing-check.dmg 다운로드](${LINKS.dmgLatest}) — ${metaParts(DMG).join(' · ')}. ${INSTALL_COPY.dmgLine}\n`));
  assert.ok(t.includes('v0.3.67 · 37.7MB · macOS 14 이상 · Apple Silicon·Intel · Apple 공증'), '설치 카드 메타 줄');
  assert.ok(t.includes(`\n- iPhone: [App Store](${LINKS.appStore}) — iOS 18 이상 · 무료\n`));
  assert.ok(t.includes(`\n- [GitHub 릴리스](${LINKS.releases}): v0.3.67 (2026-10-30)\n`));
  assert.equal(kstDate(PUBLISHED), '2026-10-30');
  // 날짜가 없으면 날짜를 지어내지 않는다
  const noDate = llms(null);
  assert.ok(noDate.includes(`\n- [GitHub 릴리스](${LINKS.releases}): v0.3.67\n`));
  assert.ok(!/\d{4}-\d{2}-\d{2}/.test(noDate));
});

test('llms.txt: 폴백 릴리스(live=false)면 버전·크기·날을 싣지 않는다', () => {
  const fb = llms(null, { file: 'dmg', label: 'aing-check.dmg 다운로드', version: '0.3.49', mb: '30.1' }, false);
  assert.ok(!fb.includes('0.3.49') && !fb.includes('30.1MB'), '폴백 숫자 0');
  assert.ok(fb.includes(`\n- DMG: [aing-check.dmg 다운로드](${LINKS.dmgLatest}) — ${INSTALL_COPY.metaTail.join(' · ')}. ${INSTALL_COPY.dmgLine}\n`));
  assert.ok(fb.includes(`\n- [GitHub 릴리스](${LINKS.releases})\n`));
  // live 인데 날이 있어도, live=false 면 날도 0
  assert.ok(!/\d{4}-\d{2}-\d{2}/.test(llms(PUBLISHED, DMG, false)));
});

test('llms.txt: 기능 6 · FAQ 5(질문·답 글자 그대로)', () => {
  const t = llms();
  for (const c of FEATURE_COPY) assert.ok(t.includes(`\n- ${c.title.join(' ')}: ${c.body}\n`), c.id);
  assert.equal(FAQ_ITEMS.length, 5);
  for (const it of FAQ_ITEMS) assert.ok(t.includes(`\n- **${it.q}**\n  ${it.a}\n`), it.q);
});

test('llms.txt: 링크 8개는 절대 주소 · 이름은 사이트 이름·푸터·내비 정본 · 지어낸 문장 0', () => {
  const t = llms();
  const sec = t.slice(t.indexOf('## 링크'));
  const links = [...sec.matchAll(/^- \[([^\]]+)\]\(([^)]+)\)$/gm)].map((m) => [m[1], m[2]]);
  assert.deepEqual(links, [
    ['아잉체크', `${SITE}/`],
    ['설치', `${SITE}/#install`],
    ['개인정보 처리방침', LINKS.privacy],
    ['이용약관', LINKS.terms],
    ['지원', LINKS.support],
    ['GitHub', LINKS.github],
    ['계정 삭제', `${SITE}/delete-account`],
    ['글꼴 라이선스', `${SITE}/licenses`],
  ]);
  assert.match(code('../app/delete-account/page.tsx'), /const TITLE = "아잉체크: 계정 삭제"/, "'계정 삭제' = 그 페이지 제목");
  // 문서 안 모든 마크다운 링크가 절대 주소
  for (const m of t.matchAll(/\]\(([^)]+)\)/g)) assert.match(m[1], /^https:\/\//, m[1]);
  // 승인 안 된 설명 문장·이름표 0(검증 지적: '이 문서에 대해' 해라체 문장 · '핵심 정보' · '최신 Mac 버전' · '홈')
  for (const w of ['이 문서에 대해', '다시 만든다', '핵심 정보', '최신 Mac 버전', '[홈]', '최신']) assert.ok(!t.includes(w), `'${w}'`);
});

test('llms.txt: 금지어 0 · 업데이트 명령 0 · 별점·숫자 주장 0', () => {
  const t = llms();
  for (const w of FORBIDDEN) assert.ok(!t.includes(w), `금지어 '${w}'`);
  for (const w of ['별점', '평점', '다운로드 수', '사용자 수', '만 명']) assert.ok(!t.includes(w), `'${w}'`);
});

test('llms.txt 라우트: text/plain; charset=utf-8 · Cache-Control(/api/release 와 같은 값) · 1시간 ISR · live = source github', () => {
  const route = code('../app/llms.txt/route.ts');
  assert.match(route, /export const revalidate = 3600/);
  assert.match(route, /"Content-Type": "text\/plain; charset=utf-8"/);
  assert.match(route, /"Cache-Control": "public, s-maxage=3600, stale-while-revalidate=86400"/);
  // /api/release 와 같은 캐시 머리(값이 갈라지면 빨강)
  const cc = /["']Cache-Control["']:\s*["']([^"']+)["']/.exec(code('../app/api/release/route.ts'));
  assert.ok(cc, 'api/release Cache-Control');
  assert.equal(cc[1], 'public, s-maxage=3600, stale-while-revalidate=86400');
  assert.match(route, /llmsTxt\(\{/);
  assert.match(route, /installChoice\(release, RELEASE_FALLBACK\)/);
  assert.match(route, /live: release\.source === "github"/);
});

// ─── IndexNow ──────────────────────────────────────────────────────────────────────────────────

test('IndexNow: 키 32자 16진 · public/<키>.txt 내용 = 키 하나 · 키 파일은 하나뿐', () => {
  assert.match(INDEXNOW_KEY, /^[0-9a-f]{32}$/);
  const file = new URL(`../public/${INDEXNOW_KEY}.txt`, import.meta.url);
  assert.ok(existsSync(file), `public/${INDEXNOW_KEY}.txt 없음`);
  assert.equal(readFileSync(file, 'utf8'), INDEXNOW_KEY);
  const keyFiles = readdirSync(new URL('../public/', import.meta.url)).filter((f) => /^[0-9a-f]{32}\.txt$/.test(f));
  assert.deepEqual(keyFiles, [`${INDEXNOW_KEY}.txt`]);
});

test('IndexNow 스크립트: npm run indexnow · 빌드에 안 걸림 · 두 엔드포인트 · --dry-run · 키는 lib/seo 에서', () => {
  const pkg = JSON.parse(read('../package.json')) as { scripts: Record<string, string> };
  assert.equal(pkg.scripts.indexnow, 'node scripts/indexnow.mjs');
  for (const k of ['prebuild', 'build', 'postbuild', 'start']) {
    assert.ok(!(pkg.scripts[k] ?? '').includes('indexnow'), `${k} 에 indexnow`);
    assert.ok(!(pkg.scripts[k] ?? '').includes('seo-smoke'), `${k} 에 seo-smoke`);
  }
  assert.equal(pkg.scripts['seo:smoke'], 'node --experimental-strip-types scripts/seo-smoke.mjs');
  const s = read('../scripts/indexnow.mjs');
  assert.ok(s.includes('https://api.indexnow.org/indexnow'));
  assert.ok(s.includes('https://searchadvisor.naver.com/indexnow'));
  assert.ok(s.includes('--dry-run'));
  assert.ok(s.includes('export const INDEXNOW_KEY = "([0-9a-f]{32})"'), '스크립트가 읽는 꼴');
  assert.match(read('./seo.ts'), new RegExp(`export const INDEXNOW_KEY = "${INDEXNOW_KEY}"`));
});

test('absUrl: 경로 → 절대 · 절대는 그대로', () => {
  assert.equal(absUrl('/', SITE), `${SITE}/`);
  assert.equal(absUrl('/#install', `${SITE}/`), `${SITE}/#install`);
  assert.equal(absUrl('https://github.com/yehsung/check', SITE), 'https://github.com/yehsung/check');
});

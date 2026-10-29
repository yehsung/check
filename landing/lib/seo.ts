// lib/seo.ts — 검색·답변 엔진용 정본(docs/v3/brief.md §10 · docs/v3/seo.md). 상수 + 순수 함수.
// - 문장은 화면이 그리는 같은 상수(FEATURE_COPY · FAQ_ITEMS · INSTALL_COPY · HERO_COPY · OG_IMAGE)에서만 가져온다 — 화면에 없는 사실 0,
//   별점·리뷰·지어낸 숫자 0, 숨긴 글 0. 버전·크기는 설치 카드와 같은 installChoice() 값.
// - LINKS·BREW·FOOTER_LINKS(data/fixtures.ts · data/site-links.ts)는 JSON import 가 있어 node --test 가 못 불러온다 →
//   부르는 쪽(app/page.tsx · app/llms.txt/route.ts)이 넘긴다. 여기 런타임 import 는 node 로 바로 읽히는 파일만(.ts 확장자 — lib/seo.test.ts).
// - 메타·LD·llms.txt 글자는 Pretendard 서브셋으로 그리지 않는다(검색 결과·기계가 읽는 글) — 그래서 check-glyphs 가 보는 app/·components/·data/ 가 아니라 여기 둔다.

import type { Metadata, MetadataRoute } from "next";
import { FEATURE_COPY } from "../components/features/copy.ts";
import { HERO_COPY } from "../components/hero/copy.ts";
import { FAQ_ITEMS } from "../data/faq-items.ts";
import { INSTALL_COPY, metaParts, type InstallChoice } from "../data/install-copy.ts";
import { OG_IMAGE, SITE_NAME, SITE_URL } from "./site.ts";

// ─── 문구(docs/v3/brief.md §8 메타 · §10 — 글자 그대로) ─────────────────────────────────────────

/** title · og:title · twitter:title */
export const TITLE = "아잉체크(aing-check): Mac 메뉴바 근무 타이머";
/** meta description · og/twitter description */
export const DESCRIPTION =
  "아잉체크는 맥 메뉴바에서 켜는 무료 근무 타이머예요. 근무 시작을 클릭하면 팀원이 근무 중인 걸 보고, Claude Code·Codex·Gemini 리밋과 AI 토큰 사용량 순위, 12주 치 잔디도 봐요.";
/** llms.txt 맨 위 '> ' 한 줄 */
export const LLMS_SUMMARY =
  "아잉체크는 맥 메뉴바에서 켜는 무료 근무 타이머로, 팀원이 근무 중인 걸 보고 Claude Code·Codex·Gemini 리밋과 AI 토큰 사용량 순위, 12주 치 잔디도 봐요.";
/** 영문 이름 — 푸터 '아잉체크(aing-check)' 와 title 에 보인다. */
export const ALT_NAME = "aing-check";

/** IndexNow 키(public/<키>.txt 의 유일한 내용 — scripts/indexnow.mjs 가 이 줄을 읽는다). */
export const INDEXNOW_KEY = "2222ffef55f40d5ebd1b1e70838d8dec";

/** 페이지 내용이 마지막으로 바뀐 날(sitemap lastmod). licenses = git log landing/app/licenses(a422c6a6) · delete-account = 4cf98bfb. */
export const CONTENT_UPDATED = { home: "2026-10-30", licenses: "2026-10-12", deleteAccount: "2026-10-28" } as const;

/** 계정 삭제 경로(app/delete-account — canonical 과 같다). LINKS 에 없는 유일한 공개 경로라 여기 둔다. */
export const DELETE_ACCOUNT_PATH = "/delete-account";

/** 조직 로고 — public/ 의 정사각 아이콘(256×256 WebP, 구글 최소 112px 이상). */
export const LOGO = { path: "/assets/brand/icon-256.webp", width: 256, height: 256 } as const;

// ─── 부르는 쪽이 넘기는 값 ─────────────────────────────────────────────────────────────────────

/** data/fixtures.ts LINKS 중 여기서 쓰는 것. */
export type SeoLinks = {
  readonly github: string;
  readonly appStore: string;
  readonly dmgLatest: string;
  readonly zipLatest: string;
  readonly releases: string;
  readonly privacy: string;
  readonly terms: string;
  readonly support: string;
  readonly licenses: string;
  readonly install: string;
};
export type SeoChoice = Pick<InstallChoice, "file" | "label" | "version" | "mb">;
export type SeoFooterLink = { readonly id: string; readonly label: string; readonly href: string };
export type SeoNavLink = { readonly href: string; readonly label: string };

// ─── 작은 도구 ─────────────────────────────────────────────────────────────────────────────────

/** 경로 → 절대 주소(이미 절대면 그대로). '/' → 'https://…/'(WHATWG 정규형 — canonical 의 'https://…' 와 같은 URL). */
export function absUrl(pathOrUrl: string, siteUrl: string = SITE_URL): string {
  return new URL(pathOrUrl, siteUrl.replace(/\/+$/, "") + "/").href;
}

/** 'macOS 14 이상' — 화면 메타 줄(설치 카드 · 히어로)의 그 항목. */
export const MAC_REQUIREMENT: string = INSTALL_COPY.metaTail[0];
/** 'iOS 18 이상' — 아이폰 카드 'iOS 18 이상 · 무료' 의 앞 항목. */
export const IOS_REQUIREMENT: string = INSTALL_COPY.iphoneMeta.split(" · ")[0];

/** 기능 제목 두 줄을 화면처럼 한 줄로('한 번 클릭으로 시작하고 다시 클릭으로 마무리해요'). */
export const FEATURE_TITLES: readonly string[] = FEATURE_COPY.map((c) => c.title.join(" "));

/** 둘 중 늦은 날(같으면 a). b 가 없거나 날짜가 아니면 a. 값은 받은 문자열 그대로. */
export function laterDate(a: string, b: string | null | undefined): string {
  if (!b) return a;
  const tb = Date.parse(b);
  if (Number.isNaN(tb)) return a;
  return tb > Date.parse(a) ? b : a;
}

/** ISO 시각 → 한국 날짜 'YYYY-MM-DD'(KST = UTC+9). 날짜가 아니면 null. */
export function kstDate(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  return new Date(t + 9 * 3600_000).toISOString().slice(0, 10);
}

// ─── <head> 메타 ──────────────────────────────────────────────────────────────────────────────

/**
 * googlebot 메타 — 큰 미리보기·스니펫 길이 제한 없음. index·follow 는 기본값이라 적지 않는다:
 * 루트 레이아웃 메타는 404 화면에도 붙어서, 적으면 Next 가 404 에 내는 'noindex' 옆에 'index, follow' 가 같이 찍힌다.
 */
export const ROBOTS_META = {
  googleBot: { "max-image-preview": "large", "max-snippet": -1, "max-video-preview": -1 },
} as const satisfies Metadata["robots"];

/**
 * 검색 콘솔 소유 확인 값을 환경 변수에서. 빈 값은 내지 않는다(키도 없음).
 * 메타 태그를 통째로 붙여 넣어도 content 만 꺼내고, 값을 감싼 따옴표(" ' `)는 벗긴다. DNS TXT 값은 메타 값과 달라 그대로 둔다(docs/v3/seo.md §2).
 */
export function verificationFromEnv(env: Readonly<Record<string, string | undefined>>): Metadata["verification"] | undefined {
  const read = (name: string): string | null => {
    const raw = env[name]?.trim();
    if (!raw) return null;
    const m = /content\s*=\s*["']([^"']+)["']/i.exec(raw);
    let v = (m ? m[1] : raw).trim();
    const q = /^(["'`])([\s\S]*)\1$/.exec(v);
    if (q) v = q[2].trim();
    return v || null;
  };
  const google = read("GOOGLE_SITE_VERIFICATION");
  const naver = read("NAVER_SITE_VERIFICATION");
  const bing = read("BING_SITE_VERIFICATION");
  const other: Record<string, string> = {};
  if (naver) other["naver-site-verification"] = naver;
  if (bing) other["msvalidate.01"] = bing;
  const out: NonNullable<Metadata["verification"]> = {};
  if (google) out.google = google;
  if (Object.keys(other).length > 0) out.other = other;
  return Object.keys(out).length > 0 ? out : undefined;
}

// ─── 첫 페이지 JSON-LD(@graph) ────────────────────────────────────────────────────────────────

export interface HomeLdInput {
  links: Pick<SeoLinks, "github" | "appStore" | "dmgLatest" | "zipLatest">;
  /** 설치 카드와 같은 값(installChoice(release, RELEASE_FALLBACK)) */
  choice: SeoChoice;
  /**
   * release.source === "github". false = GitHub 실패로 RELEASE_FALLBACK(손으로 적은 상수 — 낡을 수 있다)을 받은 것 →
   * softwareVersion·fileSize 를 싣지 않는다(ISR 이 그 값을 1시간 굳혀도 크롤러에 낡은 버전이 안 나간다).
   */
  live: boolean;
  /** 화면에 보이는 앱 화면 그림 경로(첫 화면 근무 중 팝오버 — asset('ui/popover-working').src). 없으면 screenshot 을 싣지 않는다. */
  screenshot?: string;
  siteUrl?: string;
}

/** WebSite · Organization · Mac SoftwareApplication · iPhone MobileApplication. 별점·리뷰 없음. */
export function homeJsonLd({ links, choice, live, screenshot, siteUrl = SITE_URL }: HomeLdInput) {
  const home = absUrl("/", siteUrl);
  const id = (frag: string) => `${home}#${frag}`;
  const org = { "@id": id("organization") };
  const free = { "@type": "Offer", price: "0", priceCurrency: "KRW" } as const;
  const ogImage = absUrl(OG_IMAGE.url, siteUrl);
  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "WebSite",
        "@id": id("website"),
        url: home,
        name: SITE_NAME,
        alternateName: [ALT_NAME],
        inLanguage: "ko-KR",
        publisher: org,
      },
      {
        "@type": "Organization",
        "@id": id("organization"),
        name: SITE_NAME,
        url: home,
        logo: { "@type": "ImageObject", url: absUrl(LOGO.path, siteUrl), width: LOGO.width, height: LOGO.height },
        sameAs: [links.github, links.appStore],
      },
      {
        "@type": "SoftwareApplication",
        "@id": id("mac-app"),
        name: SITE_NAME,
        alternateName: ALT_NAME,
        description: DESCRIPTION,
        url: home,
        operatingSystem: MAC_REQUIREMENT,
        applicationCategory: "BusinessApplication",
        offers: free,
        // 설치 카드 'v{ver}' · 메타 줄의 '{mb}MB' 그 항목 — GitHub 에서 받은 값일 때만
        ...(live ? { softwareVersion: choice.version } : {}),
        downloadUrl: choice.file === "dmg" ? links.dmgLatest : links.zipLatest,
        ...(live ? { fileSize: metaParts(choice)[1] } : {}),
        featureList: [...FEATURE_TITLES],
        image: ogImage,
        ...(screenshot ? { screenshot: absUrl(screenshot, siteUrl) } : {}),
        publisher: org,
      },
      {
        "@type": "MobileApplication",
        "@id": id("ios-app"),
        name: SITE_NAME,
        operatingSystem: IOS_REQUIREMENT,
        applicationCategory: "BusinessApplication",
        offers: free,
        installUrl: links.appStore,
        downloadUrl: links.appStore,
        publisher: org,
      },
    ],
  };
}

// ─── sitemap.xml · robots.txt ────────────────────────────────────────────────────────────────

/** 공개 페이지 셋. url = 각 페이지 canonical. 첫 페이지 lastmod = 내용 갱신일과 최신 릴리스(버전이 화면에 보인다) 중 늦은 날. */
export function sitemapEntries(publishedAt: string | null, siteUrl: string = SITE_URL): MetadataRoute.Sitemap {
  return [
    { url: absUrl("/", siteUrl), lastModified: laterDate(CONTENT_UPDATED.home, publishedAt), changeFrequency: "weekly", priority: 1 },
    { url: absUrl("/licenses", siteUrl), lastModified: CONTENT_UPDATED.licenses, changeFrequency: "yearly", priority: 0.2 },
    { url: absUrl(DELETE_ACCOUNT_PATH, siteUrl), lastModified: CONTENT_UPDATED.deleteAccount, changeFrequency: "yearly", priority: 0.3 },
  ];
}

/** 검색·AI 크롤러를 이름으로 적어 정책을 분명히 한다('*' 와 같은 규칙 — /api/ 말고 모두 허용). */
export const ROBOTS_AGENTS = [
  "Yeti", // 네이버
  "Bingbot",
  "Googlebot",
  "GPTBot",
  "OAI-SearchBot",
  "ChatGPT-User",
  "ClaudeBot",
  "Claude-SearchBot",
  "Claude-User",
  "PerplexityBot",
  "Perplexity-User",
  "Google-Extended",
  "Applebot-Extended",
] as const;
/** /api/ = DMG 302(37MB 대) · 릴리스 JSON — 긁어 갈 내용이 없다. */
export const ROBOTS_DISALLOW = "/api/";

/**
 * 이름 있는 그룹은 '*' 를 상속하지 않으므로(RFC 9309) 그룹마다 같은 Disallow 를 단다.
 * 'Allow: /' 는 적지 않는다 — 막지 않은 곳은 원래 허용이고, Next 는 Allow 를 Disallow 보다 먼저 찍어서
 * 첫 줄부터 맞추는 옛 파서는 'Allow: /' 에 먼저 걸려 /api/ 까지 허용한다(가장 긴 규칙 우선이 아니어도 뜻이 같게).
 */
export function robotsConfig(siteUrl: string = SITE_URL): MetadataRoute.Robots {
  return {
    rules: [
      { userAgent: "*", disallow: ROBOTS_DISALLOW },
      ...ROBOTS_AGENTS.map((userAgent) => ({ userAgent, disallow: ROBOTS_DISALLOW })),
    ],
    sitemap: absUrl("/sitemap.xml", siteUrl),
  };
}

// ─── llms.txt(llmstxt.org) ───────────────────────────────────────────────────────────────────

export interface LlmsInput {
  links: SeoLinks;
  /** BREW.install */
  brewInstall: string;
  /** 설치 카드와 같은 값 */
  choice: SeoChoice;
  /** release.source === "github" — false(폴백 상수)면 버전·크기·릴리스 날을 싣지 않는다(homeJsonLd 와 같다). */
  live: boolean;
  /** 최신 릴리스 published_at(없으면 날짜를 쓰지 않는다) */
  publishedAt: string | null;
  /** data/site-links FOOTER_LINKS(이름 정본) */
  footerLinks: readonly SeoFooterLink[];
  /** data/site-links NAV_LINKS(절 이름 '기능' · '설치' · '자주 묻는 질문' 정본) */
  navLinks: readonly SeoNavLink[];
  siteUrl?: string;
}

/** 내비 링크 경로(data/site-links NAV_LINKS) — llms.txt 본문 묶음의 이름표가 이 내비 이름이다. */
const NAV_HREF = { features: "/#f-timer", install: "/#install", faq: "/#faq" } as const;

/**
 * llms.txt 본문(llmstxt.org): '# 이름' · '> 요약' · 제목 없는 본문(설치 · 기능 · 자주 묻는 질문 — 굵은 이름표는 화면 내비 이름) ·
 * '## 링크'(파일 목록 '- [이름](절대 주소)'). 글은 모두 화면과 같은 상수에서 — 새 문장을 짓지 않는다.
 */
export function llmsTxt({ links, brewInstall, choice, live, publishedAt, footerLinks, navLinks, siteUrl = SITE_URL }: LlmsInput): string {
  const abs = (p: string) => absUrl(p, siteUrl);
  const footer = (id: string) => footerLinks.find((l) => l.id === id);
  const nav = (href: string) => navLinks.find((l) => l.href === href)?.label;
  const link = (label: string, href: string) => `- [${label}](${abs(href)})`;
  const downloadUrl = choice.file === "dmg" ? links.dmgLatest : links.zipLatest;
  // 설치 카드 메타 줄 그대로('v0.3.67 · 39.0MB · macOS 14 이상 · …'). 폴백이면 버전·크기를 뺀 뒤 항목만.
  const dmgMeta = (live ? metaParts(choice) : [...INSTALL_COPY.metaTail]).join(" · ");
  const date = live ? kstDate(publishedAt) : null;
  const releaseNote = live ? `: v${choice.version}${date ? ` (${date})` : ""}` : "";

  const block = (label: string | undefined, items: string[]): string[] => (label ? [`**${label}**`, "", ...items, ""] : [...items, ""]);
  const lines: string[] = [
    `# ${SITE_NAME} (${ALT_NAME})`,
    "",
    `> ${LLMS_SUMMARY}`,
    "",
    HERO_COPY.metaPhone, // '무료 · iOS 18 이상 · macOS 14 이상'(폰 히어로 메타)
    "",
    ...block(nav(NAV_HREF.install), [
      `- Homebrew: \`${brewInstall}\` — ${INSTALL_COPY.sub}`,
      `- DMG: [${choice.label}](${downloadUrl}) — ${dmgMeta}. ${INSTALL_COPY.dmgLine}`,
      `- iPhone: [App Store](${links.appStore}) — ${INSTALL_COPY.iphoneMeta}`,
      `- [GitHub 릴리스](${links.releases})${releaseNote}`,
    ]),
    ...block(nav(NAV_HREF.features), FEATURE_COPY.map((c) => `- ${c.title.join(" ")}: ${c.body}`)),
    ...block(nav(NAV_HREF.faq), FAQ_ITEMS.map((it) => `- **${it.q}**\n  ${it.a}`)),
    "## 링크",
    "",
    link(SITE_NAME, "/"),
  ];
  const installNav = navLinks.find((l) => l.href === links.install);
  if (installNav) lines.push(link(installNav.label, installNav.href));
  for (const id of ["privacy", "terms", "support", "github"]) {
    const l = footer(id);
    if (l) lines.push(link(l.label, l.href));
  }
  lines.push(link("계정 삭제", DELETE_ACCOUNT_PATH)); // /delete-account 제목 '아잉체크: 계정 삭제'
  const lic = footer("licenses");
  if (lic) lines.push(link(lic.label, lic.href));
  lines.push("");
  return lines.join("\n");
}

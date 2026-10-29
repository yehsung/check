# 랜딩 SEO 운영 메모 (2026-10-30)

목표: 웹 검색에서 **'아잉체크'**(그리고 'aing-check')를 치면 https://aing-check.vercel.app 이 나오게 한다.
결정 요약은 `docs/v3/brief.md §10`, 정본 상수·생성 함수는 `lib/seo.ts`, 계약 시험은 `lib/seo.test.ts`(npm run test:unit).

## 1. 지금 설정된 것

| 무엇 | 어디서 | 내용 |
|---|---|---|
| title · description | `app/layout.tsx` ← `lib/seo.ts` TITLE · DESCRIPTION | og·twitter 도 같은 글자. `applicationName` = 아잉체크 |
| robots 메타 | `lib/seo.ts` ROBOTS_META | googlebot `max-image-preview:large, max-snippet:-1, max-video-preview:-1` 만. index·follow 는 기본값이라 안 적는다(루트 메타가 404 에도 붙어 `noindex` 와 겹치지 않게) |
| canonical | 각 페이지 `alternates.canonical` | `/` · `/licenses` · `/delete-account` |
| 소유 확인 메타 | `lib/seo.ts` verificationFromEnv | 환경 변수가 있을 때만(아래 2절) |
| JSON-LD | `app/page.tsx` ← `homeJsonLd` | WebSite · Organization · SoftwareApplication(Mac) · MobileApplication(iPhone) 한 @graph. Mac 버전·크기는 `/api/release` 가 GitHub 출처일 때만(폴백 상수면 뺀다). screenshot = 첫 화면 팝오버 그림. FAQPage 는 `components/faq/Faq.tsx` 가 따로 |
| robots.txt | `app/robots.ts` ← `robotsConfig` | 그룹마다 `Disallow: /api/` 한 줄(`Allow` 줄 없음 — 막지 않은 곳은 기본 허용이라 파서의 규칙 순서 해석에 기대지 않는다) · `*` + 검색·AI 크롤러 13개를 이름으로 같은 규칙 · Sitemap 줄 |
| sitemap.xml | `app/sitemap.ts` ← `sitemapEntries` | 페이지 셋, lastmod = CONTENT_UPDATED(첫 페이지는 최신 릴리스 날과 비교해 늦은 날), 1시간 ISR |
| llms.txt | `app/llms.txt/route.ts` ← `llmsTxt` | llmstxt.org 꼴: `# 이름` · `> 요약` · 제목 없는 본문(설치 · 기능 · 자주 묻는 질문) · `## 링크` 목록 하나. 화면과 같은 데이터, 버전은 GitHub 출처일 때만, 1시간 ISR, `text/plain; charset=utf-8` |
| IndexNow 키 | `public/<INDEXNOW_KEY>.txt` | 내용 = 키 하나. 키는 `lib/seo.ts` INDEXNOW_KEY |

원칙: 구조화 데이터와 llms.txt 는 화면에 보이는 사실(또는 화면의 링크·버전)만. 별점·리뷰·지어낸 숫자·숨긴 글·클로킹 없음.
화면 문구(FEATURE_COPY · FAQ_ITEMS · INSTALL_COPY · HERO_COPY)를 고치면 LD·llms.txt 가 저절로 따라간다.

## 2. 검색 콘솔 소유 확인 코드 넣기

1. 각 콘솔에서 'HTML 태그(메타 태그)' 방식을 고르고 `content="…"` 값을 복사한다.
   - Google Search Console(URL 접두어 속성 `https://aing-check.vercel.app/`) → `GOOGLE_SITE_VERIFICATION`
   - 네이버 서치어드바이저(사이트 등록) → `NAVER_SITE_VERIFICATION`
   - Bing Webmaster Tools → `BING_SITE_VERIFICATION`(메타 이름 `msvalidate.01`)
2. Vercel 프로젝트 → Settings → Environment Variables 에 위 이름으로 추가, 환경은 **Production**.
   값은 content 값만 넣는다(메타 태그를 통째로 붙여 넣어도 content 만 꺼내 쓰고, 값을 감싼 따옴표·앞뒤 공백은 지운다).
   **DNS TXT 레코드 값(`google-site-verification=…`)은 넣지 않는다** — 메타 태그 값과 다른 값이라 넣으면 확인만 조용히 실패한다.
3. **다시 배포**한다(첫 페이지는 빌드 때 메타를 굽는다 — 변수만 바꾸면 반영되지 않는다).
4. `curl -s https://aing-check.vercel.app/ | grep -o '<meta name="\(google-site-verification\|naver-site-verification\|msvalidate.01\)"[^>]*>'` 로 메타가 나오는지 보고 콘솔에서 [확인].
5. 확인 뒤 각 콘솔에 sitemap `https://aing-check.vercel.app/sitemap.xml` 을 제출한다(네이버는 '요청 → 사이트맵 제출', 구글은 'Sitemaps', Bing 은 'Sitemaps').
   첫 페이지 URL 검사 → 색인 생성 요청도 한 번 한다.

비어 있는 변수는 메타를 내지 않는다(키도 없음) — 셋 중 하나만 넣어도 된다.

**현재 상태(2026-10-30):** 구글은 HTML 태그로 확인됨(`GOOGLE_SITE_VERIFICATION`) · 빙은 'Google Search Console 에서 가져오기'로 추가(메타 불필요) ·
네이버는 `NAVER_SITE_VERIFICATION` 메타에 더해 HTML 파일 `public/navered243ff5c6d2f989a048e172c7489e63.html` 도 둔다 —
서치어드바이저 소유확인 화면의 기본 선택이 'HTML 파일 업로드'라, 태그만 있으면 404 로 실패한다. 이 파일과 env 값은 지우지 않는다(지우면 확인이 풀린다).

## 3. IndexNow 보내기(배포 뒤)

```sh
cd landing
npm run indexnow -- --dry-run   # 보낼 JSON 확인(엔드포인트 안 부름)
npm run indexnow                # api.indexnow.org(Bing 등) · searchadvisor.naver.com 에 제출, 엔드포인트마다 HTTP 상태 출력
```

- 라이브 `https://aing-check.vercel.app/sitemap.xml` 의 URL 을 읽어 `{host, key, keyLocation, urlList}` 를 보낸다. `SITE_URL=…` 로 주소를 바꿀 수 있다.
- 실제 제출 전 `keyLocation`(`/<키>.txt`)이 라이브에서 키를 돌려주는지 먼저 본다 — 키 파일이 배포되기 전이면 멈춘다.
- 200·202 = 받음. 403 = 키 불일치, 422 = URL 이 host 와 다름, 429 = 너무 잦음.
- 빌드에는 걸지 않았다. 내용이 바뀐 배포 뒤에만 돌린다(같은 URL 을 자주 보내지 않는다).
- 구글은 IndexNow 를 쓰지 않는다 — Search Console 의 sitemap·URL 검사로 대신한다.

## 4. 측정 계획

기준선(2026-10-30): 웹 검색 '아잉체크' 결과 0건(사이트가 나오지 않음).

다시 재기 **2026-11-13**(2주 뒤):
1. 색인: `site:aing-check.vercel.app` 을 Google · 네이버 · Bing 에서 — 나온 페이지 수와 제목·설명이 위 글자 그대로인지.
2. 순위: '아잉체크' · 'aing-check' 를 각 검색엔진에서 — 첫 페이지 안 순위(시크릿 창, 로그아웃).
3. 콘솔: Google Search Console 실적(노출·클릭·평균 순위, 검색어 '아잉체크'·'aing-check') · 네이버 서치어드바이저(노출·클릭·수집 현황) · Bing Webmaster(노출·클릭).
4. 구조화 데이터: Google 리치 결과 테스트 · Schema Markup Validator 로 첫 페이지 오류 0 확인(별점이 없어 소프트웨어 리치 결과는 안 뜰 수 있다 — 정상).
5. AI 답변 인용: ChatGPT 검색 · Perplexity · Claude · Google AI 개요에 "아잉체크가 뭐야?" — 사이트나 llms.txt 가 출처로 나오는지, 설명이 사실과 맞는지.

결과는 이 파일 아래에 날짜와 함께 덧붙인다.

## 5. 실서버 스모크(배포 뒤 · 빌드 뒤)

```sh
cd landing
npm run seo:smoke -- --base https://aing-check.vercel.app   # 운영
npx next start -p <포트> & npm run seo:smoke -- --base http://localhost:<포트>   # 로컬 빌드(끝나면 서버를 끈다)
```

- `<title>` 하나·description·og:title · JSON-LD 둘이 JSON 으로 읽히는지 · 별점 0 · screenshot 이 화면의 `<img src>` 인지 ·
  LD·llms.txt 버전이 `/api/release` 출처(github 이면 있음, fallback 이면 없음)와 맞는지 · 소유 확인 메타 · 404 의 robots 메타에 `index` 0 ·
  robots.txt(그룹 14 · `Allow` 0 · 그룹마다 `Disallow: /api/` · Sitemap) · sitemap 3 URL 과 각 canonical · llms.txt 머리·머리글자·캐시 머리 · IndexNow 키 파일.
- 소유 확인 메타는 **이 명령의 환경 변수**와 비교한다 — 빌드(배포)한 환경과 같은 값으로 돌린다(운영이면 Vercel 에 넣은 값).
- `/api/release` 와 첫 페이지는 ISR 이 따로 돌아 드물게 출처가 갈릴 수 있다 — 그 한 줄만 빨강이면 1시간 뒤 다시 잰다.
- `lib/seo.test.ts`(npm run test:unit)는 순수 함수·소스 꼴만 잰다. 실제 응답은 이 스모크로만 보인다.

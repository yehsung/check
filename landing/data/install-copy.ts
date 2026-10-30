// 설치 절 #install 문장(docs/v3/brief.md §8 '설치' 글자 그대로 — v3.1 §9.3: 업데이트 줄 삭제 · 부제 교체) + 릴리스로 버튼·크기를 고르는 순수 함수 + brew 터미널 출력.
// import 는 타입뿐이라 node --experimental-strip-types 로 바로 실행해 볼 수 있다(components/install/install-copy.test.ts).
import type { ReleaseInfo } from "@/data/fixtures";
import type { FigureString } from "@/data/figures";

export const INSTALL_COPY = {
  /** H2 두 줄(줄마다 <br>) */
  h2: ["복잡한 과정 없이", "명령어 한 줄로 설치해요"],
  sub: "터미널에 복사해 붙여 넣으면 내려받기부터 설치까지 끝나요.",
  /** 터미널 창 제목 */
  terminalTitle: "zsh",
  /** 터미널 첫 줄 [복사] 접근 이름(보이는 '복사' 포함) */
  copyAria: "brew 설치 명령 복사",
  /** DMG 카드 — 버튼 글자는 installChoice().label('aing-check.dmg 다운로드') */
  dmgTitle: "Homebrew를 안 쓴다면",
  /** 메타 줄 'v{ver} · {mb}MB · ' 뒤에 붙는 항목 */
  metaTail: ["macOS 14 이상", "Apple Silicon·Intel", "Apple 공증"],
  dmgLine: "DMG 파일을 내려받아 Applications 폴더로 끌어다 놓으면 경고 없이 열려요.",
  /** iPhone 카드 */
  iphoneTitle: "아이폰에서도",
  iphoneMeta: "iOS 18 이상 · 무료",
  /** 데스크톱 QR 옆 */
  qrCaption: "카메라로 찍으면 App Store가 열려요.",
} as const;

// ─── 안드로이드 베타(docs/v3/brief.md §12 — Play 비공개 테스트, 구글 그룹으로 테스터를 받는다) ───────────────────────
// 사용자(2026-10-30): "저거 베타로 사용할 수 있는 경로를 랜딩페이지에 추가하자. 간편하게 접근할 수 있게끔."
// 글자는 §12 그대로(Gemini 로 다듬은 정본 — 화면·llms.txt·시험이 이 상수 하나만 읽는다). 주소는 LINKS(data/fixtures.ts)의 link 키 —
// 이 파일은 node --test 가 바로 읽어야 해서(JSON import 0) 주소를 가져오지 않고 키로 가리킨다. 단계 순서가 곧 실제 순서다(바꾸지 마라).

/** LINKS 의 안드로이드 단계 주소 키 */
export type AndroidLinkKey = "androidGroup" | "androidTesting" | "androidStore";

export type AndroidStep = {
  /** 단계 이름(h4) */
  readonly name: string;
  /** 버튼 글자(새 탭) */
  readonly cta: string;
  /** 보조 한 줄 */
  readonly note: string;
  /** LINKS[link] = 버튼 주소 */
  readonly link: AndroidLinkKey;
  /** 측정 표식 data-cta */
  readonly dataCta: "android-group" | "android-testing" | "android-store";
};

export const ANDROID_COPY = {
  /** 설치 절 카드 제목(h3) */
  title: "안드로이드는 베타로",
  /** 카드 한 줄 */
  line: "구글 계정만 있으면 세 단계로 설치까지 끝나요.",
  /** 같은 계정 경고(가장 중요 — ink-1, 정보 아이콘) */
  warn: "폰의 Play 스토어와 같은 구글 계정으로 가입해요. 다르면 3단계에서 '찾을 수 없음'이 떠요.",
  /** 세 단계(이 순서 그대로 1·2·3) */
  steps: [
    { name: "구글 그룹 가입", cta: "가입하기", note: "누구나 가입할 수 있고 목록·이메일은 관리자만 봐요.", link: "androidGroup", dataCta: "android-group" },
    { name: "웹에서 테스터 되기", cta: "등록하기", note: "열린 페이지에서 '테스터 되기'를 클릭해요.", link: "androidTesting", dataCta: "android-testing" },
    { name: "Play 스토어에서 설치", cta: "설치하기", note: "설치 뒤 업데이트는 Play 스토어가 자동으로 해요.", link: "androidStore", dataCta: "android-store" },
  ] as const satisfies readonly AndroidStep[],
  /** 단계 목록 아래 접는 문제 해결(<details> 기본 닫힘 · §12.6) — 요약 줄 */
  helpTitle: "3단계에서 앱이 안 보이나요?",
  /** 문제 해결 항목(<ul>, 이 순서 그대로) — llms.txt 안드로이드 줄 아래에도 같은 글자 */
  helpItems: [
    "Play 스토어 앱 오른쪽 위 프로필 사진에서 그룹에 가입한 계정으로 바꿔요.",
    "2단계에서 '테스터 되기'까지 클릭했는지 확인해요.",
    "등록 반영까지 몇 분 걸릴 수 있어요. 잠시 뒤 다시 열어요.",
  ],
  /** 베타 안내(작게) */
  betaNote: "베타라 길건너 아잉이·아잉 큐브 게임은 아직 없어요.",
  /** 데스크톱 QR 옆 */
  qrCaption: "카메라로 찍으면 이 안내가 폰에서 열려요.",
  /** QR 그림 alt(링크 이름) */
  qrAlt: "이 안내를 폰에서 여는 QR 코드",
  /** 설치 선택 창 휴대폰 줄 — 이름 · 칩 둘(CHOOSER_COPY 가 가리킨다) */
  chooserRow: "휴대폰 앱",
  chooserIphone: "아이폰",
  chooserAndroid: "안드로이드 베타",
  /** 폰 첫 화면(안드로이드 기기) 주 버튼 — 히어로·아웃트로 */
  phoneCta: "안드로이드 베타 받기",
  /** 폰 첫 화면(안드로이드 기기) 버튼 줄 아래 메타 */
  phoneMeta: "무료 · 안드로이드 베타 · macOS 14 이상",
  /** FAQ 2번 답 맨 끝 문장(data/faq-items.ts · brief §8 에 글자 그대로) */
  faqTail: "안드로이드에서도 베타로 쓸 수 있어요.",
} as const;

/** 릴리스 MB('30.1' 꼴 — 숫자와 점뿐). FigureString 의 한 갈래라 .t-facts 에 그대로 넣을 수 있다. */
export type MbFigure = Extract<FigureString, `${number}.${number}`>;

export type InstallChoice = {
  /** DMG 가 있으면 dmg, 없을 때만 zip */
  file: "dmg" | "zip";
  /** "aing-check.dmg 다운로드" */
  label: string;
  /** 접근 이름에 형식·크기 — "aing-check.dmg 다운로드, 30.1MB" */
  ariaLabel: string;
  /** 10진 MB 한 자리(lib/release formatMB 와 같은 값 — 하드코딩 금지) */
  mb: MbFigure;
  /** "0.3.49"(앞의 v 없음) */
  version: string;
};

const MB_RE = /^\d+\.\d+$/;

/** 문자열이 '30.1' 꼴이면 MbFigure 로 좁힌다. 아니면 null. */
export function asMbFigure(s: string | null | undefined): MbFigure | null {
  return typeof s === "string" && MB_RE.test(s) ? (s as MbFigure) : null;
}

/** 바이트 → '30.1'(formatMB 와 같은 식 — 반올림 한 자리). mb 문자열이 이상할 때만 쓴다. */
function mbFromBytes(bytes: number): MbFigure {
  const [whole, tenth] = (Math.max(0, bytes) / 1e6).toFixed(1).split(".");
  return `${Number(whole)}.${Number(tenth)}`;
}

function pick(r: ReleaseInfo): InstallChoice | null {
  const asset = r.dmg ?? r.zip;
  if (!asset) return null;
  const file: InstallChoice["file"] = r.dmg ? "dmg" : "zip";
  const name = asset.name || (file === "dmg" ? "aing-check.dmg" : "aing-check.zip");
  const mb = asMbFigure(asset.mb) ?? mbFromBytes(asset.bytes);
  return { file, label: `${name} 다운로드`, ariaLabel: `${name} 다운로드, ${mb}MB`, mb, version: r.version };
}

/**
 * 릴리스 → 버튼·크기·버전. release 에 DMG·zip 이 둘 다 없으면(getRelease 가 이미 폴백을 주지만 타입상 가능) fallback 으로.
 * fallback(RELEASE_FALLBACK)에도 없으면 dmg 이름에 크기 0.0 — RELEASE_FALLBACK 은 상수라 닿지 않는 길(테스트가 지킨다).
 */
export function installChoice(release: ReleaseInfo, fallback: ReleaseInfo): InstallChoice {
  return (
    pick(release) ??
    pick(fallback) ?? {
      file: "dmg",
      label: "aing-check.dmg 다운로드",
      ariaLabel: "aing-check.dmg 다운로드",
      mb: mbFromBytes(0),
      version: fallback.version,
    }
  );
}

/** 메타 줄 항목: ['v0.3.63', '30.1MB', 'macOS 14 이상', 'Apple Silicon·Intel', 'Apple 공증'] — ' · ' 로 잇는다. */
export function metaParts(c: Pick<InstallChoice, "version" | "mb">): string[] {
  return [`v${c.version}`, `${c.mb}MB`, ...INSTALL_COPY.metaTail];
}

// ─── 설치 선택 창(docs/v3/brief.md §11 — 히어로·아웃트로·메뉴바의 다운로드 버튼이 여는 창) ──────────────────────
// 사용자(2026-10-30): "설치하기 눌렀을때 바로 dmg 파일 다운되는게 아니라 브루나 dmg 파일 직접 다운 같은거중 선택할 수 있게끔 하자."
// 글자는 §11 그대로(정본은 이 상수 하나 — components/install/InstallChooser.tsx 가 읽는다).
export const CHOOSER_COPY = {
  /** 대화상자 접근 이름(aria-label — 화면에는 보이지 않는다) */
  ariaLabel: "아잉체크 설치 방법 선택",
  /** 선택 1 제목 */
  brewTitle: "Homebrew로 설치하기",
  /** 선택 1 한 줄 = 설치 절 부제와 같은 문장(따로 적지 않는다) */
  brewLine: INSTALL_COPY.sub,
  /** 선택 2 제목(줄 전체가 /api/download 링크) */
  dmgTitle: "DMG 파일 직접 내려받기",
  /** 휴대폰 줄 이름(DMG 줄 아래 — §12) */
  phoneTitle: ANDROID_COPY.chooserRow,
  /** 휴대폰 줄 칩 1(App Store 새 탭) */
  phoneIphone: ANDROID_COPY.chooserIphone,
  /** 휴대폰 줄 칩 2(/#android — 창을 닫고 설치 절 안드로이드 카드로) */
  phoneAndroid: ANDROID_COPY.chooserAndroid,
  /** 맨 아래 링크(/#install) */
  more: "설치 방법 자세히 보기",
} as const;

/** DMG 카드 메타 줄 끝의 공증 항목('Apple 공증') — 선택 창 메타는 이것만 남긴다. */
const NOTARY = INSTALL_COPY.metaTail[2];

/**
 * 선택 창 DMG 줄 메타: ['v0.3.68', '31.4MB', 'Apple 공증'] — DMG 카드 metaParts 에서 버전·크기·공증만(같은 installChoice 값).
 * 폴백(release.source 'fallback')은 DMG 카드와 똑같이 installChoice 가 고른 RELEASE_FALLBACK 값을 보인다(같은 페이지에서 두 곳이 다르지 않게).
 * 모르는 항목만 뺀다: 버전이 비었거나 크기가 0(자산이 하나도 없을 때의 0.0)이면 그 항목 없이. 순수 함수.
 */
export function chooserMetaParts(c: Pick<InstallChoice, "version" | "mb">): string[] {
  const [version, size] = metaParts(c);
  const out: string[] = [];
  if (c.version.trim()) out.push(version);
  if (Number(c.mb) > 0) out.push(size);
  out.push(NOTARY);
  return out;
}

// ─── brew 터미널 출력(§4.5 · §8) ────────────────────────────────────────────────────────────────
// 형식은 Homebrew 7 소스 그대로(brief §8): tap.rb 의 `ohai "Tapping #{name}"` · cask/download 의 `==> Downloading <url>` ·
// cask/installer.rb 의 `ohai "Installing Cask #{token}"` · cask/artifact/moved.rb 의 `ohai "Moving App '#{basename}' to '#{target}'"` ·
// 마지막 `🍺  #{token} was successfully installed!`(맥주 뒤 공백 둘). 'Tapped 1 cask (…).' 줄은 숫자를 지어내야 해서 뺐다.
// 다운로드 주소는 Cask(packaging/homebrew/aing-check.rb)의 url 과 같은 꼴 — 버전만 릴리스 값으로 바뀐다(하드코딩 금지).

export type TerminalLine = {
  /** ohai = 앞에 '==> ' 화살표(brew 파랑) · done = 🍺 성공 줄(밝게) */
  kind: "ohai" | "done";
  /** 화살표 뒤 글자(ohai) 또는 줄 전체(done) */
  text: string;
};

/** 'brew install yehsung/check/aing-check' → { tap: 'yehsung/check', token: 'aing-check' }. 꼴이 아니면 null. */
export function parseBrewInstall(command: string): { tap: string; token: string } | null {
  const m = /^brew install ([\w.-]+)\/([\w.-]+)\/([\w.@-]+)$/.exec(command.trim());
  return m ? { tap: `${m[1]}/${m[2]}`, token: m[3] } : null;
}

/** Cask 의 url 꼴(GitHub Releases 의 aing-check.zip). owner/repo 는 앱 저장소(yehsung/check). */
export function caskZipUrl(version: string, token = "aing-check"): string {
  return `https://github.com/yehsung/check/releases/download/v${version}/${token}.zip`;
}

/** brew 설치 명령 + 릴리스 버전 → 터미널 출력 다섯 줄. 명령 꼴이 아니면 기본 탭(yehsung/check · aing-check)으로. 순수 함수. */
export function brewTranscript(command: string, version: string): TerminalLine[] {
  const { tap, token } = parseBrewInstall(command) ?? { tap: "yehsung/check", token: "aing-check" };
  const app = `${token}.app`;
  return [
    { kind: "ohai", text: `Tapping ${tap}` },
    { kind: "ohai", text: `Downloading ${caskZipUrl(version, token)}` },
    { kind: "ohai", text: `Installing Cask ${token}` },
    { kind: "ohai", text: `Moving App '${app}' to '/Applications/${app}'` },
    { kind: "done", text: `🍺  ${token} was successfully installed!` },
  ];
}

/**
 * 터미널 글자를 줄바꿈 조각으로: '/' 뒤('//' 사이 제외) · '&& ' 뒤에만 줄바꿈 기회(<wbr>)를 더하고, 하이픈이 든 낱말('aing-check.app')은
 * 통째로 묶어(nowrap) 'aing-' / 'check' 처럼 하이픈에서 끊기지 않게 한다. 공백에서는 평소처럼 바뀐다.
 * 조각을 이으면 원래 글자와 같다(복사·선택 글자 그대로). 순수 함수 — CommandPill 의 commandParts 와 같은 줄바꿈 자리 + 하이픈 묶음.
 */
export function wrapTokens(text: string): { text: string; nowrap: boolean; wbrAfter: boolean }[] {
  // 줄바꿈 기회 자리로 먼저 자른다(뒤돌아보기 정규식 없이 — 옛 사파리에서도 읽힌다)
  const parts: string[] = [];
  let from = 0;
  for (let i = 0; i < text.length; i++) {
    const slash = text[i] === "/" && text[i + 1] !== "/"; // 'https://' 의 두 '/' 사이에서는 끊지 않는다
    const andAnd = text.startsWith("&& ", i - 2) && i >= 2;
    if (slash || andAnd) {
      parts.push(text.slice(from, i + 1));
      from = i + 1;
    }
  }
  if (from < text.length) parts.push(text.slice(from));

  const out: { text: string; nowrap: boolean; wbrAfter: boolean }[] = [];
  parts.forEach((part, pi) => {
    const pieces = part.split(/(\S+-\S+)/).filter((x) => x.length > 0);
    pieces.forEach((piece, i) => {
      const lastOfPart = i === pieces.length - 1;
      out.push({ text: piece, nowrap: /^\S+-\S+$/.test(piece), wbrAfter: lastOfPart && pi < parts.length - 1 });
    });
  });
  return out;
}

/** 화살표 줄의 접두(brew 의 ohai). 화면에서는 파랑, 복사·읽기 글자는 그대로. */
export const OHAI_ARROW = "==>";

// ─── 타이핑 시간표(§4.5 — 명령 약 1.2초 · 출력 줄당 120–250ms) ─────────────────────────────────
export const TYPING = {
  /** 명령 전체를 치는 시간 */
  typeMs: 1200,
  /** 마지막 글자 뒤 Enter 까지 */
  enterMs: 320,
  /** 출력 줄 사이 간격(줄마다 다르게 — 실제 brew 처럼 다운로드 뒤가 조금 길다). 범위 120–250, j 번째 = 줄 j → 줄 j+1 */
  lineGapsMs: [230, 250, 160, 220],
  /** 성공 줄 뒤 새 프롬프트까지 */
  promptMs: 260,
} as const;

/**
 * 시간표: 글자 i(1..n)가 보이는 시각 · 출력 줄 j 가 보이는 시각 · 새 프롬프트 시각(ms, 재생 시작 기준). 순수 함수.
 * 출력 줄 수가 lineGapsMs 보다 많으면 마지막 간격을 되풀이한다.
 */
export function typingSchedule(commandLength: number, lineCount: number): { chars: number[]; lines: number[]; prompt: number } {
  const n = Math.max(0, commandLength);
  const step = n > 0 ? TYPING.typeMs / n : 0;
  const chars = Array.from({ length: n }, (_, i) => Math.round(step * (i + 1)));
  const gaps = TYPING.lineGapsMs;
  let t = (chars.at(-1) ?? 0) + TYPING.enterMs;
  const lines: number[] = [];
  for (let j = 0; j < lineCount; j++) {
    if (j > 0) t += gaps[Math.min(j - 1, gaps.length - 1)];
    lines.push(t);
  }
  return { chars, lines, prompt: t + TYPING.promptMs };
}

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

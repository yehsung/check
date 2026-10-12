// 설치 절 문장(SPEC v2 §S6 — CB 문장 글자 그대로) + 릴리스로 주 버튼·크기를 고르는 순수 함수(PLAN v2 §3.7).
// import 는 타입뿐이라 node --experimental-strip-types 로 바로 실행해 볼 수 있다(components/install/install-copy.test.ts).
import type { ReleaseInfo } from "@/data/fixtures";
import type { FigureString } from "@/data/figures";

export const INSTALL_COPY = {
  h2: ["지금, 메뉴바에."], // CB:224
  macTitle: "Mac", // CB §10 플랫폼 표기(SPEC §1.4.3 열 라벨)
  iphoneTitle: "iPhone",
  metaTail: ["macOS 14 Sonoma 이상", "Apple Silicon·Intel", "Apple 공증"], // CB:228
  steps: [
    "받은 파일을 열어요",
    "aing-check 아이콘을 Applications 폴더로 끌어다 놓아요",
    "실행하면 메뉴바 오른쪽 위에 아이콘이 떠요",
  ], // CB:229
  copyAria: "brew 설치 명령 복사", // SPEC §S6 접근성
  // (CB:236 brew 업데이트 문장은 뺐다 — 설치 절의 업데이트 문장은 맨 아래 updateLine 하나, DECISIONS D26-1)
  // (v2.1 brief-v21 §2: "터미널이 편하다면"(CB:234) · zip 링크(CB:238) · iPhone 둘째 줄(CB:243 뒷문장) · 팀 참여 3걸음(CB:246–248)은
  //  설치 절에서 뺐다 — 팀 코드는 FAQ 3번, 근무 시작·종료는 장면 6 이 말한다. /api/download?file=zip 라우트는 그대로)
  iphoneMeta: "iOS 18 이상 · 무료", // CB:243
  // 설치 경로를 가르지 않는다 — DMG 설치본도 앱 안에서 스스로 바뀐다(DECISIONS D18 · SPEC §1.4.3 승인 문장).
  updateLine: "새 버전이 나오면 메뉴바 아이콘에 작은 점이 떠요. 지금 업데이트 한 번이면 설치하고 다시 켜져요.",
} as const;

/** 릴리스 MB('30.1' 꼴 — 숫자와 점뿐). FigureString 의 한 갈래라 .t-facts 에 그대로 넣을 수 있다. */
export type MbFigure = Extract<FigureString, `${number}.${number}`>;

export type InstallChoice = {
  /** DMG 가 있으면 dmg, 없을 때만 zip(SPEC §S6) */
  file: "dmg" | "zip";
  /** "aing-check.dmg 다운로드" */
  label: string;
  /** 접근 이름에 형식·크기 — "aing-check.dmg 다운로드, 30.1MB" */
  ariaLabel: string;
  /** 10진 MB 한 자리(lib/release formatMB 와 같은 값) — 숫자 격자 4번 칸·메타 줄(DECISIONS D16: 하드코딩 금지) */
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
 * 릴리스 → 주 버튼·크기. release 에 DMG·zip 이 둘 다 없으면(getRelease 가 이미 폴백을 주지만 타입상 가능) fallback 으로.
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

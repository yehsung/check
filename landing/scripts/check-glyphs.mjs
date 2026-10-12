#!/usr/bin/env node
/**
 * 글자 검사(SPEC v2 §9.5) — Node 만 쓴다(파이썬 없음, Vercel 빌드에서도 돈다). `prebuild` 가 부른다.
 *
 *   node scripts/check-glyphs.mjs
 *
 * (a) 랜딩 소스(app/**, components/**, data/** 의 .ts/.tsx, data/generated 제외)의 문자열 리터럴·템플릿·JSX 텍스트에 나온
 *     **한글 음절**이 public/fonts/pretendard-500-sub.txt **그리고** pretendard-600-sub.txt(서브셋에 실제로 든 글자)에
 *     모두 있어야 한다. 한글 밖의 비 ASCII 글자(이모지 제외)가 빠졌으면 경고만 한다.
 * (b) data/figures.ts 의 리터럴 글자(공백 제외 전부 — 숫자·':'·'.'·'콕'·'주' …)가 public/fonts/pretendard-300-num.txt 에
 *     모두 있어야 한다(.t-number·.t-facts 는 이 글꼴 하나로만 그린다).
 * 하나라도 어긋나면 목록을 찍고 exit 1. 검사에 쓸 .txt(또는 data/figures.ts)가 없으면 그 검사만 경고하고 건너뛴다
 * (스캐폴드 전 — exit 0).
 *
 * 주석과 개발용 문구(console.*·devWarn/warnOnce 류 호출·new *Error 의 인자)는 글자로 치지 않는다(TypeScript 파서로
 * 리터럴만 읽는다). typescript 를 못 불러오면 주석을 대충 걷어 낸 전체 글자로 대신한다(더 많이 잡는 쪽이라 안전).
 *
 * 이 파일은 subset-fonts.mjs 가 import 해서 같은 수집기를 쓴다(기본 모드 = 소스 스캔, 300 = data/figures.ts 하나).
 */
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const FONTS_DIR = path.join(ROOT, "public/fonts");
/** 서브셋 글자 목록(subset-fonts.mjs 가 쓰고 여기서 읽는다). */
export const SUB_TXT = {
  500: path.join(FONTS_DIR, "pretendard-500-sub.txt"),
  600: path.join(FONTS_DIR, "pretendard-600-sub.txt"),
  "300n": path.join(FONTS_DIR, "pretendard-300-num.txt"),
};
/** 300 숫자 서브셋의 유일한 글자 출처(SPEC §6.4). */
export const FIGURES_FILE = path.join(ROOT, "data/figures.ts");
/** 300 숫자 서브셋에 늘 더하는 글자(릴리스 MB '30.1' 꼴 · 시각 '00:00' 꼴). */
export const FIGURE_EXTRA = "0123456789:.";
export const SCAN_DIRS = ["app", "components", "data"];
export const SCAN_EXCLUDE = [path.join("data", "generated")];
/** 테스트 파일은 배포되지 않는다(금지어 검사 문자열 등) — 수집에서 뺀다(DECISIONS D21-2). subset-fonts.mjs 도 이 수집기를 쓴다. */
export const TEST_FILE = /\.test\.(ts|tsx|mts|mjs)$/;
export const HANGUL_SYLLABLE = /^[가-힣]$/;

/** 이모지·이모지 조각(변형 선택자·ZWJ·키캡)·제어 문자는 서브셋에 넣지 않는다(☕️ 는 시스템 이모지 글꼴로). */
export function isGlyphCandidate(ch) {
  if (/\p{Cc}|\p{Cs}|\p{Co}/u.test(ch)) return false;
  if (/\p{Extended_Pictographic}/u.test(ch)) return false;
  if (/[​-‏⁠︀-️⃣]/u.test(ch)) return false;
  const cp = ch.codePointAt(0);
  if (cp >= 0x1f000) return false; // 보조 평면의 기호·이모지
  return true;
}

const NAMED_ENTITIES = { nbsp: " ", middot: "·", hellip: "…", lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”", amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", mdash: "—", ndash: "–", times: "×", rarr: "→", larr: "←" };
function decodeEntities(s) {
  return s
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&([a-z]+);/gi, (m, n) => NAMED_ENTITIES[n.toLowerCase()] ?? m);
}

function listSourceFiles(root) {
  const out = [];
  const walk = (dir) => {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const p = path.join(dir, e.name);
      const rel = path.relative(root, p);
      if (e.isDirectory()) {
        if (e.name === "node_modules" || e.name.startsWith(".")) continue;
        if (SCAN_EXCLUDE.some((x) => rel === x || rel.startsWith(x + path.sep))) continue;
        walk(p);
      } else if (/\.(ts|tsx|mts)$/.test(e.name) && !e.name.endsWith(".d.ts") && !TEST_FILE.test(e.name)) {
        out.push(p);
      }
    }
  };
  for (const d of SCAN_DIRS) walk(path.join(root, d));
  return out.sort();
}

let tsCache;
function loadTypeScript(root) {
  if (tsCache !== undefined) return tsCache;
  try {
    tsCache = createRequire(path.join(root, "package.json"))("typescript");
  } catch {
    tsCache = null;
  }
  return tsCache;
}

/**
 * 소스 문자열 하나에서 글자를 뽑아 add(text) 로 넘긴다. fileName 의 확장자로 TSX 여부를 정한다.
 * 반환: 쓴 방법('typescript x.y' | 'fallback(regex)').
 */
export function visitSourceText(src, fileName, add, root = ROOT) {
  const ts = loadTypeScript(root);
  if (!ts) {
    // 대체 경로: 블록·줄 주석을 대충 걷어 내고 남은 글자 전부(문자열 안의 // 도 지울 수 있어 덜 잡을 수 있다 — 경고로 알린다).
    add(src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'`])\/\/.*$/gm, "$1"));
    return "fallback(regex)";
  }
  const SK = ts.SyntaxKind;
  const sf = ts.createSourceFile(fileName, src, ts.ScriptTarget.Latest, true, fileName.endsWith(".tsx") ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
  // 개발용 문구(화면에 그려지지 않는다): console.*(…) · devWarn/warnOnce/log/debug/assert/invariant 류 호출 · new *Error(…)
  const DEV_FN = /^(dev)?(warn|log|debug|trace|assert|invariant|error)(once|dev)?$/i;
  const calleeName = (e) => (e.kind === SK.Identifier ? e.text : e.kind === SK.PropertyAccessExpression ? e.name.text : "");
  const isDevOnly = (node) => {
    if (node.kind === SK.CallExpression) {
      const e = node.expression;
      if (e.kind === SK.PropertyAccessExpression && e.expression.kind === SK.Identifier && e.expression.text === "console") return true;
      return DEV_FN.test(calleeName(e));
    }
    if (node.kind === SK.NewExpression) return /Error$/.test(calleeName(node.expression));
    return false;
  };
  const visit = (node) => {
    if (isDevOnly(node)) return;
    switch (node.kind) {
      case SK.StringLiteral:
      case SK.NoSubstitutionTemplateLiteral:
      case SK.TemplateHead:
      case SK.TemplateMiddle:
      case SK.TemplateTail:
        add(node.text);
        break;
      case SK.JsxText:
        add(decodeEntities(node.text));
        break;
      default:
        break;
    }
    ts.forEachChild(node, visit);
  };
  visit(sf);
  return `typescript ${ts.version}`;
}

/**
 * 소스 글자 수집. 반환: { chars: Set<string>, where: Map<string, Set<string>>, files: string[], method }
 * where = 글자 → 그 글자가 나온 파일(상대 경로) 집합.
 * opts.files 를 주면(절대 경로 또는 root 기준 상대 경로) 그 파일들만 읽는다 — 300 숫자 서브셋은 data/figures.ts 하나.
 */
export function collectSourceGlyphs(root = ROOT, opts = {}) {
  const files = opts.files ? opts.files.map((f) => path.resolve(root, f)).filter((f) => fs.existsSync(f)) : listSourceFiles(root);
  const chars = new Set();
  const where = new Map();
  let method = loadTypeScript(root) ? `typescript ${loadTypeScript(root).version}` : "fallback(regex)";
  for (const file of files) {
    const rel = path.relative(root, file);
    const add = (text) => {
      for (const ch of text) {
        if (!isGlyphCandidate(ch)) continue;
        chars.add(ch);
        if (!where.has(ch)) where.set(ch, new Set());
        where.get(ch).add(rel);
      }
    };
    method = visitSourceText(fs.readFileSync(file, "utf8"), file, add, root);
  }
  return { chars, where, files: files.map((f) => path.relative(root, f)), method };
}

const hex = (c) => `U+${c.codePointAt(0).toString(16).toUpperCase().padStart(4, "0")}`;
const readTxt = (file) => new Set(fs.readFileSync(file, "utf8").replace(/[\r\n]/g, ""));

/** (a) 소스 한글 ⊂ 500·600 서브셋. 반환 exit 기여(0|1). */
function checkTextFonts() {
  const { chars, where, files, method } = collectSourceGlyphs(ROOT);
  if (method.startsWith("fallback")) console.warn("check-glyphs: typescript 를 못 불러와 정규식 대체 경로로 셌다.");
  const hangul = [...chars].filter((c) => HANGUL_SYLLABLE.test(c));
  let code = 0;
  for (const w of ["500", "600"]) {
    const txt = SUB_TXT[w];
    const name = path.relative(ROOT, txt);
    if (!fs.existsSync(txt)) {
      console.warn(`check-glyphs: ${name} 없음 — 서브셋 전이라 이 검사를 건너뛴다(npm run subset 뒤에 다시 돈다).`);
      continue;
    }
    const have = readTxt(txt);
    const missing = hangul.filter((c) => !have.has(c)).sort();
    const otherMissing = [...chars].filter((c) => c.codePointAt(0) > 0x7e && !HANGUL_SYLLABLE.test(c) && !have.has(c) && !/\s/u.test(c)).sort();
    if (otherMissing.length) {
      console.warn(`check-glyphs: 경고 — ${path.basename(txt)} 에 없는 비한글 글자 ${otherMissing.length}개(시스템 글꼴로 섞인다): ${otherMissing.map((c) => `${c}(${hex(c)})`).join(" ")}`);
    }
    if (missing.length) {
      console.error(`check-glyphs: 서브셋(${path.basename(txt)})에 없는 한글 음절 ${missing.length}개 — npm run subset 으로 서브셋을 다시 만드세요.`);
      for (const c of missing) console.error(`  ${c}  ${hex(c)}  ${[...where.get(c)].join(", ")}`);
      code = 1;
      continue;
    }
    console.log(`check-glyphs: OK — 소스 ${files.length}개 파일, 한글 음절 ${hangul.length}자 모두 ${path.basename(txt)}(${have.size}자)에 있음 [${method}]`);
  }
  return code;
}

/** (b) data/figures.ts 글자 ⊂ 300 숫자 서브셋. 반환 exit 기여(0|1). */
function checkFigureFont() {
  const txt = SUB_TXT["300n"];
  if (!fs.existsSync(txt)) {
    console.warn(`check-glyphs: ${path.relative(ROOT, txt)} 없음 — 숫자 서브셋 전이라 이 검사를 건너뛴다(npm run subset 뒤에 다시 돈다).`);
    return 0;
  }
  if (!fs.existsSync(FIGURES_FILE)) {
    console.warn(`check-glyphs: ${path.relative(ROOT, FIGURES_FILE)} 없음 — 숫자 글자 출처가 아직 없어 이 검사를 건너뛴다.`);
    return 0;
  }
  const have = readTxt(txt);
  const { chars } = collectSourceGlyphs(ROOT, { files: [FIGURES_FILE] });
  const need = [...chars].filter((c) => !/\s/u.test(c)).sort((a, b) => a.codePointAt(0) - b.codePointAt(0));
  const missing = need.filter((c) => !have.has(c));
  if (missing.length) {
    console.error(`check-glyphs: data/figures.ts 의 글자 ${missing.length}개가 ${path.basename(txt)} 에 없다 — npm run subset 으로 다시 만드세요: ${missing.map((c) => `${c}(${hex(c)})`).join(" ")}`);
    return 1;
  }
  console.log(`check-glyphs: OK — data/figures.ts 글자 ${need.length}자(${need.join("")}) 모두 ${path.basename(txt)}(${have.size}자)에 있음`);
  return 0;
}

function main() {
  const a = checkTextFonts();
  const b = checkFigureFont();
  return a || b ? 1 : 0;
}

const invokedDirectly = (() => {
  try {
    return !!process.argv[1] && pathToFileURL(fs.realpathSync(path.resolve(process.argv[1]))).href === pathToFileURL(fs.realpathSync(fileURLToPath(import.meta.url))).href;
  } catch {
    return false;
  }
})();
if (invokedDirectly) {
  process.exit(main());
}

#!/usr/bin/env node
/**
 * 글꼴 서브셋(SPEC v2 §2.3 · §9.5, DECISIONS D5) — `npm run subset`
 *
 *   node scripts/subset-fonts.mjs              # 기본: 소스 스캔(app/**, components/**, data/** 의 .ts/.tsx 리터럴·JSX 텍스트)
 *   node scripts/subset-fonts.mjs --from-spec  # 스캐폴드용: docs/v2/SPEC.md §3 본문 글자 ∪ 소스 스캔
 *
 * 500·600 은 같은 글자 집합: 위 글자 + ASCII(U+0020–007E) 전부 + 한글 문장 부호 「」·…‘’“”, 이모지·제어 문자·줄바꿈 제외.
 * 300 숫자 전용은 같은 수집기를 data/figures.ts 하나에만 돌린 글자 + 0–9 : .
 *   (--from-spec 이면 docs/v2/SPEC.md §6.4 코드 블록 = figures.ts 전문도 더한다 — 스캐폴드 때 figures.ts 가 아직 없을 수 있다.)
 *
 * 출력(landing/public/fonts/):
 *   pretendard-500-sub.woff2 · .txt  ← /Users/yesung/aing-check-promo/public/fonts/Pretendard-Medium.woff2
 *   pretendard-600-sub.woff2 · .txt  ← Pretendard-SemiBold.woff2
 *   pretendard-300-num.woff2 · .txt  ← PretendardVariable.woff2 → fonttools varLib.instancer wght=300(임시 폴더) → 서브셋
 *   jbm-400-ascii.woff2              ← JetBrainsMono-Regular.woff2, U+0020-007E
 *   LICENSE-Pretendard.txt · LICENSE-JetBrainsMono.txt (원본 복사)
 *   .txt = 서브셋에 실제로 든 글자(출력 글꼴 cmap 기준, 코드포인트 순). check-glyphs.mjs 가 읽는다.
 * v1 pretendard-800-sub.* 는 통합(⑤)이 지웠다(2026-10-12 — app/layout.tsx 는 500·600·300 만 가리킨다).
 *
 * 도구: pyftsubset(env PYFTSUBSET, 기본 /opt/anaconda3/bin/pyftsubset — fontTools + brotli),
 *       fonttools(env FONTTOOLS, 기본 pyftsubset 과 같은 폴더), cmap 읽기는 같은 폴더의 python3(env PYTHON 으로 덮어쓰기).
 *       500·600: pyftsubset <src> --text-file=<글자> --flavor=woff2 --layout-features=kern,liga --no-hinting
 *       300:     fonttools varLib.instancer PretendardVariable.woff2 wght=300 -o <임시>
 *                pyftsubset <임시> --text-file=<글자> --flavor=woff2 --layout-features=kern,tnum --no-hinting
 * 임시 파일은 OS 임시 폴더에 만들고 끝나면(실패해도) 지운다. 출력은 같은 폴더의 임시 이름에 쓴 뒤 rename 한다.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { ROOT, FIGURES_FILE, FIGURE_EXTRA, collectSourceGlyphs, visitSourceText, isGlyphCandidate, HANGUL_SYLLABLE } from "./check-glyphs.mjs";

const FONT_SRC = "/Users/yesung/aing-check-promo/public/fonts/";
const OUT = path.join(ROOT, "public/fonts");
const SPEC = path.join(ROOT, "docs/v2/SPEC.md");
const PYFTSUBSET = process.env.PYFTSUBSET ?? "/opt/anaconda3/bin/pyftsubset";
const FONTTOOLS = process.env.FONTTOOLS ?? path.join(path.dirname(PYFTSUBSET), "fonttools");
const PYTHON = process.env.PYTHON ?? (fs.existsSync(path.join(path.dirname(PYFTSUBSET), "python3")) ? path.join(path.dirname(PYFTSUBSET), "python3") : "python3");
const EXTRA_PUNCT = "「」·…‘’“”";
const FROM_SPEC = process.argv.includes("--from-spec");

/** 본문 글꼴 두 벌(같은 글자 집합). */
const TEXT_FONTS = [
  { out: "pretendard-500-sub", src: "Pretendard-Medium.woff2" },
  { out: "pretendard-600-sub", src: "Pretendard-SemiBold.woff2" },
];
const FIGURE_FONT = { out: "pretendard-300-num", src: "PretendardVariable.woff2", wght: 300 };

function die(msg) {
  console.error(`subset-fonts: ${msg}`);
  process.exit(1);
}

function run(cmd, args) {
  const r = spawnSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  if (r.error) throw new Error(`${cmd} 실행 실패: ${r.error.message}`);
  if (r.status !== 0) throw new Error(`${path.basename(cmd)} exit ${r.status}\n${r.stdout}\n${r.stderr}`);
  if (r.stderr.trim()) console.warn(r.stderr.trim());
  return r.stdout;
}

/** SPEC.md 에서 `## <n>.` 절 본문(다음 `## ` 머리 전까지)을 꺼낸다. */
function specSection(md, n) {
  const lines = md.split("\n");
  const start = lines.findIndex((l) => new RegExp(`^## ${n}\\.`).test(l));
  if (start < 0) throw new Error(`docs/v2/SPEC.md 에서 '## ${n}.' 절을 못 찾았다`);
  let end = lines.findIndex((l, i) => i > start && /^## /.test(l));
  if (end < 0) end = lines.length;
  return lines.slice(start, end).join("\n");
}

/** SPEC.md §6.4(`data/figures.ts` 전문) 의 ```ts 코드 블록. */
function specFiguresBlock(md) {
  const lines = md.split("\n");
  const start = lines.findIndex((l) => /^### 6\.4 /.test(l));
  if (start < 0) throw new Error("docs/v2/SPEC.md 에서 '### 6.4' 절을 못 찾았다");
  const open = lines.findIndex((l, i) => i > start && /^```ts\s*$/.test(l));
  const close = lines.findIndex((l, i) => i > open && /^```\s*$/.test(l));
  if (open < 0 || close < 0) throw new Error("docs/v2/SPEC.md §6.4 에 ```ts 코드 블록이 없다");
  return lines.slice(open + 1, close).join("\n");
}

const dropWhitespace = (set) => {
  for (const ch of [...set]) if (/\s/u.test(ch) && ch !== " ") set.delete(ch); // 줄바꿈·탭 등
  return set;
};

/** 500·600 글자 집합. */
function gatherTextGlyphs() {
  const src = collectSourceGlyphs(ROOT);
  const chars = new Set(src.chars);
  let label = `소스 ${src.files.length}개 파일 [${src.method}]`;
  if (FROM_SPEC) {
    const text = specSection(fs.readFileSync(SPEC, "utf8"), 3);
    for (const ch of text) if (isGlyphCandidate(ch)) chars.add(ch);
    label = `docs/v2/SPEC.md §3 ∪ ${label}`;
  }
  for (let cp = 0x20; cp <= 0x7e; cp++) chars.add(String.fromCodePoint(cp));
  for (const ch of EXTRA_PUNCT) chars.add(ch);
  return { chars: dropWhitespace(chars), label };
}

/** 300 숫자 글자 집합. */
function gatherFigureGlyphs() {
  const chars = new Set();
  const labels = [];
  if (fs.existsSync(FIGURES_FILE)) {
    const r = collectSourceGlyphs(ROOT, { files: [FIGURES_FILE] });
    for (const ch of r.chars) chars.add(ch);
    labels.push("data/figures.ts");
  } else if (!FROM_SPEC) {
    throw new Error("data/figures.ts 가 없다 — 300 숫자 서브셋의 글자 출처(SPEC §6.4). 스캐폴드 때는 --from-spec 으로.");
  }
  if (FROM_SPEC) {
    visitSourceText(specFiguresBlock(fs.readFileSync(SPEC, "utf8")), "figures-spec.ts", (text) => {
      for (const ch of text) if (isGlyphCandidate(ch)) chars.add(ch);
    });
    labels.push("docs/v2/SPEC.md §6.4");
  }
  for (const ch of FIGURE_EXTRA) chars.add(ch);
  for (const ch of [...chars]) if (/\s/u.test(ch)) chars.delete(ch); // 숫자 글꼴엔 공백도 없다
  return { chars, label: `${labels.join(" ∪ ")} + ${FIGURE_EXTRA}` };
}

function cmapOf(file) {
  const py = "import sys, json\nfrom fontTools.ttLib import TTFont\nprint(json.dumps(sorted(TTFont(sys.argv[1]).getBestCmap().keys())))";
  return JSON.parse(run(PYTHON, ["-c", py, file]));
}

const sortCp = (arr) => [...arr].sort((a, b) => a.codePointAt(0) - b.codePointAt(0));
const hex = (c) => `${c}(U+${c.codePointAt(0).toString(16).toUpperCase().padStart(4, "0")})`;

/** 같은 폴더 임시 이름에 쓴 뒤 rename(반쯤 쓴 파일이 보이는 순간이 없게). */
function publish(fromFile, name) {
  const dest = path.join(OUT, name);
  const tmp = path.join(OUT, `.${name}.tmp-${process.pid}`);
  fs.copyFileSync(fromFile, tmp);
  fs.renameSync(tmp, dest);
}
function publishText(text, name) {
  const dest = path.join(OUT, name);
  const tmp = path.join(OUT, `.${name}.tmp-${process.pid}`);
  fs.writeFileSync(tmp, text, "utf8");
  fs.renameSync(tmp, dest);
}

/** 서브셋 하나 만들고 cmap 글자 목록을 돌려준다(아직 OUT 에 쓰지 않는다). */
function subset(srcFile, textFile, features, outFile) {
  run(PYFTSUBSET, [srcFile, `--text-file=${textFile}`, "--flavor=woff2", `--layout-features=${features}`, "--no-hinting", `--output-file=${outFile}`]);
  return cmapOf(outFile).map((cp) => String.fromCodePoint(cp)).filter((c) => !/\p{Cc}/u.test(c));
}

function main() {
  if (!fs.existsSync(PYFTSUBSET)) die(`pyftsubset 없음: ${PYFTSUBSET}`);
  if (!fs.existsSync(FONTTOOLS)) die(`fonttools 없음: ${FONTTOOLS}`);
  for (const f of [...TEXT_FONTS.map((t) => t.src), FIGURE_FONT.src, "JetBrainsMono-Regular.woff2", "LICENSE-Pretendard.txt", "LICENSE-JetBrainsMono.txt"]) {
    if (!fs.existsSync(FONT_SRC + f)) die(`원본 없음: ${FONT_SRC + f}`);
  }
  if (FROM_SPEC && !fs.existsSync(SPEC)) die(`--from-spec 인데 ${path.relative(ROOT, SPEC)} 가 없다`);
  fs.mkdirSync(OUT, { recursive: true });
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "aing-subset-"));
  const outputs = [];
  let failure = null;
  try {
    // ── 500 · 600(같은 글자 집합) ──
    const { chars, label } = gatherTextGlyphs();
    const sorted = sortCp(chars);
    const textFile = path.join(tmp, "glyphs.txt");
    fs.writeFileSync(textFile, sorted.join(""), "utf8");
    const hangulReq = sorted.filter((c) => HANGUL_SYLLABLE.test(c)).length;
    const built = [];
    for (const t of TEXT_FONTS) {
      const woff = path.join(tmp, `${t.out}.woff2`);
      const included = subset(FONT_SRC + t.src, textFile, "kern,liga", woff);
      const inSet = new Set(included);
      const notInFont = sorted.filter((c) => !inSet.has(c));
      if (notInFont.length) console.warn(`subset-fonts: 경고 — ${t.src} 에 없는 글자 ${notInFont.length}개(시스템 글꼴로 그려진다): ${notInFont.map(hex).join(" ")}`);
      const missingHangul = sorted.filter((c) => HANGUL_SYLLABLE.test(c) && !inSet.has(c));
      if (missingHangul.length) throw new Error(`${t.out}: 한글 음절이 서브셋에 안 들어갔다: ${missingHangul.join("")}`);
      built.push({ ...t, woff, included });
    }
    // 두 벌의 cmap 이 같아야 한다(SPEC §2.3 '같은 글자 집합').
    const [a, b] = built.map((x) => x.included.join(""));
    if (a !== b) {
      const sa = new Set(built[0].included);
      const sb = new Set(built[1].included);
      const onlyA = built[0].included.filter((c) => !sb.has(c));
      const onlyB = built[1].included.filter((c) => !sa.has(c));
      throw new Error(`500·600 서브셋 글자가 다르다 — 500 만: ${onlyA.map(hex).join(" ") || "없음"} / 600 만: ${onlyB.map(hex).join(" ") || "없음"}`);
    }

    // ── 300 숫자 전용(Variable → wght=300 인스턴스 → 서브셋) ──
    const fig = gatherFigureGlyphs();
    const figSorted = sortCp(fig.chars);
    const figText = path.join(tmp, "figures.txt");
    fs.writeFileSync(figText, figSorted.join(""), "utf8");
    const inst = path.join(tmp, "pretendard-300-instance.ttf");
    run(FONTTOOLS, ["varLib.instancer", FONT_SRC + FIGURE_FONT.src, `wght=${FIGURE_FONT.wght}`, "-o", inst]);
    const figWoff = path.join(tmp, `${FIGURE_FONT.out}.woff2`);
    const figIncluded = subset(inst, figText, "kern,tnum", figWoff);
    const figSet = new Set(figIncluded);
    const figMissing = figSorted.filter((c) => !figSet.has(c));
    if (figMissing.length) throw new Error(`${FIGURE_FONT.out}: 숫자 서브셋에 안 들어간 글자: ${figMissing.map(hex).join(" ")}`);
    // 인스턴스가 정말 300 인지(OS/2 usWeightClass · fvar 없음)
    const meta = JSON.parse(run(PYTHON, ["-c", "import sys, json\nfrom fontTools.ttLib import TTFont\nf=TTFont(sys.argv[1])\nprint(json.dumps({'w': f['OS/2'].usWeightClass, 'fvar': 'fvar' in f, 'gvar': 'gvar' in f}))", figWoff]));
    if (meta.w !== FIGURE_FONT.wght || meta.fvar || meta.gvar) throw new Error(`${FIGURE_FONT.out}: 인스턴스가 정적 ${FIGURE_FONT.wght} 이 아니다 ${JSON.stringify(meta)}`);

    // ── JetBrains Mono Regular ASCII ──
    const jbmTmp = path.join(tmp, "jbm-400-ascii.woff2");
    run(PYFTSUBSET, [FONT_SRC + "JetBrainsMono-Regular.woff2", "--unicodes=U+0020-007E", "--flavor=woff2", "--layout-features=kern,liga", "--no-hinting", `--output-file=${jbmTmp}`]);
    const jbmCps = cmapOf(jbmTmp);
    if (jbmCps.length !== 95 || jbmCps[0] !== 0x20 || jbmCps.at(-1) !== 0x7e) throw new Error(`jbm 서브셋 cmap 이 U+0020–007E 95자가 아니다(${jbmCps.length}자)`);

    // ── 전부 만든 뒤에 내보낸다(중간 실패면 public/fonts 는 그대로) ──
    for (const x of built) {
      publish(x.woff, `${x.out}.woff2`);
      publishText(x.included.join("") + "\n", `${x.out}.txt`);
      outputs.push(`${x.out}.woff2`, `${x.out}.txt`);
    }
    publish(figWoff, `${FIGURE_FONT.out}.woff2`);
    publishText(figIncluded.join("") + "\n", `${FIGURE_FONT.out}.txt`);
    outputs.push(`${FIGURE_FONT.out}.woff2`, `${FIGURE_FONT.out}.txt`);
    publish(jbmTmp, "jbm-400-ascii.woff2");
    outputs.push("jbm-400-ascii.woff2");
    for (const f of ["LICENSE-Pretendard.txt", "LICENSE-JetBrainsMono.txt"]) {
      publish(FONT_SRC + f, f);
      outputs.push(f);
    }

    console.log(`subset-fonts: 500·600 글자 출처 = ${label} + ASCII + ${EXTRA_PUNCT}`);
    console.log(`subset-fonts: 500·600 요청 ${sorted.length}자(한글 음절 ${hangulReq}) → 서브셋 cmap ${built[0].included.length}자(두 벌 같음)`);
    console.log(`subset-fonts: 300 글자 출처 = ${fig.label} → ${figIncluded.join("")} (${figIncluded.length}자, usWeightClass ${meta.w})`);
    for (const f of outputs) {
      const n = fs.statSync(path.join(OUT, f)).size;
      if (!(n > 0)) throw new Error(`${f} 가 0 바이트`);
      console.log(`${String(n).padStart(9)} B  public/fonts/${f}`);
    }
  } catch (e) {
    failure = e;
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
    for (const f of fs.readdirSync(OUT)) if (f.startsWith(".") && f.includes(`.tmp-${process.pid}`)) fs.rmSync(path.join(OUT, f), { force: true });
  }
  if (failure) die(failure?.message ?? String(failure));
}

main();

#!/usr/bin/env node
// v1 초안(거부된 v1 설계 단계 — scripts/build-assets.mjs 가 대체했다). 기록으로만 남긴다. v2 정본은 docs/v2/.
/**
 * 아잉체크 랜딩 에셋 내보내기 — 설계 초안(이 파일은 scratchpad 의 레시피. 구현 때 landing/scripts/export-assets.mjs 로 옮긴다).
 *
 * 읽기: /Users/yesung/aing-check-promo/public/assets (+ check/packaging/appicon). 원본은 절대 쓰지 않는다.
 * 쓰기: OUT (기본 ./landing/public/assets). 결과물은 커밋한다 — Vercel 빌드에서 돌리지 않는다(hevc_videotoolbox = macOS 전용).
 *
 * 필요: node 22, sharp 0.34(landing devDependency), ffmpeg(libvpx-vp9 + hevc_videotoolbox).
 *   FFMPEG 환경변수로 경로를 준다. 이 맥에선 /Users/yesung/aing-check-promo/node_modules/@remotion/compositor-darwin-arm64/ffmpeg
 *   (DYLD_LIBRARY_PATH 를 같은 폴더로; pad·select 필터가 없는 축소판이라 짝수 맞춤은 sharp 쪽에서 한다).
 *
 * 실행: OUT=<dir> FFMPEG=<ffmpeg> node export-assets.mjs [--only=char,ui,ios,brand,stills]
 */
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const require = createRequire(import.meta.url);
const sharp = require(process.env.SHARP ?? "sharp");
sharp.concurrency(4);

const SRC = "/Users/yesung/aing-check-promo/public/assets/";
const ICON = "/Users/yesung/check/packaging/appicon/icon-1024.png";
const OUT = path.resolve(process.env.OUT ?? "landing/public/assets");
const FF = process.env.FFMPEG ?? "ffmpeg";
const ffEnv = { ...process.env, DYLD_LIBRARY_PATH: path.dirname(FF) };
const only = (process.argv.find((a) => a.startsWith("--only=")) ?? "--only=char,ui,ios,brand,stills").slice(7).split(",");
const report = [];
const put = (rel, buf) => {
  const p = path.join(OUT, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, buf);
  report.push([rel, buf.length]);
};
const sizeOf = (rel) => fs.statSync(path.join(OUT, rel)).size;

// ─── 1. 캐릭터 알파 시퀀스 → 알파 영상 두 벌 + 포스터 ─────────────────────────────
// 박스(rect)는 2100×2625(main) / 2160×2160(ultra) 캔버스 좌표 [x, y, w, h]. w·h 는 4의 배수 → S=0.5 에서 짝수.
// HERO 박스 = idle_long·hit·poked·commute_start·commute_end·greeting alphaBBoxUnion 의 합집합(430,548)-(1727,2118) + 여백.
// 같은 박스·같은 배율이라 영상끼리 갈아 끼울 때 위치 계산이 없다(겹쳐 두고 보이기만 바꾼다).
const HERO = [424, 544, 1308, 1580];
const SEQ = [
  // name, dir(%04d.png), frames, rect, scale, posterFrame, vp9 crf, hevc q, 언제 받나
  ["aing-idle", "v4/char/aing/idle_long", 432, HERO, 0.5, 0, 46, 30], // 첫 화면(포스터 먼저, 영상은 LCP 뒤)
  ["aing-commute-start", "v3/mac/char/aing/commute_start", 45, HERO, 0.5, 0, 42, 35], // [근무 시작] 데모 — 첫 상호작용 전 idle 시간에 미리
  ["aing-poked", "v3/mac/char/aing/poked", 90, HERO, 0.5, 0, 42, 35], // 콕 데모 — 절이 가까워지면
  ["aing-hit", "v3/mac/char/aing/hit", 36, HERO, 0.5, 0, 42, 35], // 선택(클릭 = 할 일 보드가 앱 기본, 아얏은 설정에서 끈 경우)
  ["aing-face-left", "v4/char/aing/face_left", 108, HERO, 0.5, 0, 44, 32], // 선택(드래그 방향 보기 — 앱은 즉시 스냅)
  ["aing-face-right", "v4/char/aing/face_right", 108, HERO, 0.5, 0, 44, 32],
  ["aing-ultra-charged", "v4/char/aing/ultra_charged", 102, [452, 1032, 1228, 1160], 0.5, 0, 44, 35], // 루비 절
  ["aing-ultra", "v4/char/aing/ultra_poked", 165, [260, 48, 1680, 1476], 0.5, 40, 46, 30], // 울트라 절(가장 무겁다 — 절 진입 600px 전)
];

async function exportSeq([name, dir, frames, [x, y, w, h], s, posterFrame, crf, q]) {
  if (process.env.SEQ && !process.env.SEQ.split(",").includes(name)) return null;
  const tmp = fs.mkdtempSync(path.join(process.env.TMP_DIR ?? os.tmpdir(), `aing-${name}-`)); // 프레임 임시 폴더(끝나면 지운다)
  const W = Math.round(w * s), H = Math.round(h * s);
  if (W % 2 || H % 2) throw new Error(`${name}: 홀수 크기 ${W}x${H}`);
  for (let f = 0; f < frames; f++) {
    const src = `${SRC}${dir}/${String(f).padStart(4, "0")}.png`;
    await sharp(src).extract({ left: x, top: y, width: w, height: h }).resize(W, H, { kernel: "lanczos3" }).png({ compressionLevel: 1 }).toFile(`${tmp}/${String(f).padStart(4, "0")}.png`);
  }
  const inArgs = ["-hide_banner", "-loglevel", "error", "-y", "-framerate", "30", "-i", `${tmp}/%04d.png`];
  const webm = path.join(OUT, `char/${name}.webm`), mov = path.join(OUT, `char/${name}.mov`);
  fs.mkdirSync(path.dirname(webm), { recursive: true });
  // VP9 알파(크롬·엣지·파이어폭스). auto-alt-ref 0 은 알파 인코딩 필수 조건.
  execFileSync(FF, [...inArgs, "-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-b:v", "0", "-crf", String(crf), "-row-mt", "1", "-deadline", "good", "-cpu-used", "2", "-auto-alt-ref", "0", "-an", webm], { env: ffEnv, stdio: ["ignore", "inherit", "inherit"] });
  // HEVC 알파(사파리·모든 iOS 브라우저). hvc1 태그 필수(hev1 이면 사파리가 안 튼다). 비트레이트 대신 품질 q.
  execFileSync(FF, [...inArgs, "-c:v", "hevc_videotoolbox", "-alpha_quality", "0.6", "-q:v", String(q), "-tag:v", "hvc1", "-pix_fmt", "bgra", "-movflags", "+faststart", "-an", mov], { env: ffEnv, stdio: ["ignore", "inherit", "inherit"] });
  report.push([`char/${name}.webm`, fs.statSync(webm).size], [`char/${name}.mov`, fs.statSync(mov).size]);
  // 포스터(감속 모션·저전력 모드·첫 칠) — 같은 박스·같은 크기 webp.
  put(`char/${name}-poster.webp`, await sharp(`${tmp}/${String(posterFrame).padStart(4, "0")}.png`).webp({ quality: 82, alphaQuality: 90, effort: 6 }).toBuffer());
  fs.rmSync(tmp, { recursive: true, force: true });
  return { name, box: [W, H], rect: [x, y, w, h], scale: s, frames, fps: 30 };
}

// ─── 2. 맥 스크린샷: @3x → @2x(= pt × 2). 표시 = 1 CSS px : 1 pt ────────────────────
const MAC = "v4/mac/ui/";
const UI = [
  // out, src, width(px, 생략 = pt×2), quality
  ["ui/popover-off.webp", "popover_main_off_1020@3x.png"],
  ["ui/popover-on.webp", "tick/popover_tick_on_00@3x.png"],
  ["ui/popover-working.webp", "popover_main_working_1405@3x.png"],
  ["ui/popover-newmsg.webp", "popover_main_working_1405_newmsg@3x.png"],
  ["ui/poke-list.webp", "poke_list@3x.png"],
  ["ui/poke-focus.webp", "poke_focus_stage1@3x.png"],
  ["ui/message-thread.webp", "message_thread_gureum_read@3x.png"],
  ["ui/league.webp", "league_week@3x.png"],
  ["ui/insights.webp", "insights_full@3x.png"],
  ["ui/ultra-charge.webp", "ultra_charge@3x.png"],
  ["ui/character-pick.webp", "character_pick_aing@3x.png"],
  ["ui/shop-ruby.webp", "shop_ruby@3x.png"],
  ["ui/minigame.webp", "minigame_window_flappy_playing_8rows@3x.png", 1400, 80], // 700pt × 2
  ["ui/gomoku.webp", "gomoku_playing@3x.png", 1600, 78], // 1240pt 창 → 표시 최대 800 CSS px
  ["ui/gomoku-sm.webp", "gomoku_playing@3x.png", 900, 78], // 모바일 srcset
  ["ui/todo-board.webp", "todo_board_today_opaque@3x.png"], // 알파(반투명 창) 유지
  ["ui/poke-row-mint.webp", "poke_row_mint@6x.png", 608], // 304pt × 2
];
async function exportUI() {
  for (const [out, src, width, q = 80] of UI) {
    const meta = await sharp(SRC + MAC + src).metadata();
    const scaleTag = /@(\d+)x/.exec(src)?.[1] ?? "3";
    const w = width ?? Math.round((meta.width / Number(scaleTag)) * 2);
    put(out, await sharp(SRC + MAC + src).resize({ width: w, kernel: "lanczos3" }).webp({ quality: q, alphaQuality: 90, effort: 6, smartSubsample: true }).toBuffer());
  }
  // 근무 시작 틱: on_00 위에 덮을 '변하는 열'만 12장 → 가로 스트립 한 장.
  // 차분 bbox(@3x) = (291,146)-(555,1654). 3의 배수로 넓혀 @2x 정수 좌표: x 288..558 → 192..372, y 144..1659 → 96..1106.
  const R3 = { left: 288, top: 144, width: 270, height: 1515 };
  const tw = 180, th = 1010;
  const tiles = [];
  for (let i = 0; i < 12; i++) {
    tiles.push(await sharp(`${SRC}${MAC}tick/popover_tick_on_${String(i).padStart(2, "0")}@3x.png`).extract(R3).resize(tw, th, { kernel: "lanczos3" }).png().toBuffer());
  }
  put("ui/popover-tick-strip.webp", await sharp({ create: { width: tw * 12, height: th, channels: 3, background: "#000" } })
    .composite(tiles.map((b, i) => ({ input: b, left: i * tw, top: 0 }))).webp({ quality: 82, effort: 6 }).toBuffer());
  // 메뉴바 라벨(@10x 투명판, 22pt 높이) → 표시 3배(66 CSS px 높이)의 2배 = 132px 높이.
  for (const n of ["aing_off_dark", "aing_working_0000_dark", "aing_working_0345_dark", "aing_working_0345_newmsg_dark", "aing_working_0642_dark"]) {
    put(`ui/menubar-${n.replace("aing_", "").replace(/_/g, "-")}.webp`, await sharp(`${SRC}${MAC}menubar/menubar_${n}_alpha@10x.png`).resize({ height: 132, kernel: "lanczos3" }).webp({ quality: 90, alphaQuality: 100, effort: 6 }).toBuffer());
  }
  // 말풍선(@8x, 사방 여백 10pt + 고정 폭 투명) → 알파>8 bbox(= 그림자 포함 상자)로 자르고 @3x 로.
  // 앱 배치: 오버레이 말풍선의 그림자 상자 좌상단 = main 캔버스 (323, 981)px(v3 _ui/bubble_*.png 실측, 패널 +4,+8pt).
  // 캔버스 px = @3x px × 3.5(10.5pt/px ÷ 3). 울트라 말풍선(ultra_mint)은 ultra 정사각 위쪽 가운데(앱: +56pt).
  const bubbles = {};
  for (const n of ["commute_start", "hit", "poked_mint", "ultra_mint", "first_arrival", "message_gureum", "goal_achieved", "autostart"]) {
    const src = `${SRC}${MAC}bubble/bubble_${n}@8x.png`;
    const { data, info } = await sharp(src).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    let x0 = info.width, y0 = info.height, x1 = -1, y1 = -1;
    for (let yy = 0; yy < info.height; yy++) for (let xx = 0; xx < info.width; xx++) if (data[(yy * info.width + xx) * 4 + 3] > 8) { if (xx < x0) x0 = xx; if (xx > x1) x1 = xx; if (yy < y0) y0 = yy; if (yy > y1) y1 = yy; }
    const w8 = x1 - x0 + 1, h8 = y1 - y0 + 1, w3 = Math.round((w8 * 3) / 8), h3 = Math.round((h8 * 3) / 8);
    const out = `ui/bubble-${n.replace(/_/g, "-")}.webp`;
    put(out, await sharp(src).extract({ left: x0, top: y0, width: w8, height: h8 }).resize(w3, h3, { kernel: "lanczos3" }).webp({ quality: 90, alphaQuality: 100, effort: 6 }).toBuffer());
    bubbles[n] = { file: out, px3x: [w3, h3], canvasPx: [Math.round(w3 * 3.5), Math.round(h3 * 3.5)] };
  }
  put("ui/bubbles.json", Buffer.from(JSON.stringify({ anchorCanvas: [323, 981], canvasPerPx3x: 3.5, bubbles }, null, 1)));
  // 몸통 위 근무 시간 라벨(앱 오버레이, HH:MM) — v3 _ui/timer_*.png 의 상자 (787,1686) 527×239 그대로 → S 0.5.
  for (const t of ["00-00", "00-01"]) {
    put(`ui/timer-${t}.webp`, await sharp(`${SRC}v3/mac/char/_ui/timer_${t}.png`).extract({ left: 787, top: 1686, width: 528, height: 240 }).resize(264, 120).webp({ quality: 90, alphaQuality: 100 }).toBuffer());
  }
}

// ─── 3. 아이폰: 1206×2622 @3x → 폭 600(표시 300 CSS px × 2). 다크만 ───────────────
const IOS = ["now", "now_s2", "messages", "conv-gureum_read", "rankings-league", "games", "gomoku-match", "me", "me_records", "me-characters"];
async function exportIOS() {
  for (const n of IOS) {
    put(`ios/${n.replace(/_/g, "-")}.webp`, await sharp(`${SRC}v4/ios/screens/${n}_dark@3x.png`).resize({ width: 600, kernel: "lanczos3" }).webp({ quality: 80, effort: 6, smartSubsample: true }).toBuffer());
  }
  for (const [n, w] of [["today-small", 340], ["working-medium", 728], ["todos-large", 728], ["todos-medium", 728]]) {
    put(`ios/widget-${n}.webp`, await sharp(`${SRC}v4/ios/widgets/promo_${n}_dark@3x.png`).resize({ width: w, kernel: "lanczos3" }).webp({ quality: 85, alphaQuality: 100, effort: 6 }).toBuffer());
  }
}

// ─── 4. 캐릭터 6종 정지 + 걷기 4포즈(스프라이트 5종) ─────────────────────────────
async function exportStills() {
  const m3 = JSON.parse(fs.readFileSync(`${SRC}v3/mac/char/manifest.json`, "utf8")).characters;
  for (const c of ["aing", "fox", "shiba", "jellyfish", "ghost", "squirrel"]) {
    const [x0, y0, x1, y1] = m3[c].actions.idle.alphaBBoxUnion;
    const dir = c === "aing" ? "v4/char/aing/idle_long" : `v3/mac/char/${c}/idle`;
    put(`char/still-${c}.webp`, await sharp(`${SRC}${dir}/0000.png`).extract({ left: x0, top: y0, width: x1 - x0 + 1, height: y1 - y0 + 1 })
      .resize({ height: 400, kernel: "lanczos3" }).webp({ quality: 82, alphaQuality: 90, effort: 6 }).toBuffer());
    if (c === "aing") continue; // 아잉은 3D — 걷기 없음
    // 걷기 = 아틀라스 4프레임 × 140ms(앱). 30fps 렌더에서 포즈가 바뀌는 첫 프레임 = 0·5·9·13(알파 차분으로 실측 — 5·9·13·17 에서 포즈가 바뀐다).
    const [wx0, wy0, wx1, wy1] = m3[c].actions.walk.alphaBBoxUnion;
    const ww = wx1 - wx0 + 1, wh = wy1 - wy0 + 1, th = 300, tw = Math.round((ww * th) / wh);
    const poses = await Promise.all([0, 5, 9, 13].map((f) => sharp(`${SRC}v3/mac/char/${c}/walk/${String(f).padStart(4, "0")}.png`).extract({ left: wx0, top: wy0, width: ww, height: wh }).resize(tw, th).png().toBuffer()));
    put(`char/walk-${c}.webp`, await sharp({ create: { width: tw * 4, height: th, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
      .composite(poses.map((b, i) => ({ input: b, left: i * tw, top: 0 }))).webp({ quality: 82, alphaQuality: 90, effort: 6 }).toBuffer());
  }
}

// ─── 5. 브랜드 ──────────────────────────────────────────────────────────────────
async function exportBrand() {
  put("brand/icon-256.webp", await sharp(ICON).resize(256).webp({ quality: 90, alphaQuality: 100 }).toBuffer());
  put("brand/icon-128.webp", await sharp(ICON).resize(128).webp({ quality: 90, alphaQuality: 100 }).toBuffer());
  // app/ 아래(Next 메타데이터 파일 규약): icon.png 512 · apple-icon.png 180 · favicon 은 32px png 를 icon.png 로 대체 가능
  put("../../app/icon.png", await sharp(ICON).resize(512).png({ compressionLevel: 9, palette: false }).toBuffer());
  put("../../app/apple-icon.png", await sharp(ICON).resize(180).flatten({ background: "#15172a" }).png().toBuffer());
  put("../../app/favicon-32.png", await sharp(ICON).resize(32).png().toBuffer());
  fs.copyFileSync(`${SRC}v3/brand/appstore-badge-ko-black.svg`, path.join(OUT, "brand/appstore-badge-ko-black.svg")); // 바이트 그대로(애플 규칙: 수정 금지)
  report.push(["brand/appstore-badge-ko-black.svg", sizeOf("brand/appstore-badge-ko-black.svg")]);
  put("brand/aing-face-192.webp", await sharp(`${SRC}brand/aing-neutral.png`).webp({ quality: 90, alphaQuality: 100 }).toBuffer());
}

const seqMeta = [];
if (only.includes("char")) for (const s of SEQ) { const m = await exportSeq(s); if (m) seqMeta.push(m); }
if (only.includes("ui")) await exportUI();
if (only.includes("ios")) await exportIOS();
if (only.includes("stills")) await exportStills();
if (only.includes("brand")) await exportBrand();
if (seqMeta.length) put("char/sequences.json", Buffer.from(JSON.stringify({ canvas: { main: [2100, 2625], ultra: [2160, 2160] }, sequences: seqMeta }, null, 1)));
report.sort((a, b) => a[0].localeCompare(b[0]));
let total = 0;
for (const [f, n] of report) { total += n; console.log(`${(n / 1024).toFixed(1).padStart(8)} KB  ${f}`); }
console.log(`${(total / 1024).toFixed(1).padStart(8)} KB  합계(${report.length}개)`);

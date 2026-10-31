#!/usr/bin/env node
/**
 * 아잉체크 랜딩 에셋 내보내기 — PLAN §5.1–5.3 표 69행 전부(`npm run assets`).
 *
 *   cd /Users/yesung/check/landing && node scripts/build-assets.mjs [--only=ui,char,ios,brand,data[,fonts]] [--seq=aing-idle,…]
 *
 * 묶음(--only, 기본 = ui,char,ios,brand,data):
 *   ui     1–42행  맥 렌더(@3x → @2x webp)·틱 띠·잔디·헤더·메뉴바 라벨·말풍선(@4x, SPEC v2 §9.3)
 *          + v2 크롭 V2_CROPS(SPEC v2 §9.2 — 조각·패널·근무 라벨·char/aing-rest-poster·메뉴바 아이콘)
 *   char   43–52행 캐릭터 알파 영상 두 벌(VP9 webm / HEVC mov) + 포스터. --seq 로 일부만(그때 --only 기본 = char,data)
 *   ios    53–60행 아이폰 화면·위젯 (+ v3.1 구름빵 대화 두 장)
 *   brand  61–64행 App Store 배지(복사)·QR 둘(scripts/make-qr.py — App Store · 안드로이드 베타)·아이콘 webp·app/icon.png·app/apple-icon.png
 *   v31    v3.1 새 렌더 4장(docs/v3/brief.md §9.1 · §9.5 — AI 리밋 카드 · 체스 판 · 1:1 테트리스 창 · 아이폰 AI 리밋 위젯).
 *          원본은 promo 가 아니라 렌더 에이전트 출력(env V31_MAC · V31_IOS, 기본 = 세션 스크래치). 원본이 없으면 경고만 하고
 *          이미 구운 파일을 그대로 둔다(기본 묶음 아님 — `--only=v31`).
 *   data   68–69행 data/generated/{assets,sequences,bubbles,grass}.json
 *   fonts  65–67행 = scripts/subset-fonts.mjs 를 부른다(기본 묶음 아님 — `npm run subset` 이 정식 입구). --from-spec 을 넘겨준다.
 * JSON 네 개는 어느 묶음을 돌렸든 끝에 디스크의 결과물에서 다시 쓴다(?v= 해시가 늘 파일과 맞게).
 *
 * 입력(읽기만): /Users/yesung/aing-check-promo/public/assets/ · /Users/yesung/check/packaging/appicon/icon-1024.png
 * 출력: landing/public/assets/** · landing/app/{icon,apple-icon}.png · landing/data/generated/*.json
 *
 * 도구: Node 22 + sharp(devDependency). ffmpeg = env FFMPEG(기본 Remotion 동봉판
 *   /Users/yesung/aing-check-promo/node_modules/@remotion/compositor-darwin-arm64/ffmpeg, DYLD_LIBRARY_PATH = 같은 폴더).
 *   그 판에는 pad·select·fps·crop 필터가 없다 → 박스 크롭·×0.5 축소·짝수 프레임 솎기는 sharp/JS 로 os.tmpdir()/aing-<name>-*
 *   에 프레임을 만들어 넣고, 끝나면(실패해도) 지운다. 영상 인코딩은 동시에 최대 3개(env FF_JOBS).
 *   VP9 속도: env VP9_CPU_USED(기본 2).
 *
 * 검증(끝, PLAN §5.1): ① 모든 출력 > 0 바이트(69행 출력 목록 전부 존재) ② 영상마다 입력 프레임 수 = 메타 frames,
 *   그리고 ffprobe 로 출력 패킷 수·크기·hvc1 태그·VP9 alpha_mode 확인 ③ webp 픽셀 = 표의 값 ④ 크롬 경로 합계 > 4.5MB 경고.
 *   하나라도 어긋나면 exit 1. 끝에 파일·KB·묶음별 합계 표.
 */
import { createRequire } from "node:module";
import { spawn, spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(path.join(ROOT, "package.json"));
const sharp = require("sharp");
sharp.cache(false);

const SRC = "/Users/yesung/aing-check-promo/public/assets/";
const MAC = SRC + "v4/mac/ui/";
const ICON = "/Users/yesung/check/packaging/appicon/icon-1024.png";
const OUT = path.join(ROOT, "public/assets");
const FONTS_OUT = path.join(ROOT, "public/fonts");
const GEN = path.join(ROOT, "data/generated");
const APP = path.join(ROOT, "app");
const FF = process.env.FFMPEG ?? "/Users/yesung/aing-check-promo/node_modules/@remotion/compositor-darwin-arm64/ffmpeg";
const FFPROBE = process.env.FFPROBE ?? path.join(path.dirname(FF), "ffprobe");
const FF_ENV = { ...process.env, DYLD_LIBRARY_PATH: path.dirname(FF) };
const FF_JOBS = Number(process.env.FF_JOBS ?? 3);
const CPU_USED = String(process.env.VP9_CPU_USED ?? 2);
const BUDGET = 4.5e6; // 크롬 경로 페이지 전체(SPEC §8.1)

// ─── 인자 ──────────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const argVal = (k) => args.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3);
const GROUPS = ["ui", "char", "ios", "brand", "data", "fonts", "v31"];
const seqArg = argVal("seq")?.split(",").filter(Boolean) ?? null;
const only = (argVal("only")?.split(",").filter(Boolean)) ?? (seqArg ? ["char", "data"] : ["ui", "char", "ios", "brand", "data"]);
for (const g of only) if (!GROUPS.includes(g)) fail(`알 수 없는 묶음 --only=${g} (가능: ${GROUPS.join(",")})`);

// ─── 표: 맥 렌더(@3x → @2x = 원본 폭 × 2/3) ──────────────────────────────────────
// [행, 출력, 원본(MAC 기준), 기대 [w,h], webp 옵션]
const R80 = { quality: 80, alphaQuality: 90, smartSubsample: true };
const RENDERS = [
  [1, "ui/popover-off.webp", "popover_main_off_1020@3x.png", [828, 1306], R80],
  [2, "ui/popover-on.webp", "tick/popover_tick_on_00@3x.png", [828, 1306], R80],
  [4, "ui/popover-working.webp", "popover_main_working_1405@3x.png", [828, 1306], R80],
  [5, "ui/popover-newmsg.webp", "popover_main_working_1405_newmsg@3x.png", [828, 1306], R80],
  [6, "ui/popover-off-1702.webp", "popover_main_off_1702@3x.png", [828, 1306], R80],
  [7, "ui/league.webp", "league_week@3x.png", [828, 1200], R80],
  [8, "ui/poke-list.webp", "poke_list@3x.png", [828, 1308], R80],
  [9, "ui/poke-cooldown.webp", "poke_cooldown_mint@3x.png", [828, 1308], R80],
  [10, "ui/poke-focus-1.webp", "poke_focus_stage1@3x.png", [828, 1358], R80],
  [11, "ui/poke-focus-2.webp", "poke_focus_stage2@3x.png", [828, 1358], R80],
  [12, "ui/message-composing.webp", "message_thread_gureum_composing@3x.png", [828, 1144], R80],
  [13, "ui/message-unread.webp", "message_thread_gureum_unread@3x.png", [828, 1206], R80],
  [14, "ui/message-read.webp", "message_thread_gureum_read@3x.png", [828, 1206], R80],
  [15, "ui/minigame.webp", "minigame_window_flappy_playing_8rows@3x.png", [1400, 779], R80],
  [18, "ui/character-pick.webp", "character_pick_aing@3x.png", [828, 990], R80],
  [19, "ui/todo-board.webp", "todo_board_today_opaque@3x.png", [600, 800], { quality: 80, alphaQuality: 90, smartSubsample: true }],
  [20, "ui/insights-popover.webp", "insights_popover@3x.png", [828, 1390], R80],
  [25, "ui/token-month.webp", "token_board_month@3x.png", [828, 1364], R80],
  [26, "ui/token-last.webp", "token_board_last_month@3x.png", [828, 1364], R80],
];
// 잔디(@3x 원본 크기 그대로, q88)
const GRASS = [
  [21, "ui/grass-work-empty.webp", "insights/work_grass_empty@3x.png", [912, 515]],
  [22, "ui/grass-work-final.webp", "insights/work_grass_final@3x.png", [912, 515]],
  [23, "ui/grass-token-empty.webp", "insights/token_grass_empty@3x.png", [912, 519]],
  [24, "ui/grass-token-final.webp", "insights/token_grass_final@3x.png", [912, 519]],
];
// 오른쪽 '판돈' 칸 제외(SPEC §9.1). 판(x60–1883 @3x)의 좌우 여백을 34·33px(≈11pt)로 맞춘다(수리 단계 — 예전 left 0 은 21pt·2.5pt 로 기울었다).
const GOMOKU_CROP = { left: 26, top: 0, width: 1890, height: 2100 };
// 메뉴바 라벨(@10x 투명) — 높이 66(nav) / 132(-lg), q90 a100
const LABEL = { quality: 90, alphaQuality: 100 };
const LABELS = [
  [28, "ui/menubar-off.webp", "menubar/menubar_aing_off_dark_alpha@10x.png", 66],
  [28, "ui/menubar-off-lg.webp", "menubar/menubar_aing_off_dark_alpha@10x.png", 132],
  [29, "ui/menubar-0000.webp", "menubar/menubar_aing_working_0000_dark_alpha@10x.png", 66],
  [30, "ui/menubar-0100.webp", "menubar/menubar_aing_working_0100_dark_alpha@10x.png", 66],
  [31, "ui/menubar-0345.webp", "menubar/menubar_aing_working_0345_dark_alpha@10x.png", 66],
  [32, "ui/menubar-0345-newmsg.webp", "menubar/menubar_aing_working_0345_newmsg_dark_alpha@10x.png", 66],
  [33, "ui/menubar-0642.webp", "menubar/menubar_aing_working_0642_dark_alpha@10x.png", 66],
  [33, "ui/menubar-0642-lg.webp", "menubar/menubar_aing_working_0642_dark_alpha@10x.png", 132],
  [29, "ui/menubar-0000-lg.webp", "menubar/menubar_aing_working_0000_dark_alpha@10x.png", 132], // v2 히어로 돔 꼭대기 라벨(SPEC v2 §9.2)
];
// 말풍선(@8x 투명) — 알파>8 bbox 크롭 → × 1/2(= @4x px, SPEC v2 §9.3). id = SPEC §3.5 / fixtures BubbleId
//   bubbles.json 의 px3x·canvasPx 는 파일 픽셀이 아니라 bbox 에서 계산(= round(bbox × 3/8) × 3.5) → v1(@3x) 값 그대로.
const BUBBLES = [
  [35, "commute-start", "bubble/bubble_commute_start@8x.png"],
  [36, "autostart", "bubble/bubble_autostart@8x.png"],
  [37, "poked-mint", "bubble/bubble_poked_mint@8x.png"],
  [38, "message-gureum", "bubble/bubble_message_gureum@8x.png"],
  [39, "commute-end", "bubble/bubble_commute_end@8x.png"],
  [40, "ultra-mint", "bubble/bubble_ultra_mint@8x.png"],
  [41, "update", "bubble/bubble_update@8x.png"],
];
// 루비 말풍선(42행): 캔버스 층 bubble_00.png 의 (323,981)–(948,1290) = 625×309 캔버스 px → ÷ 2.625 = @4x px 파일
//   (bubbles.json 은 ÷ 3.5 = @3x px 로 계속 — canvasPx 불변)
const RUBY = { src: SRC + "v4/char/aing/_ui/bubble_00.png", box: { left: 323, top: 981, width: 625, height: 309 } };
const BUBBLE_ORDER = ["commute-start", "autostart", "poked-mint", "message-gureum", "commute-end", "ruby", "ultra-mint", "update"];
const ANCHOR_CANVAS = [323, 981];
const CANVAS_PER_PX3X = 3.5;
const CANVAS_PER_PX4X = 2.625; // = 3.5 × 3/4
// 틱 띠(3행): 12장의 (288,144) 270×1515 → 180×1010, 12칸 가로 2160×1010
const TICK = { region: { left: 288, top: 144, width: 270, height: 1515 }, tile: [180, 1010], count: 12, displayPt: [90, 505] };

// ─── v2 크롭(SPEC v2 §9.2 · PLAN v2 §5.2) — 크롭·리사이즈·품질만(덧그리기 0) ────────────
// [출력, 원본(SRC 기준), extract | null, resize {width|height} | null, webp 옵션, 기대 [w,h]]
// poke·token·league 조각은 아바타 열(센터 배지)을 뺀다(DECISIONS D17) — 감사는 .scratch/assets/badges.png.
// char/aing-rest-poster 는 영상 묶음을 돌리지 않으려고 ui 묶음에서 굽는다(HERO 박스 × 0.5 = 모든 반응 시퀀스 0번 프레임).
const V2_CROPS = [
  ["ui/header-on-lg.webp", "v4/mac/ui/header/header_on_1020@4x.png", null, null, { quality: 85, alphaQuality: 90 }, [1264, 428]],
  ["ui/poke-slice.webp", "v4/mac/ui/poke_list@3x.png", { left: 228, top: 390, width: 762, height: 852 }, null, R80, [762, 852]],
  ["ui/token-slice.webp", "v4/mac/ui/token_board_month@3x.png", { left: 246, top: 390, width: 708, height: 1005 }, { width: 472 }, R80, [472, 670]],
  ["ui/league-slice.webp", "v4/mac/ui/league_week@3x.png", { left: 216, top: 540, width: 744, height: 640 }, { width: 496 }, R80, [496, 427]],
  ["ui/message-unread-panel.webp", "v4/mac/ui/message_thread_gureum_unread@3x.png", { left: 36, top: 390, width: 954, height: 900 }, null, R80, [954, 900]],
  ["ui/message-read-panel.webp", "v4/mac/ui/message_thread_gureum_read@3x.png", { left: 36, top: 390, width: 954, height: 900 }, null, R80, [954, 900]],
  ["ui/character-panel.webp", "v4/mac/ui/character_pick_aing@3x.png", { left: 36, top: 390, width: 954, height: 900 }, null, R80, [954, 900]],
  ["ui/timer-00-00.webp", "v3/mac/char/_ui/timer_00-00.png", { left: 787, top: 1686, width: 527, height: 239 }, { width: 264 }, { quality: 90, alphaQuality: 100 }, [264, 120]],
  ["char/aing-rest-poster.webp", "v3/mac/char/aing/commute_start/0000.png", { left: 424, top: 544, width: 1308, height: 1580 } /* = HERO */, { width: 654 }, { quality: 80, alphaQuality: 90, smartSubsample: true }, [654, 790]],
  ["ui/menubar-icon.webp", "v4/mac/ui/menubar/menubar_aing_icon_working@10x.png", null, { width: 66 }, LABEL, [66, 66]],
];
// timer 크롭 = 알파 bbox 실측(SPEC §9.2). 원본이 바뀌어 bbox 가 달라지면 경고(크롭은 표 값 그대로).
const V2_BBOX_CHECK = { "ui/timer-00-00.webp": { left: 787, top: 1686, width: 527, height: 239 } };

// ─── 표: 캐릭터 시퀀스(43–52행) ─────────────────────────────────────────────────
// box = 캔버스 좌표 [x, y, w, h](w·h 4의 배수 → ×0.5 짝수). offsetOut = (박스 원점 − HERO 원점) × scale(PLAN §3.5).
const CANVAS = { main: [2100, 2625], ultra: [2160, 2160] };
const HERO = [424, 544, 1308, 1580];
const SCALE = 0.5;
const SEQS = [
  { row: 43, name: "aing-idle", dir: "v4/char/aing/idle_long", frames: 432, canvas: "main", box: HERO, crf: 46, q: 30, gop: 30, loop: true,
    poster: { row: 45, frame: 0 }, low: { row: 44, fps: 15, crf: 44, q: 40, gop: 15 } },
  { row: 46, name: "aing-commute-start", dir: "v3/mac/char/aing/commute_start", frames: 45, canvas: "main", box: HERO, crf: 42, q: 35, gop: 30, loop: false },
  { row: 47, name: "aing-commute-end", dir: "v3/mac/char/aing/commute_end", frames: 36, canvas: "main", box: HERO, crf: 42, q: 35, gop: 30, loop: false },
  { row: 48, name: "aing-poked", dir: "v3/mac/char/aing/poked", frames: 90, canvas: "main", box: HERO, crf: 42, q: 35, gop: 30, loop: false },
  // milestone: crf 42 → 54 · q 35 → 20(수리 단계 P-6 — 666KB 로 SPEC §8.1 예상 240KB 의 2.8배였다)
  { row: 49, name: "aing-milestone", dir: "v3/mac/char/aing/milestone", frames: 72, canvas: "main", box: [308, 544, 1544, 1580], crf: 54, q: 20, gop: 30, loop: false },
  { row: 50, name: "aing-ultra-charged", dir: "v4/char/aing/ultra_charged", frames: 102, canvas: "main", box: [452, 1032, 1228, 1160], crf: 44, q: 35, gop: 30, loop: false },
  // ultra: 0.75배(1260×1108) — 1440×900 에서 영상 상자 686 CSS px = DPR2 1,372 기기 px 라 0.5배(840)는 1.63배 확대로 물렀다(수리 단계 D-17).
  //   근접 시에만 받는 지연 로드라 첫 화면 예산과 무관. 높이 1107 은 짝수로(1108 — 비율 차 0.09%).
  { row: 51, name: "aing-ultra", dir: "v4/char/aing/ultra_poked", frames: 72, canvas: "ultra", box: [260, 48, 1680, 1476], crf: 46, q: 30, gop: 30, loop: false,
    scale: 0.75, poster: { row: 52, frame: 40 } }, // 원본은 165장 — 0000–0071 만(SPEC 울트라 72프레임)
];
const even = (n) => Math.round(n / 2) * 2;
for (const s of SEQS) {
  const [, , w, h] = s.box;
  if (w % 4 || h % 4) fail(`${s.name}: 박스 w·h 가 4의 배수가 아니다(${w}×${h})`);
  s.scale = s.scale ?? SCALE;
  s.size = [even(w * s.scale), even(h * s.scale)];
  s.offsetOut = s.canvas === "main" ? [(s.box[0] - HERO[0]) * s.scale, (s.box[1] - HERO[1]) * s.scale] : null;
}
{
  const rest = V2_CROPS.find(([rel]) => rel === "char/aing-rest-poster.webp")?.[2];
  if (!rest || rest.left !== HERO[0] || rest.top !== HERO[1] || rest.width !== HERO[2] || rest.height !== HERO[3]) fail(`char/aing-rest-poster 크롭 ${JSON.stringify(rest)} ≠ HERO ${HERO.join(",")}`);
}
if (seqArg) for (const n of seqArg) if (!SEQS.some((s) => s.name === n)) fail(`알 수 없는 --seq=${n} (가능: ${SEQS.map((s) => s.name).join(",")})`);

// ─── 표: 아이폰(53–60행) ────────────────────────────────────────────────────────
const IOS = [
  [53, "ios/now.webp", "v4/ios/screens/now_dark@3x.png", [600, 1304], { quality: 80, smartSubsample: true }],
  [54, "ios/messages.webp", "v4/ios/screens/messages_dark@3x.png", [600, 1304], { quality: 80, smartSubsample: true }],
  [55, "ios/rankings-league.webp", "v4/ios/screens/rankings-league_dark@3x.png", [600, 1304], { quality: 80, smartSubsample: true }],
  [56, "ios/games.webp", "v4/ios/screens/games_dark@3x.png", [600, 1304], { quality: 80, smartSubsample: true }],
  [57, "ios/me-records.webp", "v4/ios/screens/me_records_dark@3x.png", [600, 1304], { quality: 80, smartSubsample: true }],
  [58, "ios/widget-todos-large.webp", "v4/ios/widgets/promo_todos-large_dark@3x.png", [728, 764], { quality: 85, alphaQuality: 100 }],
  [59, "ios/widget-todos-large-checked.webp", "v4/ios/widgets/promo_todos-large-checked_dark@3x.png", [728, 764], { quality: 85, alphaQuality: 100 }],
  [60, "ios/widget-today-small.webp", "v4/ios/widgets/promo_today-small_dark@3x.png", [340, 340], { quality: 85, alphaQuality: 100 }],
  // v3.1(docs/v3/brief.md §9.1 f-message): 맥 1:1 메시지 패널과 같은 구름빵 대화(11:54–14:04). 보낸 직후 '1' → 읽음(고정 무대에서 맥 패널과 함께 교체)
  ["v3.1", "ios/conv-gureum-sent.webp", "v4/ios/screens/conv-gureum_sent1_dark@3x.png", [600, 1304], { quality: 80, smartSubsample: true }],
  ["v3.1", "ios/conv-gureum-read.webp", "v4/ios/screens/conv-gureum_read_dark@3x.png", [600, 1304], { quality: 80, smartSubsample: true }],
];

// ─── 표: v3.1 새 렌더(§9.5) — [출력, 원본(절대 경로), 리사이즈 폭 | null, 기대 [w,h], webp 옵션] ─────────────────
// 맥 렌더는 @3x 불투명 다크(창 크롬 없음 — 랜딩이 frame 을 씌운다). 폭은 기존 관례대로: 판은 작은 판(오목 sm 700)과 같게,
// 테트리스 두 판 크롭·위젯은 @3x → @2x. 리밋 카드는 1pt 보다 크게 보이는 주인공(1440 에서 ≥ 400 css)이라
// @3x 그대로(1020 — DPR 2 에서도 흐리지 않게).
const V31_MAC = process.env.V31_MAC ?? "/private/tmp/claude-501/-Users-yesung-check/2e0b98fb-2bf2-4358-9866-db6bfc6f2d59/scratchpad/agents/render-mac/out/";
const V31_IOS = process.env.V31_IOS ?? "/private/tmp/claude-501/-Users-yesung-check/2e0b98fb-2bf2-4358-9866-db6bfc6f2d59/scratchpad/agents/render-ios/out/";
const V31_CROP = process.env.V31_CROP ?? "/private/tmp/claude-501/-Users-yesung-check/2e0b98fb-2bf2-4358-9866-db6bfc6f2d59/scratchpad/crop/";
const V31 = [
  ["ui/ai-limits-card.webp", V31_MAC + "mac-ai-limits-card@3x.png", null, [1020, 417], R80],
  ["ui/chess-board.webp", V31_MAC + "mac-chess-board@3x.png", 700, [700, 700], { quality: 78, alphaQuality: 90, smartSubsample: true }],
  // 테트리스: 사용자 지정 크롭(brief §9.5 마지막 줄 — 두 사람 카드+판만, 원본 2700×1662 의 (38,330)–(1836,1626), 사방 22px 창 바탕) → @2x 폭
  ["ui/tetris-duel.webp", V31_CROP + "mac-tetris-duel-boards@3x.png", 1200, [1200, 865], R80],
  ["ios/widget-limits-medium.webp", V31_IOS + "ios-widget-limits-medium_dark@3x.png", 728, [728, 340], { quality: 85, alphaQuality: 100 }],
];

// ─── 공용 ──────────────────────────────────────────────────────────────────────
const errors = [];
const warnings = [];
const tmpDirs = new Set();
const children = new Set();
const encoded = []; // 이번 실행에서 인코딩한 영상(입력 프레임 수 검증 기록)

function fail(msg) {
  console.error(`build-assets: ${msg}`);
  cleanup();
  process.exit(1);
}
function cleanup() {
  for (const c of children) try { c.kill("SIGKILL"); } catch { /* 이미 끝남 */ }
  for (const d of tmpDirs) fs.rmSync(d, { recursive: true, force: true });
  tmpDirs.clear();
}
process.on("SIGINT", () => { cleanup(); process.exit(130); });
process.on("SIGTERM", () => { cleanup(); process.exit(143); });

const pad4 = (n) => String(n).padStart(4, "0");
const sha8 = (buf) => crypto.createHash("sha1").update(buf).digest("hex").slice(0, 8);
const outAbs = (rel) => path.join(OUT, rel);
function mkTmp(name) {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), `aing-${name}-`));
  tmpDirs.add(d);
  return d;
}
function rmTmp(d) {
  fs.rmSync(d, { recursive: true, force: true });
  tmpDirs.delete(d);
}
function writeFile(abs, buf) {
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, buf);
}
function expectDims(label, got, want) {
  const [w, h] = want;
  if ((w != null && got[0] !== w) || (h != null && got[1] !== h)) errors.push(`③ ${label}: ${got[0]}×${got[1]} ≠ 표 ${w ?? "*"}×${h ?? "*"}`);
}
/** sharp 파이프라인 → webp → 쓰기 → 픽셀 크기 검사. */
async function webp(rel, pipeline, opts, want) {
  const buf = await pipeline.webp({ effort: 6, ...opts }).toBuffer();
  writeFile(outAbs(rel), buf);
  const m = await sharp(buf).metadata();
  if (want) expectDims(rel, [m.width, m.height], want);
  return { buf, w: m.width, h: m.height };
}
async function pool(items, n, fn) {
  const q = items.map((it, i) => [it, i]);
  const workers = Array.from({ length: Math.min(n, q.length) }, async () => {
    for (let job = q.shift(); job; job = q.shift()) await fn(job[0], job[1]);
  });
  await Promise.all(workers);
}
let ffSlots = FF_JOBS;
const ffWaiters = [];
async function withFfSlot(fn) {
  if (ffSlots > 0) ffSlots--;
  else await new Promise((r) => ffWaiters.push(r));
  try {
    return await fn();
  } finally {
    const next = ffWaiters.shift();
    if (next) next();
    else ffSlots++;
  }
}
function runProc(cmd, argv, env) {
  return new Promise((resolve, reject) => {
    const c = spawn(cmd, argv, { env, stdio: ["ignore", "pipe", "pipe"] });
    children.add(c);
    let out = "";
    let err = "";
    c.stdout.on("data", (d) => (out += d));
    c.stderr.on("data", (d) => (err += d));
    c.on("error", (e) => { children.delete(c); reject(e); });
    c.on("close", (code, sig) => {
      children.delete(c);
      if (code === 0) resolve({ out, err });
      else reject(new Error(`${path.basename(cmd)} exit ${code ?? sig}: ${err.trim().slice(-2000)}`));
    });
  });
}
async function alphaBBox(file, thr = 8) {
  const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  let x0 = info.width, y0 = info.height, x1 = -1, y1 = -1;
  for (let y = 0; y < info.height; y++) {
    const row = y * info.width * 4;
    for (let x = 0; x < info.width; x++) {
      if (data[row + x * 4 + 3] > thr) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) throw new Error(`${file}: 알파>${thr} 픽셀 없음`);
  return { left: x0, top: y0, width: x1 - x0 + 1, height: y1 - y0 + 1 };
}

// ─── ui (1–42행) ────────────────────────────────────────────────────────────────
async function buildUI() {
  const t0 = Date.now();
  await pool(RENDERS, 4, async ([, rel, src, want, opts]) => {
    const m = await sharp(MAC + src).metadata();
    const w = Math.round((m.width * 2) / 3);
    await webp(rel, sharp(MAC + src).resize({ width: w, kernel: "lanczos3" }), opts, want);
  });
  await pool(GRASS, 4, async ([, rel, src, want]) => {
    await webp(rel, sharp(MAC + src), { quality: 88, alphaQuality: 90 }, want);
  });
  // 16·17행 오목: 크롭 (0,0,1890,2100) → 1260×1400 / 700×778, q78
  await webp("ui/gomoku-board.webp", sharp(MAC + "gomoku_playing@3x.png").extract(GOMOKU_CROP).resize({ width: 1260, kernel: "lanczos3" }), { quality: 78, alphaQuality: 90, smartSubsample: true }, [1260, 1400]);
  await webp("ui/gomoku-board-sm.webp", sharp(MAC + "gomoku_playing@3x.png").extract(GOMOKU_CROP).resize({ width: 700, kernel: "lanczos3" }), { quality: 78, alphaQuality: 90, smartSubsample: true }, [700, 778]);
  // 27행 헤더 @4x → @2x(원본 폭 / 2), q85
  {
    const src = MAC + "header/header_off_1702@4x.png";
    const m = await sharp(src).metadata();
    await webp("ui/header-off-1702.webp", sharp(src).resize({ width: Math.round(m.width / 2), kernel: "lanczos3" }), { quality: 85, alphaQuality: 90 }, [632, 214]);
  }
  // 3행 틱 띠
  {
    const [tw, th] = TICK.tile;
    const tiles = [];
    for (let i = 0; i < TICK.count; i++) {
      const src = `${MAC}tick/popover_tick_on_${String(i).padStart(2, "0")}@3x.png`;
      tiles.push(await sharp(src).extract(TICK.region).resize(tw, th, { kernel: "lanczos3", fit: "fill" }).removeAlpha().png().toBuffer());
    }
    const strip = sharp({ create: { width: tw * TICK.count, height: th, channels: 3, background: "#000000" } }).composite(tiles.map((input, i) => ({ input, left: i * tw, top: 0 })));
    await webp("ui/popover-tick-strip.webp", strip, { quality: 82 }, [tw * TICK.count, th]);
  }
  // 28–33행 메뉴바 라벨
  await pool(LABELS, 4, async ([, rel, src, h]) => {
    await webp(rel, sharp(MAC + src).resize({ height: h, kernel: "lanczos3" }), LABEL, [null, h]);
  });
  // 34행 메뉴바 아이콘(점)
  await webp("ui/menubar-icon-dot.webp", sharp(MAC + "menubar/menubar_aing_icon_working_dot@10x.png").resize(66, 66, { kernel: "lanczos3", fit: "fill" }), LABEL, [66, 66]);
  // 35–42행 말풍선 @4x(SPEC v2 §9.3) — 루비는 캔버스 층(크롭 상자가 실제 알파 bbox 와 같은지는 bubbleGeometry 가 확인)
  const geom = await bubbleGeometry();
  await pool(BUBBLE_ORDER, 4, async (id) => {
    const g = geom.get(id);
    const [w4, h4] = g.px4x;
    await webp(`ui/bubble-${id}.webp`, sharp(g.src).extract(g.box).resize(w4, h4, { kernel: "lanczos3", fit: "fill" }), { quality: 90, alphaQuality: 100 }, [w4, h4]);
  });
  // v2 크롭(SPEC v2 §9.2) — 크롭·리사이즈·품질만
  await pool(V2_CROPS, 4, async ([rel, src, extract, resize, opts, want]) => {
    const file = SRC + src;
    if (V2_BBOX_CHECK[rel]) {
      const bb = await alphaBBox(file);
      const b = V2_BBOX_CHECK[rel];
      if (bb.left !== b.left || bb.top !== b.top || bb.width !== b.width || bb.height !== b.height) {
        warnings.push(`${rel}: 원본 알파 bbox ${JSON.stringify(bb)} ≠ 표 크롭 ${JSON.stringify(b)} — 표 값으로 자름`);
      }
    }
    let p = sharp(file);
    if (extract) p = p.extract(extract);
    if (resize) p = p.resize({ ...resize, kernel: "lanczos3" });
    await webp(rel, p, opts, want);
  });
  console.log(`build-assets: ui 끝 (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
}

/**
 * 말풍선 기하(한 실행에 한 번). id → { src, box(원본 크롭), px3x(@3x 논리 px — bubbles.json·canvasPx 용), px4x(파일 픽셀) }.
 * 일반 말풍선: box = @8x 원본의 알파>8 bbox, px3x = round(bbox × 3/8), px4x = round(bbox / 2).
 * 루비: box = RUBY.box(캔버스 px), px3x = round(box ÷ 3.5), px4x = round(box ÷ 2.625).
 */
let bubbleGeomCache = null;
function bubbleGeometry() {
  bubbleGeomCache ??= (async () => {
    const m = new Map();
    await pool(BUBBLES, 4, async ([, id, src]) => {
      const bb = await alphaBBox(MAC + src);
      m.set(id, {
        src: MAC + src,
        box: bb,
        px3x: [Math.round((bb.width * 3) / 8), Math.round((bb.height * 3) / 8)],
        px4x: [Math.round(bb.width / 2), Math.round(bb.height / 2)],
      });
    });
    const bb = await alphaBBox(RUBY.src);
    const b = RUBY.box;
    if (bb.left !== b.left || bb.top !== b.top || bb.width !== b.width || bb.height !== b.height) {
      warnings.push(`42행 bubble_00.png 알파 bbox ${JSON.stringify(bb)} ≠ 스펙 크롭 ${JSON.stringify(b)} — 스펙 값으로 자름`);
    }
    m.set("ruby", {
      src: RUBY.src,
      box: b,
      px3x: [Math.round(b.width / CANVAS_PER_PX3X), Math.round(b.height / CANVAS_PER_PX3X)],
      px4x: [Math.round(b.width / CANVAS_PER_PX4X), Math.round(b.height / CANVAS_PER_PX4X)],
    });
    for (const id of BUBBLE_ORDER) if (!m.has(id)) throw new Error(`말풍선 기하 없음: ${id}`);
    return m;
  })();
  return bubbleGeomCache;
}

// ─── char (43–52행) ─────────────────────────────────────────────────────────────
function vp9Args(dir, fps, crf, gop, out) {
  return ["-hide_banner", "-nostdin", "-loglevel", "error", "-y", "-framerate", String(fps), "-i", `${dir}/%04d.png`,
    "-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-b:v", "0", "-crf", String(crf), "-row-mt", "1", "-deadline", "good", "-cpu-used", CPU_USED,
    "-auto-alt-ref", "0", "-g", String(gop), "-an", out];
}
function hevcArgs(dir, fps, q, gop, out) {
  return ["-hide_banner", "-nostdin", "-loglevel", "error", "-y", "-framerate", String(fps), "-i", `${dir}/%04d.png`,
    "-c:v", "hevc_videotoolbox", "-alpha_quality", "0.6", "-q:v", String(q), "-tag:v", "hvc1", "-pix_fmt", "bgra", "-g", String(gop),
    "-movflags", "+faststart", "-an", out];
}
const countPngs = (dir) => fs.readdirSync(dir).filter((f) => /^\d{4}\.png$/.test(f)).length;

async function encodePair(label, framesDir, fps, crf, q, gop, outBase, expectFrames) {
  const n = countPngs(framesDir);
  encoded.push({ label, inputFrames: n, frames: expectFrames });
  if (n !== expectFrames) errors.push(`② ${label}: 입력 프레임 ${n} ≠ 메타 frames ${expectFrames}`);
  const encDir = mkTmp(`${label}-enc`);
  try {
    const webm = path.join(encDir, "o.webm");
    const mov = path.join(encDir, "o.mov");
    const t0 = Date.now();
    await Promise.all([
      withFfSlot(() => runProc(FF, vp9Args(framesDir, fps, crf, gop, webm), FF_ENV)).then(() => console.log(`  ${label}.webm ${((Date.now() - t0) / 1000).toFixed(1)}s`)),
      withFfSlot(() => runProc(FF, hevcArgs(framesDir, fps, q, gop, mov), FF_ENV)).then(() => console.log(`  ${label}.mov ${((Date.now() - t0) / 1000).toFixed(1)}s`)),
    ]);
    fs.mkdirSync(path.dirname(outAbs(outBase)), { recursive: true });
    fs.copyFileSync(webm, outAbs(`${outBase}.webm`));
    fs.copyFileSync(mov, outAbs(`${outBase}.mov`));
  } finally {
    rmTmp(encDir);
  }
}

async function buildSeq(s) {
  const t0 = Date.now();
  const [x, y, w, h] = s.box;
  const [W, H] = s.size;
  const srcDir = SRC + s.dir;
  const first = await sharp(`${srcDir}/0000.png`).metadata();
  const [cw, ch] = CANVAS[s.canvas];
  if (first.width !== cw || first.height !== ch) errors.push(`${s.name}: 원본 캔버스 ${first.width}×${first.height} ≠ ${s.canvas} ${cw}×${ch}`);
  for (let f = 0; f < s.frames; f++) if (!fs.existsSync(`${srcDir}/${pad4(f)}.png`)) fail(`${s.name}: 원본 프레임 없음 ${srcDir}/${pad4(f)}.png`);
  const frames = mkTmp(s.name);
  try {
    await pool(Array.from({ length: s.frames }, (_, f) => f), 6, async (f) => {
      await sharp(`${srcDir}/${pad4(f)}.png`).extract({ left: x, top: y, width: w, height: h }).resize(W, H, { kernel: "lanczos3", fit: "fill" })
        .png({ compressionLevel: 1 }).toFile(`${frames}/${pad4(f)}.png`);
    });
    console.log(`  ${s.name}: 프레임 ${s.frames}장 준비 ${((Date.now() - t0) / 1000).toFixed(1)}s`);
    if (s.poster) {
      await webp(`char/${s.name}-poster.webp`, sharp(`${frames}/${pad4(s.poster.frame)}.png`), { quality: 82, alphaQuality: 90 }, [W, H]);
    }
    const jobs = [encodePair(s.name, frames, 30, s.crf, s.q, s.gop, `char/${s.name}`, s.frames)];
    if (s.low) {
      // 15fps 판: 짝수 프레임만 하드링크로 다시 번호를 매긴다(ffmpeg 축소판에 select·fps 필터가 없다)
      const low = mkTmp(`${s.name}-15`);
      const lowFrames = Math.ceil(s.frames / 2);
      for (let i = 0; i < lowFrames; i++) fs.linkSync(`${frames}/${pad4(i * 2)}.png`, `${low}/${pad4(i)}.png`);
      jobs.push(encodePair(`${s.name}-15`, low, s.low.fps, s.low.crf, s.low.q, s.low.gop, `char/${s.name}-15`, lowFrames).finally(() => rmTmp(low)));
    }
    await Promise.all(jobs);
  } finally {
    rmTmp(frames);
  }
  console.log(`build-assets: ${s.name} 끝 (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
}

async function buildChar() {
  const t0 = Date.now();
  const list = SEQS.filter((s) => !seqArg || seqArg.includes(s.name));
  // 시퀀스 3개까지 동시에(프레임 준비는 sharp, 인코딩은 ffmpeg 슬롯 FF_JOBS 개가 묶는다)
  await pool(list, 3, buildSeq);
  console.log(`build-assets: char 끝 (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
}

// ─── ios (53–60행) ──────────────────────────────────────────────────────────────
async function buildIOS() {
  await pool(IOS, 4, async ([, rel, src, want, opts]) => {
    await webp(rel, sharp(SRC + src).resize({ width: want[0], kernel: "lanczos3" }), opts, want);
  });
  console.log("build-assets: ios 끝");
}

// ─── v31(v3.1 새 렌더) ─────────────────────────────────────────────────────────────
async function buildV31() {
  await pool(V31, 4, async ([rel, src, width, want, opts]) => {
    if (!fs.existsSync(src)) {
      warnings.push(`v31 원본 없음: ${src} — 이미 구운 public/assets/${rel} 를 그대로 둔다`);
      return;
    }
    let p = sharp(src);
    if (width) p = p.resize({ width, kernel: "lanczos3" });
    await webp(rel, p, opts, want);
  });
  console.log("build-assets: v31 끝");
}

// ─── brand (61–64행) ────────────────────────────────────────────────────────────
async function buildBrand() {
  // 61행 배지: 바이트 그대로
  const badgeSrc = SRC + "v3/brand/appstore-badge-ko-black.svg";
  fs.mkdirSync(outAbs("brand"), { recursive: true });
  fs.copyFileSync(badgeSrc, outAbs("brand/appstore-badge-ko-black.svg"));
  if (!fs.readFileSync(badgeSrc).equals(fs.readFileSync(outAbs("brand/appstore-badge-ko-black.svg")))) errors.push("61행 배지 바이트가 원본과 다르다");
  // 62행 QR: scripts/make-qr.py(App Store · 안드로이드 베타 안내 /#android — docs/v3/brief.md §12)
  const py = process.env.PYTHON ?? "python3";
  const r = spawnSync(py, [path.join(ROOT, "scripts/make-qr.py")], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  if (r.status !== 0) errors.push(`62행 make-qr.py 실패(exit ${r.status ?? r.error?.message}): ${(r.stderr || "").trim()}`);
  else console.log(`  ${r.stdout.trim()}`);
  // 63행 아이콘 webp
  await webp("brand/icon-64.webp", sharp(ICON).resize(64, 64, { kernel: "lanczos3" }), { quality: 90, alphaQuality: 100 }, [64, 64]);
  await webp("brand/icon-256.webp", sharp(ICON).resize(256, 256, { kernel: "lanczos3" }), { quality: 90, alphaQuality: 100 }, [256, 256]);
  // 64행 app/icon.png(128, 팔레트 PNG) · app/apple-icon.png(180, #12131C 평탄화)
  // 파비콘은 탭에서 16–32px 이라 128 이면 넉넉하다. 256 풀컬러(53KB)는 첫 방문마다 받는 그림 중 가장 무거웠다(수리 단계 P-9).
  const icon = await sharp(ICON).resize(128, 128, { kernel: "lanczos3" }).png({ compressionLevel: 9, palette: true, quality: 95, effort: 10 }).toBuffer();
  writeFile(path.join(APP, "icon.png"), icon);
  const apple = await sharp(ICON).resize(180, 180, { kernel: "lanczos3" }).flatten({ background: "#12131C" }).png({ compressionLevel: 9 }).toBuffer();
  writeFile(path.join(APP, "apple-icon.png"), apple);
  const mi = await sharp(icon).metadata();
  const ma = await sharp(apple).metadata();
  expectDims("app/icon.png", [mi.width, mi.height], [128, 128]);
  expectDims("app/apple-icon.png", [ma.width, ma.height], [180, 180]);
  if (ma.hasAlpha) errors.push("app/apple-icon.png 에 알파가 남아 있다(평탄화 실패)");
  console.log("build-assets: brand 끝");
}

// ─── fonts (65–67행) — subset-fonts.mjs 위임 ─────────────────────────────────────
function buildFonts() {
  const r = spawnSync(process.execPath, [path.join(ROOT, "scripts/subset-fonts.mjs"), ...(args.includes("--from-spec") ? ["--from-spec"] : [])], { stdio: ["ignore", "inherit", "inherit"] });
  if (r.status !== 0) errors.push(`65–67행 subset-fonts.mjs 실패(exit ${r.status})`);
}

// ─── data (68–69행) — 디스크의 결과물에서 쓴다 ───────────────────────────────────
function listFiles(dir) {
  const out = [];
  const walk = (d) => {
    if (!fs.existsSync(d)) return;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      if (e.name.startsWith(".")) continue;
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else out.push(p);
    }
  };
  walk(dir);
  return out.sort();
}
function fileRef(rel) {
  const abs = outAbs(rel);
  if (!fs.existsSync(abs)) {
    errors.push(`① 출력 없음: public/assets/${rel}`);
    return { src: null, bytes: 0, buf: null };
  }
  const buf = fs.readFileSync(abs);
  return { src: `/assets/${rel}?v=${sha8(buf)}`, bytes: buf.length, buf };
}
/**
 * generated JSON 쓰기 — 데브 서버가 import 하므로 반쯤 쓴 파일이 보이는 순간이 없게 같은 폴더 임시 이름에 쓴 뒤 rename.
 * 내용이 같으면 건드리지 않는다(mtime·HMR 그대로).
 */
function writeJSON(name, obj) {
  const dest = path.join(GEN, name);
  const buf = Buffer.from(JSON.stringify(obj, null, 2) + "\n");
  if (fs.existsSync(dest) && fs.readFileSync(dest).equals(buf)) return;
  fs.mkdirSync(GEN, { recursive: true });
  const tmp = path.join(GEN, `.${name}.tmp-${process.pid}`);
  try {
    fs.writeFileSync(tmp, buf);
    JSON.parse(fs.readFileSync(tmp, "utf8")); // 쓴 그대로 읽히는지
    fs.renameSync(tmp, dest);
  } finally {
    fs.rmSync(tmp, { force: true });
  }
}
const r2 = (n) => Math.round(n * 100) / 100;

async function buildData() {
  // assets.json — public/assets 의 이미지 전부(webp·svg). 영상은 sequences.json 에만.
  const assets = {};
  for (const abs of listFiles(OUT)) {
    if (!/\.(webp|svg|png)$/.test(abs)) continue;
    const rel = path.relative(OUT, abs).split(path.sep).join("/");
    const buf = fs.readFileSync(abs);
    const m = await sharp(buf).metadata();
    assets[rel.replace(/\.[^.]+$/, "")] = { src: `/assets/${rel}?v=${sha8(buf)}`, w: m.width, h: m.height, bytes: buf.length };
  }
  writeJSON("assets.json", assets);

  // sequences.json(PLAN §3.5)
  const sequences = {};
  for (const s of SEQS) {
    const webm = fileRef(`char/${s.name}.webm`);
    const mov = fileRef(`char/${s.name}.mov`);
    const meta = { kind: "video", fps: 30, frames: s.frames, loop: s.loop, canvas: s.canvas, box: s.box, scale: s.scale, size: s.size, offsetOut: s.offsetOut, gop: s.gop,
      src: { webm: webm.src, mov: mov.src } };
    if (s.low) {
      const lw = fileRef(`char/${s.name}-15.webm`);
      const lm = fileRef(`char/${s.name}-15.mov`);
      meta.low = { fps: s.low.fps, frames: Math.ceil(s.frames / 2), gop: s.low.gop, src: { webm: lw.src, mov: lm.src }, bytes: { webm: lw.bytes, mov: lm.bytes } };
    }
    if (s.poster) {
      meta.poster = fileRef(`char/${s.name}-poster.webp`).src;
      meta.posterFrame = s.poster.frame;
    } else {
      meta.poster = null;
    }
    meta.bytes = { webm: webm.bytes, mov: mov.bytes };
    sequences[s.name] = meta;
  }
  const tick = fileRef("ui/popover-tick-strip.webp");
  sequences.tick = { kind: "sheet", fps: 1, frames: TICK.count, loop: false, hold: "last", src: tick.src, frameSize: TICK.tile, cols: TICK.count, rows: 1, displayPt: TICK.displayPt, bytes: tick.bytes };
  writeJSON("sequences.json", { version: 1, canvas: CANVAS, heroBox: HERO, sequences });

  // bubbles.json(PLAN §3.8) — 파일은 @4x 지만 px3x·pt·canvasPx 는 bbox 에서(= v1 값 그대로, SPEC v2 §9.3 canvasPx 불변)
  const geom = await bubbleGeometry();
  const bubbles = {};
  for (const id of BUBBLE_ORDER) {
    const rel = `ui/bubble-${id}.webp`;
    if (!fs.existsSync(outAbs(rel))) {
      errors.push(`① 출력 없음: public/assets/${rel}`);
      continue;
    }
    const g = geom.get(id);
    const m = await sharp(outAbs(rel)).metadata();
    expectDims(`${rel}(@4x)`, [m.width, m.height], g.px4x);
    const [w3, h3] = g.px3x;
    bubbles[id] = { asset: `ui/bubble-${id}`, px3x: [w3, h3], pt: [r2(w3 / 3), r2(h3 / 3)], canvasPx: [w3 * CANVAS_PER_PX3X, h3 * CANVAS_PER_PX3X] };
  }
  writeJSON("bubbles.json", { anchorCanvas: ANCHOR_CANVAS, canvasPerPx3x: CANVAS_PER_PX3X, bubbles });

  // grass.json(PLAN §3.8) — date 는 버리고 요일만
  const g = JSON.parse(fs.readFileSync(MAC + "insights/grass_light.json", "utf8"));
  const WEEK = ["일", "월", "화", "수", "목", "금", "토"];
  const side = (src, label) => {
    if (!src?.png || !src?.grid || !Array.isArray(src?.cells)) {
      errors.push(`68행 grass_light.json 의 ${label} 형식이 예상과 다르다`);
      return null;
    }
    const cells = src.cells.map((c) => {
      const weekday = WEEK[new Date(`${c.date}T00:00:00Z`).getUTCDay()];
      if (WEEK[(c.row + 1) % 7] !== weekday) errors.push(`68행 ${label} ${c.date}: row ${c.row} 와 요일 ${weekday} 가 안 맞는다(월=0 가정)`);
      return { col: c.col, row: c.row, future: c.future, level: c.level, weekday, valueText: c.valueText, x: c.x, y: c.y, w: c.w, h: c.h };
    });
    return { png: src.png, grid: src.grid, cells };
  };
  writeJSON("grass.json", { scale: g.scale, work: side(g.work_grass, "work_grass"), token: side(g.token_grass, "token_grass") });
  console.log("build-assets: data 끝");
}

// ─── 검증 ───────────────────────────────────────────────────────────────────────
function expectedOutputs() {
  const list = [];
  const a = (rel) => list.push(`public/assets/${rel}`);
  a("ui/popover-tick-strip.webp");
  for (const [, rel] of [...RENDERS, ...GRASS, ...LABELS]) a(rel);
  a("ui/gomoku-board.webp"); a("ui/gomoku-board-sm.webp"); a("ui/header-off-1702.webp"); a("ui/menubar-icon-dot.webp");
  for (const id of BUBBLE_ORDER) a(`ui/bubble-${id}.webp`);
  for (const [rel] of V2_CROPS) a(rel);
  for (const s of SEQS) {
    a(`char/${s.name}.webm`); a(`char/${s.name}.mov`);
    if (s.low) { a(`char/${s.name}-15.webm`); a(`char/${s.name}-15.mov`); }
    if (s.poster) a(`char/${s.name}-poster.webp`);
  }
  for (const [, rel] of IOS) a(rel);
  for (const [rel] of V31) a(rel);
  for (const rel of ["brand/appstore-badge-ko-black.svg", "brand/qr-appstore.svg", "brand/qr-android-beta.svg", "brand/icon-64.webp", "brand/icon-256.webp"]) a(rel);
  list.push("app/icon.png", "app/apple-icon.png");
  list.push("data/generated/assets.json", "data/generated/sequences.json", "data/generated/bubbles.json", "data/generated/grass.json");
  return list;
}
// SPEC v2 §9.5 — v1 pretendard-800-sub.* 는 검증 목록에서 뺐고 파일도 통합(⑤)이 지웠다.
const FONT_OUTPUTS = [
  "public/fonts/pretendard-500-sub.woff2", "public/fonts/pretendard-500-sub.txt",
  "public/fonts/pretendard-600-sub.woff2", "public/fonts/pretendard-600-sub.txt",
  "public/fonts/pretendard-300-num.woff2", "public/fonts/pretendard-300-num.txt",
  "public/fonts/jbm-400-ascii.woff2", "public/fonts/LICENSE-Pretendard.txt", "public/fonts/LICENSE-JetBrainsMono.txt",
];

function probeVideo(file) {
  const r = spawnSync(FFPROBE, ["-v", "error", "-select_streams", "v:0", "-count_packets", "-show_entries", "stream=codec_name,codec_tag_string,width,height,nb_read_packets:stream_tags=alpha_mode", "-of", "json", file], { env: FF_ENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  if (r.status !== 0) return { error: (r.stderr || r.error?.message || "").trim() };
  return JSON.parse(r.stdout).streams?.[0] ?? { error: "스트림 없음" };
}

function verify() {
  // ① 출력 전부 존재 + > 0 바이트
  for (const rel of expectedOutputs()) {
    const abs = path.join(ROOT, rel);
    if (!fs.existsSync(abs)) errors.push(`① 출력 없음: ${rel}`);
    else if (!(fs.statSync(abs).size > 0)) errors.push(`① 0 바이트: ${rel}`);
  }
  for (const rel of FONT_OUTPUTS) {
    const abs = path.join(ROOT, rel);
    if (!fs.existsSync(abs) || !(fs.statSync(abs).size > 0)) (only.includes("fonts") ? errors : warnings).push(`글꼴 출력 없음/0B: ${rel} (npm run subset)`);
  }
  for (const abs of [...listFiles(OUT), ...listFiles(FONTS_OUT)]) if (!(fs.statSync(abs).size > 0)) errors.push(`① 0 바이트: ${path.relative(ROOT, abs)}`);
  // ② 영상: 출력 패킷 수 = frames, 크기, 코덱 태그, VP9 알파 표시
  if (fs.existsSync(FFPROBE)) {
    for (const s of SEQS) {
      const variants = [[`char/${s.name}`, s.frames]];
      if (s.low) variants.push([`char/${s.name}-15`, Math.ceil(s.frames / 2)]);
      for (const [base, frames] of variants) {
        for (const ext of ["webm", "mov"]) {
          const abs = outAbs(`${base}.${ext}`);
          if (!fs.existsSync(abs)) continue;
          const p = probeVideo(abs);
          if (p.error) { errors.push(`② ffprobe ${base}.${ext}: ${p.error}`); continue; }
          if (Number(p.nb_read_packets) !== frames) errors.push(`② ${base}.${ext}: 출력 프레임 ${p.nb_read_packets} ≠ ${frames}`);
          if (p.width !== s.size[0] || p.height !== s.size[1]) errors.push(`② ${base}.${ext}: ${p.width}×${p.height} ≠ ${s.size.join("×")}`);
          if (ext === "mov" && (p.codec_name !== "hevc" || p.codec_tag_string !== "hvc1")) errors.push(`② ${base}.mov: ${p.codec_name}/${p.codec_tag_string} (hevc/hvc1 이어야)`);
          if (ext === "webm" && (p.codec_name !== "vp9" || p.tags?.alpha_mode !== "1")) errors.push(`② ${base}.webm: ${p.codec_name} alpha_mode=${p.tags?.alpha_mode} (vp9/1 이어야)`);
        }
      }
    }
  } else {
    warnings.push(`ffprobe 없음(${FFPROBE}) — 출력 영상 프레임 수 검사 생략`);
  }
}

function report() {
  const rows = [];
  for (const abs of listFiles(OUT)) rows.push(path.relative(ROOT, abs));
  for (const abs of listFiles(FONTS_OUT)) rows.push(path.relative(ROOT, abs));
  for (const rel of ["app/icon.png", "app/apple-icon.png", "data/generated/assets.json", "data/generated/sequences.json", "data/generated/bubbles.json", "data/generated/grass.json"]) if (fs.existsSync(path.join(ROOT, rel))) rows.push(rel);
  const groupOf = (rel) => {
    if (rel.startsWith("public/assets/char/")) return rel.endsWith(".webm") ? (rel.includes("-15.") ? "char webm 15fps" : "char webm") : rel.endsWith(".mov") ? (rel.includes("-15.") ? "char mov 15fps" : "char mov") : "char poster";
    if (rel.startsWith("public/assets/")) return rel.split("/")[2];
    if (rel.startsWith("public/fonts/")) return /\.woff2$/.test(rel) ? "fonts" : "fonts (txt·license)";
    if (rel.startsWith("app/")) return "app icons";
    return "data";
  };
  const sums = new Map();
  let total = 0;
  console.log("\n      KB  파일");
  for (const rel of rows) {
    const n = fs.statSync(path.join(ROOT, rel)).size;
    total += n;
    const g = groupOf(rel);
    sums.set(g, (sums.get(g) ?? 0) + n);
    console.log(`${(n / 1024).toFixed(1).padStart(8)}  ${rel}`);
  }
  console.log("\n      KB  묶음");
  for (const [g, n] of [...sums].sort()) console.log(`${(n / 1024).toFixed(1).padStart(8)}  ${g}`);
  console.log(`${(total / 1024).toFixed(1).padStart(8)}  합계(${rows.length}개 — mov·15fps·txt·json 포함)`);
  // 크롬 경로 = 렌더·조각·포스터·webm 30fps·아이폰·브랜드·woff2 (사파리 mov·15fps 대체판·아이콘 png·json 제외)
  const chrome = ["ui", "char webm", "char poster", "ios", "brand", "fonts"].reduce((a, g) => a + (sums.get(g) ?? 0), 0);
  console.log(`${(chrome / 1024).toFixed(1).padStart(8)}  크롬 경로 에셋 합계(예산 ${BUDGET / 1e6}MB 중 JS·CSS ≈0.21MB 별도)`);
  if (chrome > BUDGET) warnings.push(`④ 크롬 경로 에셋 합계 ${(chrome / 1e6).toFixed(2)}MB > ${BUDGET / 1e6}MB`);
  else if (chrome + 0.21e6 > BUDGET) warnings.push(`④ 크롬 경로 에셋 ${(chrome / 1e6).toFixed(2)}MB + JS·CSS ≈0.21MB 가 ${BUDGET / 1e6}MB 를 넘을 수 있다`);
  if (encoded.length) {
    console.log("\n  ② 입력 프레임 수 = 메타 frames");
    for (const e of encoded) console.log(`     ${e.label.padEnd(24)} ${String(e.inputFrames).padStart(4)} / ${e.frames} ${e.inputFrames === e.frames ? "OK" : "✗"}`);
  }
}

// ─── 실행 ───────────────────────────────────────────────────────────────────────
async function main() {
  const t0 = Date.now();
  if (only.includes("char")) {
    if (!fs.existsSync(FF)) fail(`ffmpeg 없음: ${FF} (env FFMPEG)`);
    const v = spawnSync(FF, ["-hide_banner", "-encoders"], { env: FF_ENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    if (v.status !== 0 || !/libvpx-vp9/.test(v.stdout) || !/hevc_videotoolbox/.test(v.stdout)) fail(`ffmpeg 에 libvpx-vp9·hevc_videotoolbox 가 없다: ${FF}`);
  }
  console.log(`build-assets: 묶음 = ${only.join(",")}${seqArg ? ` · 시퀀스 = ${seqArg.join(",")}` : ""} · ffmpeg 동시 ${FF_JOBS} · VP9 cpu-used ${CPU_USED}`);
  // char 는 오래 걸리니 먼저 띄우고, 그동안 sharp 묶음을 돈다.
  const charJob = only.includes("char") ? buildChar() : Promise.resolve();
  if (only.includes("ui")) await buildUI();
  if (only.includes("ios")) await buildIOS();
  if (only.includes("v31")) await buildV31();
  if (only.includes("brand")) await buildBrand();
  if (only.includes("fonts")) buildFonts();
  await charJob;
  await buildData(); // 늘(해시가 파일과 맞게)
  verify();
  report();
  console.log(`\nbuild-assets: ${((Date.now() - t0) / 1000).toFixed(1)}s`);
  for (const w of new Set(warnings)) console.warn(`경고: ${w}`);
  const errs = [...new Set(errors)];
  if (errs.length) {
    console.error(`\nbuild-assets: 검증 실패 ${errs.length}건`);
    for (const e of errs) console.error(`  ✗ ${e}`);
    return 1;
  }
  console.log("build-assets: 검증 OK — ① 출력 > 0B ② 입력·출력 프레임 = frames ③ webp 픽셀 = 표" + (warnings.some((w) => w.startsWith("④")) ? "" : " ④ 예산 안"));
  return 0;
}

main()
  .then((code) => { cleanup(); process.exit(code); })
  .catch((e) => { console.error(e?.stack ?? e); cleanup(); process.exit(1); });

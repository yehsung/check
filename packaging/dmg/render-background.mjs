#!/usr/bin/env node
// DMG 창 배경을 다시 굽는다: background.html → background.png(640x420) + background@2x.png(1280x840).
//
// 사용법: node packaging/dmg/render-background.mjs
//
// - Playwright(chromium)는 이 저장소에 없다. PLAYWRIGHT_BASE(그 아래 node_modules/playwright 가 있는 폴더),
//   이 폴더, ~/Aingo 순서로 찾는다.
// - 글꼴은 Pretendard 를 PRETENDARD_DIR(기본 ~/aing-check-promo/public/fonts)에서 읽어 data: URL 로 심는다
//   (file:// 페이지에서 file:// 글꼴은 Chromium 이 CORS 로 막는다). 없으면 시스템의 Apple SD Gothic Neo 로 굽고 경고한다.
// - 두 장은 dmgbuild 가 tiffutil -cathidpicheck 로 한 장의 HiDPI TIFF 로 묶는다 — 2x 는 정확히 두 배여야 한다.
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const WIDTH = 640;   // settings.py BACKGROUND_W
const HEIGHT = 420;  // settings.py BACKGROUND_H

function loadPlaywright() {
  const require = createRequire(import.meta.url);
  const bases = [process.env.PLAYWRIGHT_BASE, here, path.join(os.homedir(), 'Aingo')].filter(Boolean);
  for (const base of bases) {
    try {
      return require(require.resolve('playwright', { paths: [base] }));
    } catch {
      // 다음 후보
    }
  }
  throw new Error(`playwright 를 찾지 못했습니다(찾은 곳: ${bases.join(', ')}). PLAYWRIGHT_BASE 로 node_modules 가 있는 폴더를 지정하세요.`);
}

function fontFaceCSS() {
  const dir = process.env.PRETENDARD_DIR || path.join(os.homedir(), 'aing-check-promo/public/fonts');
  const faces = [
    ['Pretendard-SemiBold.woff2', 600],
    ['Pretendard-Bold.woff2', 700],
  ];
  let css = '';
  for (const [file, weight] of faces) {
    const p = path.join(dir, file);
    if (!fs.existsSync(p)) return null;
    const b64 = fs.readFileSync(p).toString('base64');
    css += `@font-face{font-family:"Pretendard";font-weight:${weight};src:url(data:font/woff2;base64,${b64}) format("woff2");}\n`;
  }
  return css;
}

const { chromium } = loadPlaywright();
const fontCSS = fontFaceCSS();
if (!fontCSS) console.error('경고: Pretendard 를 찾지 못해 시스템 글꼴(Apple SD Gothic Neo)로 굽습니다. PRETENDARD_DIR 로 지정할 수 있습니다.');

const browser = await chromium.launch();
try {
  for (const [scale, name] of [[1, 'background.png'], [2, 'background@2x.png']]) {
    const context = await browser.newContext({ viewport: { width: WIDTH, height: HEIGHT }, deviceScaleFactor: scale });
    const page = await context.newPage();
    await page.goto(pathToFileURL(path.join(here, 'background.html')).href);
    if (fontCSS) await page.addStyleTag({ content: fontCSS });
    await page.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all([...document.images].map((img) => (img.complete ? null : new Promise((r) => { img.onload = img.onerror = r; }))));
    });
    const state = await page.evaluate(() => ({
      // check() 는 등록 안 된 글꼴에도 true 를 낸다 — 실제로 내려앉은 face 가 있는지 본다.
      pretendard: [...document.fonts].some((f) => f.family.replace(/"/g, '') === 'Pretendard' && f.status === 'loaded'),
      imagesOK: [...document.images].every((img) => img.naturalWidth > 0),
    }));
    if (!state.imagesOK) throw new Error('캐릭터 그림을 불러오지 못했습니다(background.html 의 img 경로 확인).');
    const out = path.join(here, name);
    await page.screenshot({ path: out, clip: { x: 0, y: 0, width: WIDTH, height: HEIGHT } });
    await context.close();
    console.error(`${name}: ${WIDTH * scale}x${HEIGHT * scale} (Pretendard ${state.pretendard ? '적용' : '미적용'})`);
  }
} finally {
  await browser.close();
}

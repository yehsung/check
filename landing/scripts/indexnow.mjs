#!/usr/bin/env node
/**
 * IndexNow 제출(docs/v3/seo.md) — 배포가 끝난 뒤 사람이 손으로 돌린다. 빌드(prebuild·build)에는 걸지 않는다.
 *
 *   npm run indexnow               # 라이브 sitemap 의 URL 을 IndexNow(Bing·Yandex 등 공유) + 네이버 서치어드바이저에 보낸다
 *   npm run indexnow -- --dry-run  # 보낼 JSON 만 찍는다(엔드포인트를 부르지 않는다)
 *   SITE_URL=https://… npm run indexnow -- --dry-run
 *
 * 키: lib/seo.ts 의 INDEXNOW_KEY(정본) = public/<키>.txt 의 내용. 둘이 다르면 멈춘다.
 * 실제 제출 전에는 라이브 keyLocation 이 200 + 키 글자를 돌려주는지 먼저 본다(배포 전이면 멈춘다).
 * 출력: 엔드포인트마다 HTTP 상태(200·202 = 받음). 하나라도 실패면 exit 1.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SITE = (process.env.SITE_URL || "https://aing-check.vercel.app").replace(/\/+$/, "");
const DRY = process.argv.includes("--dry-run");
const ENDPOINTS = ["https://api.indexnow.org/indexnow", "https://searchadvisor.naver.com/indexnow"];

function fail(msg) {
  console.error(`indexnow: ${msg}`);
  process.exit(1);
}

function readKey() {
  const src = fs.readFileSync(path.join(ROOT, "lib/seo.ts"), "utf8");
  const m = /export const INDEXNOW_KEY = "([0-9a-f]{32})"/.exec(src);
  if (!m) fail("lib/seo.ts 에서 INDEXNOW_KEY(32자 16진)를 못 찾았다");
  const key = m[1];
  const file = path.join(ROOT, "public", `${key}.txt`);
  if (!fs.existsSync(file)) fail(`public/${key}.txt 가 없다`);
  if (fs.readFileSync(file, "utf8").trim() !== key) fail(`public/${key}.txt 내용이 키와 다르다`);
  return key;
}

async function sitemapUrls() {
  const url = `${SITE}/sitemap.xml`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
  if (!res.ok) fail(`${url} → HTTP ${res.status}`);
  const xml = await res.text();
  const host = new URL(SITE).host;
  const urls = [...xml.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/g)].map((m) => m[1].replace(/&amp;/g, "&"));
  const own = urls.filter((u) => {
    try {
      return new URL(u).host === host;
    } catch {
      return false;
    }
  });
  if (own.length === 0) fail(`${url} 에 ${host} 주소가 없다`);
  return own;
}

async function keyIsLive(keyLocation, key) {
  try {
    const res = await fetch(keyLocation, { signal: AbortSignal.timeout(10_000) });
    return res.ok && (await res.text()).trim() === key;
  } catch {
    return false;
  }
}

const key = readKey();
const urlList = await sitemapUrls();
const payload = { host: new URL(SITE).host, key, keyLocation: `${SITE}/${key}.txt`, urlList };

if (DRY) {
  console.log("indexnow: --dry-run(보내지 않음)");
  console.log(`endpoints: ${ENDPOINTS.join(" , ")}`);
  console.log(JSON.stringify(payload, null, 2));
  process.exit(0);
}

if (!(await keyIsLive(payload.keyLocation, key))) fail(`${payload.keyLocation} 가 키를 돌려주지 않는다 — 배포 뒤에 다시 돌려라`);

let ok = true;
for (const endpoint of ENDPOINTS) {
  try {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(15_000),
    });
    const good = res.status === 200 || res.status === 202;
    if (!good) ok = false;
    console.log(`${endpoint} → HTTP ${res.status}${good ? "" : ` ${(await res.text()).slice(0, 200)}`}`);
  } catch (e) {
    ok = false;
    console.log(`${endpoint} → 실패 ${e instanceof Error ? e.message : String(e)}`);
  }
}
process.exit(ok ? 0 : 1);

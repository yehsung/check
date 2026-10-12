"use client";

import { useEffect } from "react";

// FAQ 딥링크(SPEC v2 §S7): location.hash 가 #faq-{n} 이면(로드·hashchange) 그 문항을 열고 그 자리로 스크롤한다.
// - 한 번에 하나: 네이티브 <details name="faq"> 가 닫아 준다. name 을 모르는 브라우저를 위해 같은 일을 손으로도 한다.
// - 1번(처음부터 열림)이 닫히며 위 높이가 줄어드므로, 열고 닫는 동안만 높이 전이를 끄고 위치를 확정한 뒤 스크롤한다.
// - 감속 모션이면 스크롤도 즉시. 아무것도 그리지 않는다.

const GROUP = 'details[name="faq"]';
const HASH = /^#faq-(\d{1,2})$/;

function closeOthers(keep: HTMLDetailsElement) {
  for (const d of document.querySelectorAll<HTMLDetailsElement>(`${GROUP}[open]`)) {
    if (d !== keep) d.open = false;
  }
}

function openFromHash(smooth: boolean) {
  const m = HASH.exec(window.location.hash);
  if (!m) return;
  const el = document.getElementById(`faq-${m[1]}`);
  if (!(el instanceof HTMLDetailsElement) || el.getAttribute("name") !== "faq") return;

  // ::details-content 높이 전이(지원 브라우저)를 이 순간만 끈다 — 전이 중에 재면 자리가 어긋난다.
  const freeze = document.createElement("style");
  freeze.textContent = `${GROUP}::details-content{transition:none!important}`;
  document.head.appendChild(freeze);

  el.open = true;
  closeOthers(el);
  void el.offsetHeight; // 열림·닫힘을 전이 없이 확정

  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  // html 의 scroll-padding-top(내비 + 24)을 scrollIntoView 가 따른다.
  el.scrollIntoView({ block: "start", behavior: smooth && !reduce ? "smooth" : "instant" });

  requestAnimationFrame(() => requestAnimationFrame(() => freeze.remove()));
}

export function FaqHash() {
  useEffect(() => {
    openFromHash(false);
    const onHash = () => openFromHash(true);
    // toggle 은 버블링하지 않으므로 캡처 단계에서 듣는다(name 미지원 브라우저의 '하나만 열림' 보험).
    const onToggle = (e: Event) => {
      const d = e.target;
      if (d instanceof HTMLDetailsElement && d.open && d.getAttribute("name") === "faq") closeOthers(d);
    };
    window.addEventListener("hashchange", onHash);
    document.addEventListener("toggle", onToggle, true);
    return () => {
      window.removeEventListener("hashchange", onHash);
      document.removeEventListener("toggle", onToggle, true);
    };
  }, []);
  return null;
}

export default FaqHash;

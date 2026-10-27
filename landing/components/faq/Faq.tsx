import type { CSSProperties } from "react";
import { Glass } from "@/components/glass/Glass";
import { LocalLight } from "@/components/glass/LocalLight";
import { FaqHash } from "@/components/site/FaqHash";
import { Headline } from "@/components/ui/Headline";
import { KeepDots } from "@/components/ui/KeepDots";
import { FAQ_ITEMS, faqId, faqJsonLd } from "@/data/faq-items";
import { FAQ_TITLE } from "./copy";
import { jsonLdHtml } from "./jsonld";

// components/faq/Faq.tsx — FAQ 절 #faq(docs/v3/brief.md §4.6 · §8, 서버 컴포넌트 — 움직이는 건 FaqHash 뿐).
// - 가운데 한 열(최대 880): H2 「자주 묻는 질문」 → regular 유리 판 하나 안에 5문항. 판 뒤에 국소 빛 셋(보라 넓게 · 인디고 왼쪽 아래 · 오키드 오른쪽 위).
//   굴절은 켜지 않는다(굴절 판은 내비·히어로·세그먼트 셋까지 — glass-api §7). 포인터 스페큘러만.
//   글 많은 판이라 tint(짙은 바닥색)로 대비 보험 — 판 뒤 빛이 가장 밝은 자리에서도 답 글(ink-2) ≥ 4.5:1.
// - 문항 = <details name="faq" id="faq-{n}"> + <summary>(JS 없이 열고 닫힘 · 키보드 Enter/Space). 1번만 처음부터 열림.
//   한 번에 하나는 네이티브 name 그룹(+ FaqHash 의 보험). #faq-1…#faq-5 딥링크는 FaqHash 가 열고 그 자리로 스크롤.
// - 행 사이 1px 선은 둘째 행부터 행 윗변에 배경 한 줄(좌우는 글 여백만큼 들임) — summary 의 둥근 포커스 링이 판 안에 머문다.
// - 열린 행은 summary 아래 여백을 줄이고 답에 위 여백(8)을 준다 — 포커스 링(오프셋 3 + 2px)이 답 첫 줄에 걸치지 않는다.
// - 펼침 아이콘: 둥근 칩 안 아래 꺾쇠, 열리면 180° 회전 + 보라 칩(200ms — 감속 모션이면 즉시). 장식이라 aria-hidden.
//   높이 전이는 globals 의 details[name="faq"]::details-content(interpolate-size 지원 · 감속 아님일 때만).
// - FAQPage JSON-LD 하나(화면과 같은 문장 — data/faq-items.ts).

/** 행 사이 선 색. 판 안 좌우 글 여백 --faq-px(= 선의 들임)는 폭마다 달라 클래스로 둔다(인라인이면 미디어 쿼리를 이긴다). */
const PANEL_VARS = { "--faq-line": "rgb(255 255 255 / .09)" } as CSSProperties;

const ROW =
  "group/faq not-first:[background:linear-gradient(var(--faq-line),var(--faq-line))_center_top/calc(100%_-_var(--faq-px)_*_2)_1px_no-repeat]";

const SUMMARY =
  "group/q flex cursor-pointer list-none items-center justify-between gap-5 rounded-2xl px-[var(--faq-px)] py-5 " +
  "tab:py-6 desk:py-6 group-open/faq:pb-3 [&::-webkit-details-marker]:hidden";

const ICON =
  "grid size-8 shrink-0 place-items-center rounded-full bg-white/[.06] text-ink-2 " +
  "shadow-[inset_0_1px_0_rgb(255_255_255/.16),inset_0_0_0_1px_rgb(255_255_255/.07)] " +
  "transition-[rotate,background-color,color] duration-200 ease-[var(--ease-out)] motion-reduce:transition-none " +
  "group-hover/q:bg-white/[.12] group-hover/q:text-ink-1 " +
  "group-open/faq:rotate-180 group-open/faq:bg-[rgb(var(--violet-rgb)/.34)] group-open/faq:text-ink-1";

export function Faq() {
  return (
    <section
      id="faq"
      aria-labelledby="faq-h2"
      className="relative isolate overflow-clip px-5 pb-14 pt-12 tab:px-8 tab:pb-16 tab:pt-16 desk:px-8 desk:pb-20 desk:pt-28"
    >
      {/* 아랫변(아웃트로 윗변)에서 잘리지 않게: 중심 ≤ 100% − 반높이(size × .28) − 12px */}
      <LocalLight tone="violet" x="50%" y="min(56%, calc(100% - min(364px, 42vw) - 12px))" size="min(1300px, 150vw)" aspect={0.56} strength={0.32} />
      <LocalLight tone="indigo" x="14%" y="68%" size="min(760px, 110vw)" aspect={0.6} strength={0.24} />
      <LocalLight tone="orchid" x="86%" y="max(30%, calc(min(238px, 31.5vw) + 12px))" size="min(680px, 90vw)" strength={0.2} />

      <div className="mx-auto max-w-[880px]">
        <Headline level={2} size="h2" lines={FAQ_TITLE} id="faq-h2" className="text-center" />
        <Glass
          level="regular"
          tint
          specular
          style={PANEL_VARS}
          className="mt-9 p-2 [--faq-px:16px] tab:mt-12 tab:[--faq-px:22px] desk:mt-14 desk:[--faq-px:24px]"
        >
          {FAQ_ITEMS.map((item, i) => (
            <details key={item.q} name="faq" id={faqId(i + 1)} open={i === 0} className={ROW}>
              <summary className={SUMMARY}>
                <span className="t-faq-q text-ink-1">{item.q}</span>
                <span aria-hidden="true" className={ICON}>
                  <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                    <path
                      d="M3.25 5.25 7 9l3.75-3.75"
                      stroke="currentColor"
                      strokeWidth="1.7"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    />
                  </svg>
                </span>
              </summary>
              <p className="t-body max-w-[40em] px-[var(--faq-px)] pb-6 pt-2 text-ink-2">
                <KeepDots text={item.a} />
              </p>
            </details>
          ))}
        </Glass>
      </div>
      <FaqHash />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdHtml(faqJsonLd()) }} />
    </section>
  );
}

export default Faq;

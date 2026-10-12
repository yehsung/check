import { FaqHash } from "@/components/site/FaqHash";
import { Headline } from "@/components/ui/Headline";
import { FAQ_ITEMS, faqId, faqJsonLd } from "@/data/faq-items";
import { FAQ_TITLE } from "./copy";
import { jsonLdHtml } from "./jsonld";

// components/faq/Faq.tsx — FAQ 절(SPEC v2 §S7, 서버 컴포넌트). 왼쪽 정렬 한 열: 제목 x = --gutter(1440 → 176), 그 아래 목록(최대 폭 760).
// 숫자 격자(왼쪽 제목 + 오른쪽 칸)·설치·아웃트로(가운데)와 다른 구도(J2-A8). sticky 제목·면 칠하기·+/× 아이콘 없음.
// - <details name="faq" id="faq-{n}"> 5개(brief-v21 §2 — CB §7 의 1–5번), 1번만 처음부터 open. 한 번에 하나는 네이티브 name 그룹(+ FaqHash 의 보험).
// - 빛(brief-v21 §5): 절 위쪽에 설치 오로라의 꼬리(.aurora-tail, α .08 — 늘 켜짐, 글 뒤 z -1) + 열린 행 빛 헤어라인 + 스파인 연장.
// - 행 사이 --line, 행 위아래 패딩 20, 질문 t-faq-q(600) ink-1, 답 t-body ink-2 최대 40em.
// - 열린 행 위 1px 빛 헤어라인 = globals 의 .faq-open-line(summary 를 기준으로 top:-1px → 행 윗선 위에 겹친다). 닫힌 행에서는 display:none.
// - 디스클로저 ▸ = globals 의 summary.disclosure::after(10px ink-3, 열리면 90° 180ms — 감속에서는 0). 의사 요소라 접근 트리에 없다.
// - 높이 전이는 ::details-content + interpolate-size 를 아는 브라우저 · 감속 아님일 때만(나머지는 즉시 열고 닫음).
//   규칙은 globals(details[name="faq"]::details-content — 통합이 requests/faq-outro.md §1 을 흡수). FaqHash 가 딥링크 순간에만 이 전이를 끈다.
// - FAQPage JSON-LD 하나(화면과 같은 문장 — data/faq-items.ts). SoftwareApplication 은 넣지 않는다(SPEC §8).

export function Faq() {
  return (
    <section id="faq" aria-labelledby="faq-h2" className="relative px-[var(--gutter)] phone:py-18 tab:py-20 desk:py-24">
      {/* 설치 오로라의 꼬리(brief-v21 §5) */}
      <div aria-hidden="true" className="aurora-tail" />
      {/* 10% 스파인의 연장(DECISIONS D27-2(c) — 구조물, desk 만) */}
      <div aria-hidden="true" className="spine-ext hidden desk:block" />
      <Headline level={2} size="h2" lines={FAQ_TITLE} id="faq-h2" />
      <div className="mt-10 max-w-[760px] phone:mt-8">
        {FAQ_ITEMS.map((item, i) => (
          <details
            key={item.q}
            name="faq"
            id={faqId(i + 1)}
            open={i === 0}
            className="group border-t border-line last:border-b"
          >
            <summary className="disclosure t-faq-q relative flex items-center justify-between gap-6 py-5 text-ink-1">
              <span aria-hidden="true" className="faq-open-line hidden group-open:block" />
              <span>{item.q}</span>
            </summary>
            <p className="t-body max-w-[40em] pb-5 text-ink-2">{item.a}</p>
          </details>
        ))}
      </div>
      <FaqHash />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdHtml(faqJsonLd()) }} />
    </section>
  );
}

export default Faq;

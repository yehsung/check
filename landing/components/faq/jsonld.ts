// components/faq/jsonld.ts — JSON-LD 를 <script type="application/ld+json"> 본문 문자열로(순수, import 0).
// Next 의 JSON-LD 안내(node_modules/next/dist/docs/01-app/02-guides/json-ld.md) 그대로: JSON.stringify 는 '<' 를 걸러 주지 않으므로
// '<' 로 바꿔 </script> 조기 종료를 막는다. JSON.parse 하면 원래 값과 같다(faq.test.ts).

export function jsonLdHtml(data: unknown): string {
  return JSON.stringify(data).replace(/</g, "\\u003c");
}

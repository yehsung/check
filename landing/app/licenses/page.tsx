import { readFile } from "node:fs/promises";
import path from "node:path";
import type { Metadata } from "next";
import { OG_IMAGE, SITE_NAME } from "@/lib/site";
import { Headline } from "@/components/ui/Headline";
import { LicensesNav } from "@/components/site/LicensesNav";
import { SiteFooter } from "@/components/site/SiteFooter";

// /licenses — 글꼴 라이선스(SPEC v2 §S9 · §1.5). Pretendard·JetBrains Mono 의 SIL OFL 1.1 전문을 public/fonts/LICENSE-*.txt 에서
// 빌드 때 읽어 그대로 보인다(요청 시점 API 를 쓰지 않으므로 정적 페이지로 프리렌더된다). 첫 페이지와 같은 띠 내비 + 같은 푸터.
// 글꼴·토큰은 v2(SPEC §2.3–§2.5): 제목 t-h2 · 글꼴 이름 t-h3(Pretendard 600) · 본문 t-small 시스템 글꼴 ink-2 ·
// 좌우 --gutter · 세로 패딩 120 / 96 / 72. 모노는 첫 페이지의 brew 명령 한 줄에만 쓴다.
// 원문 줄바꿈(70자 고정 폭)을 그대로 두면 좁은 폭에서 자동 줄바꿈과 겹쳐 들쭉날쭉해진다 → 빈 줄로 문단을 나눠 <p> 로,
// 문단 안 줄바꿈은 공백으로 잇는다(글자는 그대로). '-----' 줄은 <hr>, 대문자 머리(PREAMBLE 등)는 작은 굵은 제목.

const TITLE = "아잉체크: 글꼴 라이선스";
const DESCRIPTION = "Pretendard와 JetBrains Mono의 SIL Open Font License 1.1 전문이에요.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: "/licenses" },
  // openGraph·twitter 는 얕게 덮어써지므로(Next 메타 병합 규칙) 그림·사이트 이름까지 함께 준다
  openGraph: { title: TITLE, description: DESCRIPTION, url: "/licenses", siteName: SITE_NAME, type: "website", locale: "ko_KR", images: [OG_IMAGE] },
  twitter: { card: "summary_large_image", title: TITLE, description: DESCRIPTION, images: [OG_IMAGE] },
};

type Block = { kind: "hr" } | { kind: "head"; text: string } | { kind: "title"; text: string } | { kind: "p"; text: string };

const RULE = /^-{10,}$/;
const HEAD = /^[A-Z][A-Z &]+$/;

/** 라이선스 원문 → 문단 블록. 빈 줄이 문단 경계, 문단 안 줄바꿈은 공백. */
function toBlocks(text: string): Block[] {
  const out: Block[] = [];
  for (const chunk of text.split(/\n\s*\n/)) {
    const lines = chunk.split("\n").map((l) => l.trim()).filter(Boolean);
    let para: string[] = [];
    const flush = () => {
      if (para.length) out.push({ kind: "p", text: para.join(" ") });
      para = [];
    };
    const ruled = lines.some((l) => RULE.test(l));
    lines.forEach((line, i) => {
      if (RULE.test(line)) {
        flush();
        out.push({ kind: "hr" });
      } else if (ruled) {
        out.push({ kind: "title", text: line }); // 두 줄 사이의 'SIL OPEN FONT LICENSE Version 1.1 …'
      } else if (i === 0 && lines.length > 1 && HEAD.test(line)) {
        out.push({ kind: "head", text: line });
      } else {
        para.push(line);
      }
    });
    flush();
  }
  return out;
}

const FONTS = [
  { id: "pretendard", name: "Pretendard", file: "LICENSE-Pretendard.txt" },
  { id: "jetbrains-mono", name: "JetBrains Mono", file: "LICENSE-JetBrainsMono.txt" },
] as const;

async function readLicense(file: string): Promise<string> {
  const text = await readFile(path.join(process.cwd(), "public", "fonts", file), "utf8");
  return text.replace(/\r\n?/g, "\n").trimEnd();
}

export default async function LicensesPage() {
  const texts = await Promise.all(FONTS.map((f) => readLicense(f.file)));
  return (
    <>
      <LicensesNav />
      <main id="main">
        <div className="px-[var(--gutter)] phone:py-18 tab:py-24 desk:py-30">
          <Headline level={1} size="h2" lines={["글꼴 라이선스"]} />
          {FONTS.map((f, i) => (
            <section key={f.id} id={f.id} aria-labelledby={`${f.id}-title`} className="mt-14 first-of-type:mt-10">
              <h2 id={`${f.id}-title`} className="t-h3 text-ink-1">
                {f.name}
              </h2>
              <div className="t-small mt-4 max-w-[44em] text-ink-2 [overflow-wrap:anywhere]">
                {toBlocks(texts[i]).map((b, j) =>
                  b.kind === "hr" ? (
                    <hr key={j} className="my-4 border-line" />
                  ) : b.kind === "title" ? (
                    <p key={j} className="font-semibold text-ink-1">
                      {b.text}
                    </p>
                  ) : b.kind === "head" ? (
                    <h3 key={j} className="t-small mt-6 font-semibold text-ink-1">
                      {b.text}
                    </h3>
                  ) : (
                    <p key={j} className="mt-3 first:mt-0">
                      {b.text}
                    </p>
                  ),
                )}
              </div>
            </section>
          ))}
        </div>
      </main>
      <SiteFooter current="licenses" />
    </>
  );
}

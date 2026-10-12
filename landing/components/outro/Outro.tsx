import { AppStoreBadge } from "@/components/ui/AppStoreBadge";
import { CopyButton } from "@/components/ui/CopyButton";
import { Dome } from "@/components/ui/Dome";
import { DownloadCTA } from "@/components/ui/DownloadCTA";
import { Headline } from "@/components/ui/Headline";
import { BREW } from "@/data/fixtures";
import { OutroStage } from "./OutroStage";
import { OUTRO } from "./copy";

// components/outro/Outro.tsx — 아웃트로(SPEC v2 §S8 · DECISIONS D3, 서버 컴포넌트). 레퍼런스 엔드카드 자리: 처음의 돔이 작게 돌아오고
// (앱 아이콘 구성 = 링 + 아잉) 마지막 다운로드를 건넨다. 움직이는 부분(45% 진입 페이드 · 아잉 idle 2회)은 OutroStage(client).
// - 바탕: 위 160px 동안 --bg-0 → --bg-outro 그라디언트, 그 아래 --bg-outro(푸터와 이어짐). 새 색 없음.
// - 작은 돔 = globals .dome--small(d = min(60vw, 92svh, 860) · 꼭대기 14svh, phone 200vw · 10svh) — 구조물이라 늘 켜짐(GlowGate 대상 아님).
//   돔·웅덩이는 절 밖으로 넘치므로 이 절이 position:relative + overflow:clip(가로 넘침 0). #moments 의 조상이 아니라 sticky 규칙과 무관.
// - 아잉 폭: --aing-w 를 이 절 안에서만 다시 정한다(desk·tab clamp(184px, 24svh − 16px, 220px) · phone clamp(170px, 24svh, 220px)) —
//   AingClip 폭과 globals .dome-pool(폭 × 1.6 · 높이 × .24)이 같은 값을 읽는다. 웅덩이 가운데 = 아잉 상자 아랫변(절 아래 − 16).
// - 버튼 줄: Mac용 다운로드(iOS 에서는 그리지 않음 → 배지가 맨 앞, DECISIONS D9) · App Store 배지 48 · brew 명령 복사(secondary).
//   배지는 사방 여백 = 높이/4(애플 규칙)가 <a> 패딩이라 줄 간격 12 = 눈에 보이는 간격 24. phone 은 세로 쌓기(폭 100%, ≤ 320).
//   1440×900 세로: 돔 꼭대기 126 · H2 196–339 · 리드 359–391 · 버튼 줄 419–467 · 아잉 200×242(아래 여백 16) → 절 ≈ 725(min 80svh = 720).
// - 말풍선·근무 라벨·꾸벅·'근무 종료' 버튼·다른 캐릭터·장식 없음. 아잉·돔·웅덩이는 aria-hidden.

const SECTION =
  "relative flex min-h-[80svh] flex-col overflow-clip " +
  "bg-[linear-gradient(var(--bg-0),var(--bg-outro)_160px)] " +
  "[--aing-w:clamp(184px,calc(24svh_-_16px),220px)] phone:[--aing-w:clamp(170px,24svh,220px)]";

/** 웅덩이 가운데를 아잉 발(상자 아랫변 = 절 아래 − 16)에 둔다: bottom = 16 − 웅덩이 높이(--aing-w × .24)/2. */
const POOL_BOTTOM = "calc(16px - var(--aing-w) * .12)";

const FULL_ON_PHONE = "phone:w-full phone:max-w-[320px]";

export function Outro() {
  return (
    <section id="outro" aria-labelledby="outro-h2" className={SECTION}>
      {/* 10% 스파인의 끝(DECISIONS D27-2(c)): 바탕이 검게 가라앉는 위 160px 동안 사라진다 — desk 만 */}
      <div aria-hidden="true" className="spine-ext spine-ext--end hidden desk:block" />
      <Dome variant="small" pool={{ bottom: POOL_BOTTOM }} />
      <OutroStage>
        <Headline level={2} size="closing" lines={OUTRO.title} id="outro-h2" />
        <p className="t-lead mx-auto mt-5 text-ink-2">{OUTRO.lead}</p>
        <div className="mt-7 flex flex-wrap items-center justify-center gap-3 phone:w-full phone:flex-col phone:gap-2">
          <DownloadCTA placement="outro" size="l" tone="fill" className={FULL_ON_PHONE} />
          {/* 가로 줄에서는 배지 위아래 여백(12 = 높이/4)을 줄 높이에서 뺀다 — 여백은 그대로 비어 있고(리드와 28 · 아잉 상자 위 27.7% 는 빈 칸)
              버튼 줄이 48 로 와이어(419–467)와 같아진다. phone 세로 쌓기에서는 여백이 이웃 버튼과의 간격이라 그대로 둔다. */}
          <AppStoreBadge height={48} placement="outro" className="tab:-my-3 desk:-my-3" />
          {/* iOS 에서는 숨긴다 — 아이폰에서 맥 터미널 명령을 복사할 쓸모가 없다(DECISIONS D26-4, D9 의 iOS 규칙과 같은 결) */}
          <CopyButton
            text={BREW.install}
            label={OUTRO.copyLabel}
            ariaLabel={OUTRO.copyLabel}
            variant="secondary"
            className={`${FULL_ON_PHONE} [html[data-platform=ios]_&]:hidden`}
          />
        </div>
      </OutroStage>
    </section>
  );
}

export default Outro;

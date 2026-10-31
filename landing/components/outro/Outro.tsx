import { BrewPill } from "@/components/glass/CommandPill";
import { LocalLight } from "@/components/glass/LocalLight";
import { AppStoreBadge } from "@/components/ui/AppStoreBadge";
import { DownloadCTA } from "@/components/ui/DownloadCTA";
import { Headline } from "@/components/ui/Headline";
import { glassButtonClass } from "@/components/glass/GlassButton";
import { GlassFx } from "@/components/glass/GlassFx";
import { LINKS, type ReleaseInfo } from "@/data/fixtures";
import { ANDROID_COPY } from "@/data/install-copy";
import { OutroStage } from "./OutroStage";
import { OUTRO } from "./copy";

// components/outro/Outro.tsx — 아웃트로 #outro(docs/v3/brief.md §4.6 · §8, 서버 컴포넌트 — 움직이는 건 OutroStage 의 아잉뿐).
// 엔드카드 구도(가운데 한 열): 작은 유리 받침 위 아잉 → H2 두 줄 → 한 줄 → 버튼 줄. 등장 연출 없음(첫 페인트에 글이 다 보인다).
// - 빛: 페이지의 마무리 빛 — 오로라가 가장 진하게 모이는 곳. 절 국소 빛 다섯(보라 가장 넓게 · 오키드 · 인디고 둘 · 로즈 작은 점)
//   + OutroStage 안의 아잉 뒤 오키드 · 받침 아래 보라. 아래쪽 빛은 절 끝 전에 잦아들게 두어 푸터(bg-deep) 경계가 끊겨 보이지 않는다.
//   절 루트는 relative isolate overflow-clip(glass-api §7 — 빛이 옆 절로 번지거나 가로 넘침을 만들지 않게). 빛은 절 안에서 잦아들게 둔다.
// - 버튼 줄은 두 벌을 SSR 하고 폭·플랫폼으로 하나만 보인다(히어로와 같은 규칙 — §9.4.4):
//   ≥768 · iOS 아님(§8 순서): Mac용 다운로드(DownloadCTA — 클릭하면 설치 선택 창 §11) · brew 알약(복사 → 복사했어요) · App Store 배지.
//   폰(< 768) · iOS 기기: App Store 배지가 먼저 · Mac용 다운로드(투명 유리 → 설치 절 — 폰에 DMG 는 쓸모없다) 한 줄.
//   폰 · 안드로이드 기기(<html data-android> — §12): 배지 자리에 안드로이드 베타 받기(보라 유리 주 버튼 48 → #android) — 히어로와 같다.
//   brew 알약은 폰에서 한 줄에 안 들어가 숨긴다(§9.4.3 — 설치 절 터미널이 보여 준다). 배지 사방 여백 = 높이/4(애플 규칙, <a> 패딩) —
//   가로 줄에서는 위아래 여백만 줄 높이에서 뺀다.
// - 아잉 폭 --aing-w 를 이 절에서 정한다: phone 132 · tab 156 · desk clamp(160, 22svh, 208).
//   1440×900: 받침+아잉 ≈ 247 → H2 → 한 줄 → 버튼 줄 → 절 ≈ 680(그 아래 푸터까지 한 화면).

/** 안드로이드 기기(§12): 폰 벌의 Mac용 다운로드는 안드로이드 주 버튼과 함께 늘어나 줄을 채운다(배지의 −12px 짝 ml-3 은 뗀다) */
const ANDROID_GROW = "[html[data-android]_&]:ml-0 [html[data-android]_&]:grow";

const SECTION =
  "relative isolate overflow-clip px-5 pb-16 pt-4 text-center tab:px-8 tab:pb-28 desk:px-8 desk:pb-32 desk:pt-6 " +
  "[--aing-w:132px] tab:[--aing-w:156px] desk:[--aing-w:clamp(160px,22svh,208px)]";

export function Outro({ release }: { release?: ReleaseInfo } = {}) {
  return (
    <section id="outro" aria-labelledby="outro-h2" className={SECTION}>
      {/* 윗변(FAQ 아랫변)에서 잘리지 않게: 중심 ≥ 반높이(size × .22) + 8px. 아래로 넘친 끝은 bg-deep 잦아듦이 덮는다 */}
      <LocalLight tone="violet" x="50%" y="max(50%, calc(min(330px, 37.4vw) + 8px))" size="min(1500px, 170vw)" aspect={0.44} strength={0.42} />
      <LocalLight tone="orchid" x="82%" y="max(40%, calc(min(266px, 35vw) + 8px))" size="min(760px, 100vw)" strength={0.3} />
      <LocalLight tone="indigo" x="14%" y="50%" size="min(980px, 130vw)" aspect={0.6} strength={0.32} />
      <LocalLight tone="indigo" x="90%" y="62%" size="min(700px, 100vw)" aspect={0.6} strength={0.22} />
      <LocalLight tone="rose" x="58%" y="20%" size={300} aspect={0.8} strength={0.16} className="phone:hidden" />
      {/* 아래 끝은 푸터 바탕(bg-deep)으로 잦아든다 — 빛 위(같은 z, 뒤 순서)에 깔려 경계가 끊겨 보이지 않게 */}
      <span aria-hidden="true" className="pointer-events-none absolute inset-x-0 bottom-0 -z-1 h-36 bg-linear-to-b from-transparent to-bg-deep" />

      <OutroStage />

      <Headline level={2} size="h2" lines={OUTRO.title} id="outro-h2" className="mt-7 tab:mt-8 desk:mt-9" />
      <p className="t-lead mx-auto mt-5 max-w-[44em] text-balance">{OUTRO.lead}</p>

      {/* ≥768 · iOS 아님 */}
      <div className="mx-auto mt-8 hidden flex-row flex-wrap items-center justify-center gap-3 tab:flex desk:flex [html[data-platform=ios]_&]:hidden" data-chooser-row="">
        <DownloadCTA
          placement="outro"
          size="l"
          label={OUTRO.cta}
          release={release}
        />
        <BrewPill className="text-left" />
        <AppStoreBadge height={48} placement="outro" className="self-center -my-3" />
      </div>
      {/* 폰 · iOS: 배지 먼저(히어로와 같은 순서) */}
      <div className="mx-auto mt-8 flex flex-wrap items-center justify-center gap-3 tab:hidden desk:hidden [html[data-platform=ios]_&]:flex">
        <AppStoreBadge height={48} placement="outro-phone" className="-m-3 [html[data-android]_&]:hidden" />
        <a
          href={LINKS.android}
          data-cta="outro-android"
          className={glassButtonClass("primary", "l", "hidden grow [--b-h:48px] [--b-px:22px] [html[data-android]_&]:inline-flex")}
        >
          {ANDROID_COPY.phoneCta}
          <GlassFx specular />
        </a>
        <a href={LINKS.install} data-cta="outro-install" className={glassButtonClass("glass", "l", `ml-3 [--b-h:48px] [--b-px:22px] ${ANDROID_GROW}`)}>
          {OUTRO.cta}
          <GlassFx specular />
        </a>
      </div>
    </section>
  );
}

export default Outro;

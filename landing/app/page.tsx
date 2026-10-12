import { preload } from 'react-dom';
import { asset } from '@/data/fixtures';
import { getRelease } from '@/lib/release';
import { SiteNav } from '@/components/site/SiteNav';
import { Hero } from '@/components/hero/Hero';
import { Scenes } from '@/components/features/Scenes';
import { Install } from '@/components/install/Install';
import { Faq } from '@/components/faq/Faq';
import { Outro } from '@/components/outro/Outro';
import { SiteFooter } from '@/components/site/SiteFooter';
import { LiveAnnouncer } from '@/components/ui/LiveAnnouncer';

// v2.1 순서(brief-v21 §1): 히어로 → 핵심 기능 장면 6개(f-timer · f-tokens · f-message · f-rhythm · f-games · f-iphone) → 설치 → FAQ → 아웃트로.
export const revalidate = 3600;
export default async function Page() {
  // 히어로 아잉 포스터(phone LCP — SPEC §5.4): 첫 페이지에서만 높은 우선순위로 미리 받는다(React 가 <head> 로 올린다 — DECISIONS D19-4).
  const poster = asset('char/aing-rest-poster');
  if (poster) preload(poster.src, { as: 'image', fetchPriority: 'high' });
  const release = await getRelease();
  return (<>
    <SiteNav />
    <main id="main">
      <Hero release={release} />
      <Scenes />
      <Install release={release} />
      <Faq />
      <Outro />
    </main>
    <SiteFooter />
    <LiveAnnouncer />
  </>);
}

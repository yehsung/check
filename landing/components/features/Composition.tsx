// components/features/Composition.tsx — 장면 하나의 렌더 구성(훅 없음 — 데이터만 받아 그린다). FeatureStage(client)가 부른다.
// 구성 상자 = 구성 비율(--cw/--ch)로 폭에 맞춰 줄고, 안의 렌더는 % 좌표로 따라간다(폰은 CSS 가 세로 묶음으로 바꾼다).
// 렌더 <img> 는 mount 뒤에만(그 전엔 <noscript> — JS 없음은 처음부터 그림). 상자는 처음부터 제자리라 CLS 0.
// 렌더는 통째 — 크롭·마스크·페이드 없음. 창 모서리는 10px(렌더 바깥 여백에만 닿는다).
import type { CSSProperties, ReactElement } from 'react';
import { asset as assetMeta, type AssetKey } from '@/data/fixtures';
import { PHONE, type CompItem, type Composition as CompositionSpec } from './scenes.data';

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');
const pct = (v: number, of: number) => `${Math.round((v / of) * 100000) / 1000}%`;

function Img({ k, alt, w, h, className }: { k: AssetKey; alt: string; w: number; h: number; className?: string }) {
  const meta = assetMeta(k);
  return (
    // eslint-disable-next-line @next/next/no-img-element -- next/image 를 쓰지 않는다(이미지 최적화 끔 — RenderImage 와 같은 규칙)
    <img
      src={meta?.src}
      alt={alt}
      width={Math.round(w)}
      height={Math.round(h)}
      loading="lazy"
      decoding="async"
      className={cx('fx-img', className)}
    />
  );
}

/** mount 전엔 <noscript> 안에(JS 없음 = 처음부터 그림, JS 있음 = 받지 않는다). */
const lazy = (mount: boolean, el: ReactElement): ReactElement => (mount ? el : <noscript>{el}</noscript>);

function itemStyle(it: CompItem, W: number, H: number): CSSProperties {
  const [x, y, w, h] = it.box;
  return {
    '--l': pct(x, W),
    '--t': pct(y, H),
    '--wp': pct(w, W),
    '--hp': pct(h, H),
    '--pw': `${it.pw}px`,
    '--ar': `${w} / ${h}`,
    order: it.po,
  } as CSSProperties;
}

export function Composition({ comp, mount }: { comp: CompositionSpec; mount: boolean }) {
  const { w: W, h: H } = comp;
  return (
    <div className="fx-comp" style={{ '--cw': W, '--ch': H } as CSSProperties} data-comp="">
      {comp.items.map((it, i) => {
        const [, , w, h] = it.box;
        if (it.kind === 'phone') {
          const screenW = w / (1 + 2 * PHONE.bezel);
          return (
            <div key={i} className="fx-item fx-phone-item" style={itemStyle(it, W, H)} data-item="phone">
              <div className="fx-shell">
                <div className="fx-screen">
                  {lazy(mount, <Img k={it.screen} alt={it.alt} w={screenW} h={screenW * PHONE.ratio} />)}
                  {it.swap && (
                    <div className="fx-swap" data-swap="">
                      {lazy(mount, <Img k={it.swap.screen} alt={it.swap.alt} w={screenW} h={screenW * PHONE.ratio} />)}
                    </div>
                  )}
                  <span aria-hidden="true" className="fx-island" />
                </div>
              </div>
            </div>
          );
        }
        return (
          <div
            key={i}
            className={cx('fx-item', it.frame && 'fx-frame', it.phoneHide && 'fx-phone-hide')}
            style={itemStyle(it, W, H)}
            data-item={it.asset}
            data-pair={it.pair ? '' : undefined}
          >
            {lazy(mount, <Img k={it.asset} alt={it.alt} w={w} h={h} />)}
            {it.swap && (
              <div className="fx-swap" data-swap="">
                {lazy(mount, <Img k={it.swap.asset} alt={it.swap.alt} w={w} h={h} />)}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

export default Composition;

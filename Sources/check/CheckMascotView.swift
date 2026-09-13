import AppKit
import SwiftUI

struct CheckMascotView: View {
    let snapshot: WorkStatusSnapshot
    /// 지금 착용한 캐릭터가 픽셀아트인가. 기본값은 카탈로그에 물어본다 — 호출부(헤더)는 아무것도 안 넘겨도 된다.
    var isPixelArt: Bool = CheckMascotAssets.currentCharacterIsPixelArt()

    var body: some View {
        ZStack {
            // 상태 틴트 글로우 — 이미지 뒤에서 상태감을 은은하게 살린다.
            Circle()
                .fill(tint.opacity(snapshot.isWorking ? 0.30 : 0.18))
                .blur(radius: 8)
                .padding(2)
            mascot
        }
    }

    /// 헤더 초상의 CGImage. NSImage 가 비트맵 rep 하나짜리라 이 변환은 값싼 조회다(캐시는 `CheckMascotAssets`).
    private var cgImage: CGImage? {
        CheckMascotAssets.image(for: snapshot)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    @ViewBuilder
    private var mascot: some View {
        if let cgImage {
            // ★★ **`Image(nsImage:)` 는 `.interpolation(...)` 을 통째로 무시한다**(2026-09-13 실측 —
            //    `.none` 과 `.high` 로 구운 PNG 가 바이트까지 같았다). 그래서 반드시 CGImage 로 내려 그린다.
            //    되돌리면 `isPixelArt` 분기가 남은 채 아무 일도 안 하고 픽셀아트가 조용히 뭉개진다.
            //
            // 여기(46pt@2x = 92px)는 192px 원본의 **2.1배 축소**라 이웃 보간이 블록을 살린다.
            // ⚠️ **메뉴바(18pt@2x = 36px)에는 같은 처방을 쓰지 마라** — 5.3배 축소라 이웃 보간이 픽셀을
            //    너무 많이 버려 얼굴이 뭉개진다(렌더 비교로 확인: scratchpad/pack5/interp-compare.png).
            //    거기는 AppKit 의 부드러운 축소가 맞다.
            Image(decorative: cgImage, scale: 1)
                .resizable()
                .interpolation(isPixelArt ? .none : .high)
                .scaledToFit()
                .padding(1)
        } else {
            // 로드 실패 폴백 — crash 대신 SF Symbol로 상태를 표시한다.
            Image(systemName: MenuBarStatusFormatter.symbolName(for: snapshot))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
        }
    }

    private var tint: Color {
        if snapshot.pendingSync {
            return CheckTheme.pending
        }
        return snapshot.isWorking ? CheckTheme.working : CheckTheme.offWork
    }
}

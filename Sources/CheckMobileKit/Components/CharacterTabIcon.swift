#if os(iOS)
import CheckMobileShared
import SwiftUI
import UIKit

/// 탭 막대 '나' 아이콘 = **착용 캐릭터 초상 + 근무 상태 링**(시안 b2 탭 막대 `.b-pt.b-is-working` — 11개 화면 모두 같다).
///
/// SF 기호 사람 아이콘을 쓰면 브랜드 정체성이 전 화면에서 빠진다(w15 검증 medium 4). 탭 막대는 SwiftUI 뷰가 아니라 `UIImage` 를
/// 받으므로 `CharacterPortrait` 과 **같은 기하**(받침 원 · 그림 88% · 아래로 5% · 링 2pt + 틈 1.5pt)를 UIKit 으로 한 번 그려 캐시한다.
/// `ImageRenderer`(SwiftUI → 이미지)를 쓰지 않는 이유: 그림 한 장·원 두 개뿐이라 UIKit 이 싸고, 렌더러가 접는 자리(메뉴 등)가 없다.
///
/// 색은 `MobileTheme.uiColor`(동적 UIColor)를 **그리는 순간의 라이트/다크로 굳힌다** — 이미지는 모드를 따라가지 못하므로
/// 부르는 쪽이 `colorScheme` 을 키에 넣어 모드가 바뀌면 다시 그린다.
@MainActor
package enum CharacterTabIcon {
    /// 아이콘 한 변(pt). 탭 막대 기호 칸(약 28pt) 안에 링까지 들어가는 크기.
    package static let side: CGFloat = 26
    private static let ringWidth: CGFloat = 2
    private static let ringGap: CGFloat = 1.5

    private static var cache: [String: UIImage] = [:]

    /// 착용 캐릭터·표정·모드·화면 배율이 같으면 같은 이미지를 준다(디코드·렌더 1회).
    /// - Returns: 그림 리소스가 없으면 nil — 부르는 쪽이 SF 기호로 접는다.
    package static func image(id: String?, mood: CharacterMood, isDark: Bool, scale: CGFloat) -> UIImage? {
        let resolved = AingCharacterArt.resolvedID(id)
        let renderScale = max(1, scale)
        let key = "\(resolved)|\(mood.rawValue)|\(isDark ? "d" : "l")|\(renderScale)"
        if let hit = cache[key] { return hit }
        guard let art = AingCharacterArt.portraitImage(id: resolved, expression: mood.expression) else { return nil }
        let traits = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
        let format = UIGraphicsImageRendererFormat()
        format.scale = renderScale
        format.opaque = false
        let square = CGSize(width: side, height: side)
        let drawn = UIGraphicsImageRenderer(size: square, format: format).image { context in
            let inset = ringWidth + ringGap
            let inner = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
            let circle = UIBezierPath(ovalIn: inner)
            backing(mood).resolvedColor(with: traits).setFill()
            circle.fill()
            context.cgContext.saveGState()
            circle.addClip()
            let artSide = inner.width * 0.88
            UIImage(cgImage: art).draw(in: CGRect(
                x: inner.midX - artSide / 2,
                y: inner.midY - artSide / 2 + inner.height * 0.05,
                width: artSide,
                height: artSide
            ))
            context.cgContext.restoreGState()
            if let ring = mood.ring {
                ringColor(ring).resolvedColor(with: traits).setStroke()
                let stroke = UIBezierPath(ovalIn: CGRect(
                    x: ringWidth / 2, y: ringWidth / 2,
                    width: side - ringWidth, height: side - ringWidth
                ))
                stroke.lineWidth = ringWidth
                stroke.stroke()
            }
        }
        // 탭 막대가 제 색으로 칠하지 않게(초상은 원색 그대로).
        let image = drawn.withRenderingMode(.alwaysOriginal)
        cache[key] = image
        return image
    }

    /// 받침 색 — `CharacterPortrait.backing` 과 같은 규칙.
    private static func backing(_ mood: CharacterMood) -> UIColor {
        switch mood {
        case .working: return MobileTheme.uiColor(MobileThemePalette.workingTint)
        case .lost: return MobileTheme.uiColor(MobileThemePalette.pendingTint)
        case .off: return MobileTheme.uiColor(MobileThemePalette.fill)
        case .plain: return MobileTheme.uiColor(MobileThemePalette.surface2)
        }
    }

    /// 링 색 — `CharacterPortrait.ringColor` 와 같은 규칙.
    private static func ringColor(_ status: PresenceStatus) -> UIColor {
        switch status {
        case .working: return MobileTheme.uiColor(MobileThemePalette.workingDot)
        case .pending: return MobileTheme.uiColor(MobileThemePalette.pendingDot)
        case .off: return MobileTheme.uiColor(MobileThemePalette.offWorkDot)
        }
    }
}
#endif

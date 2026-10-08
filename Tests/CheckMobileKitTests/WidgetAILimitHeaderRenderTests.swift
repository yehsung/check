import AppKit
import CheckCore
import CheckMobileShared
import CheckRenderTestSupport
import Foundation
import SwiftUI
import Testing
@testable import CheckWidgetsKit

// MARK: - v0.3.47 P2 — 위젯 머리가 상한 길이 쌍둥이를 **그림으로** 가르는가
//
// ## 고친 결함
// 위젯 미디움 머리는 메인 맥 이름을 **합친 한 글자**(`· 이름 (A1B2)`)로 tail 말줄임해 그렸다. 상한 길이(64 스칼라)
// 이름이 겹친 두 맥이면 말줄임이 **꼬리부터** 먹어 두 위젯 머리가 글자 그대로 같았다. 위젯은 맥 **한 대**만 그리므로
// "이 숫자가 어느 쌍둥이 것인지"를 말할 글자가 꼬리뿐인데 그 글자가 사라졌다. 폰 카드와 같은 수리로 이름과
// 꼬리를 따로 세웠다(`AingWidgetLimitsHeaderLine` — 꼬리는 `fixedSize` + `layoutPriority(1)`).
//
// ## 왜 그림인가
// 말줄임은 높이를 바꾸지 않는다(한 줄 고정) — 값·폭 계산으로는 "두 머리가 같아 보인다"를 못 잰다. 위젯 화면은
// `#if os(iOS)` 라 맥 스위트가 못 굽지만, 머리 줄은 플랫폼 무관 뷰로 뺐으므로 **위젯이 쓰는 바로 그 뷰**를 굽는다.
// 이름·꼬리·나이는 스냅샷 → `AingWidgetLimitsState` → `headerDevice` 길을 그대로 지나 만든다(손으로 짓지 않는다).
//
// ## 비교는 문턱으로 (`CheckRenderDiff` — 맥 고르개 스위트와 같은 헬퍼)
// 같다 = 최대 Δ ≤ 2 · 다르다 = Δ>8 픽셀 40개 이상. 바이트로 견주면 호출 사이 Δ1 디더만으로 "다르다"가 초록이 된다.
//
// ## 기준선은 **다른 입력**이다
// 꼬리 칸을 떼면(옛 파일 — 합친 글자 한 줄) 꼬리가 **다른** 두 쌍둥이(A1B2 · C3D4)가 **같은 그림**이 된다.
// 같은 입력끼리의 "같다"는 영원히 초록이므로 기준선으로 쓰지 않는다. 그리고 그 기준선이 빈 그림이 아님을
// 짧은 이름 쌍둥이로 따로 잰다(짧으면 합친 글자 한 줄로도 꼬리가 남아 **다르게** 보여야 한다).

@MainActor
@Suite("위젯 AI 리밋 — 머리 줄 그림(v0.3.47 P2 · 상한 길이 쌍둥이)")
struct WidgetAILimitHeaderRenderTests {
    /// 고정 기준 시각(2026-09-17 14:05 KST — 다른 위젯 스위트와 같은 세계).
    nonisolated static let now = Date(timeIntervalSince1970: 1_789_621_500)
    /// 서버 CHECK 가 받아 주는 가장 긴 이름(64 스칼라 한글 — 11pt 에서 ≈615pt, 어느 칸에도 안 든다).
    nonisolated static let maxName = String(repeating: "가", count: AILimitDeviceLabelContract.maxScalars)

    /// 칸 안쪽 폭: 가장 좁은 기기(329 − 16×2)와 기준 기기(364 − 16×2).
    static let innerWidths: [CGFloat] = [
        CGFloat(AingWidgetLimitsMediumBudget.narrowSize.width - AingWidgetLimitsMediumBudget.contentMargin * 2),
        CGFloat(AingWidgetLimitsMediumBudget.referenceSize.width - AingWidgetLimitsMediumBudget.contentMargin * 2),
    ]

    /// 스냅샷 → 위젯 모델 → 머리 이름. `tail` nil = 꼬리 칸이 없는 파일(초안 · 옛 앱이 쓴 파일).
    static func limits(base: String, tail: String, sendTail: Bool) throws -> AingWidgetLimits {
        let panel = WidgetSnapshot.AILimitPanel(
            providers: [
                .init(provider: "claude", fiveHourPercent: 27, fiveHourResetsAt: now.addingTimeInterval(9_000),
                      weeklyPercent: 60, weeklyResetsAt: now.addingTimeInterval(450_000),
                      observedAt: now.addingTimeInterval(-12 * 3_600 - 60)),
            ],
            deviceName: AILimitDeviceNameParts(base: base, tail: tail).combined,
            deviceNameTail: sendTail ? tail : nil,
            todayTokens: 12_345_678
        )
        let snapshot = WidgetSnapshot(generatedAt: now.addingTimeInterval(-30), aiLimits: panel)
        guard case .limits(let value) = AingWidgetLimitsState(snapshot: snapshot, at: now) else {
            throw HeaderRenderFailure.notLimits
        }
        return value
    }

    /// 위젯이 그리는 **그 머리 줄**을 칸 안쪽 폭으로 굽는다(2배율 · 흰 바탕).
    static func header(_ limits: AingWidgetLimits, width: CGFloat) throws -> CGImage {
        let view = AingWidgetLimitsHeaderLine(
            title: AingWidgetText.limitsTitle,
            device: limits.headerDevice,
            age: limits.observationAgeText(now: now),
            primary: .black,
            secondary: Color(white: 0.35)
        )
        .frame(width: width, alignment: .leading)
        .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try #require(renderer.cgImage, "위젯 머리 줄을 굽지 못했다")
    }

    static func diff(_ a: CGImage, _ b: CGImage) throws -> CheckRenderDiff {
        try #require(CheckRenderDiff(a, b), "두 그림을 견줄 판을 못 만들었다")
    }

    /// ★★ 상한 길이 쌍둥이 두 장의 위젯 머리가 **눈으로 다르다** — 그리고 꼬리 칸을 떼면 **같아진다**.
    @Test("상한 길이 쌍둥이: 두 위젯 머리가 그림으로 갈린다 · 꼬리 칸을 떼면(합친 글자 한 줄) 같아진다", arguments: [0, 1])
    func twinHeadersLookDifferentOnlyBecauseOfTheTail(widthIndex: Int) throws {
        let width = Self.innerWidths[widthIndex]
        let a = try Self.limits(base: Self.maxName, tail: "A1B2", sendTail: true)
        let b = try Self.limits(base: Self.maxName, tail: "C3D4", sendTail: true)
        // 전제: 이름은 같고, 머리에 적힐 이름이 있다(맥 두 대 갈래).
        let headerA = try #require(a.headerDevice, "전제: 맥 이름이 머리에 적힌다")
        let headerB = try #require(b.headerDevice)
        #expect(headerA.name == headerB.name, "전제: 두 맥의 이름 글자가 같다(다르면 이 그물은 아무것도 재지 못한다)")
        #expect(headerA.tail == "(A1B2)" && headerB.tail == "(C3D4)", "전제: 꼬리가 따로 실렸다")
        // 전제: 그 이름은 이 폭에서 **정말로** 잘린다(안 잘리면 이 그물은 말줄임을 재지 않는다).
        let room = AingWidgetLimitsMediumBudget.family(
            width: Double(width) + AingWidgetLimitsMediumBudget.contentMargin * 2, height: 170,
            providerCount: 1, hasTokens: true
        ).deviceNameWidth
        let nameWidth = (headerA.text as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: AingWidgetLimitsMediumBudget.deviceNameFontSize)]).width
        #expect(Double(nameWidth) > room, "전제: 상한 길이 이름 \(nameWidth)pt 가 이름 자리 \(room)pt 에 다 든다")

        let imageA = try Self.header(a, width: width)
        let imageB = try Self.header(b, width: width)
        let again = try Self.diff(imageA, try Self.header(a, width: width))
        #expect(again.looksSame, "\(width)pt: 같은 머리를 두 번 구웠더니 눈에 보이게 달라졌다(\(again)) — 이 비교를 믿을 수 없다")
        let twins = try Self.diff(imageA, imageB)
        #expect(twins.looksDifferent,
                "\(width)pt: 상한 길이 쌍둥이 두 위젯의 머리가 **눈으로 똑같다**(\(twins)) — 꼬리가 말줄임에 먹혔다")

        // ★ 기준선(다른 입력): 꼬리 칸을 떼면 합친 글자 한 줄로 그려지고, 말줄임이 꼬리를 먹어 두 머리가 같아진다.
        let oldA = try Self.limits(base: Self.maxName, tail: "A1B2", sendTail: false)
        let oldB = try Self.limits(base: Self.maxName, tail: "C3D4", sendTail: false)
        #expect(oldA.headerDevice?.tail == nil && oldA.headerDevice?.text != oldB.headerDevice?.text,
                "전제: 기준선의 두 입력은 **글자가 다르다**(꼬리만 합친 글자 안에 있다)")
        let tailless = try Self.diff(try Self.header(oldA, width: width), try Self.header(oldB, width: width))
        #expect(tailless.looksSame,
                "\(width)pt: 꼬리 칸을 뗐는데도 두 머리가 달라 보인다(\(tailless)) — 기준선이 재던 결함이 사라졌다면 이 파일의 전제를 다시 써라")
    }

    /// 기준선이 **빈 그림이 아님**을 따로 잰다: 짧은 이름 쌍둥이는 합친 글자 한 줄로도 꼬리가 남아 다르게 보인다.
    /// (이 짝이 없으면 머리 줄이 이름을 아예 안 그리는 날에도 위의 "꼬리를 떼면 같다"가 초록이다.)
    @Test("기준선이 살아 있다: 짧은 이름 쌍둥이는 꼬리 칸이 없어도 두 머리가 다르다 · 이름을 안 그리면 다르다")
    func theBaselineIsNotABlankPicture() throws {
        for width in Self.innerWidths {
            let shortA = try Self.limits(base: "Mac mini", tail: "A1B2", sendTail: false)
            let shortB = try Self.limits(base: "Mac mini", tail: "C3D4", sendTail: false)
            let short = try Self.diff(try Self.header(shortA, width: width), try Self.header(shortB, width: width))
            #expect(short.looksDifferent, "\(width)pt: 짧은 이름 쌍둥이가 같아 보인다(\(short)) — 머리 줄이 이름을 그리지 않는다")

            // 이름이 있는 머리 vs 맥 한 대(이름 없음) — 이름 자리가 정말로 그려진다.
            let named = try Self.limits(base: Self.maxName, tail: "A1B2", sendTail: true)
            let alone = AingWidgetLimitsHeaderLine(
                title: AingWidgetText.limitsTitle, device: nil, age: named.observationAgeText(now: Self.now),
                primary: .black, secondary: Color(white: 0.35)
            )
            .frame(width: width, alignment: .leading)
            .background(Color.white)
            let renderer = ImageRenderer(content: alone)
            renderer.scale = 2
            let aloneImage = try #require(renderer.cgImage)
            let gap = try Self.diff(try Self.header(named, width: width), aloneImage)
            #expect(gap.looksDifferent, "\(width)pt: 이름을 적은 머리와 안 적은 머리가 같아 보인다(\(gap))")
        }
    }

    /// 꼬리 자리 예산: 가장 넓은 꼬리 `(WWWW)` 도 가장 좁은 칸의 이름 자리에 **먼저** 든다(실측을 다시 잰다).
    @Test("꼬리 예산: 가장 넓은 꼬리도 좁은 칸 이름 자리에 든다 · 상수는 실측과 같다")
    func theWidestTailAlwaysHasRoom() {
        let font = NSFont.systemFont(ofSize: AingWidgetLimitsMediumBudget.deviceNameFontSize)
        let widest = Double((AILimitDeviceNameParts.tailText("WWWW") as NSString).size(withAttributes: [.font: font]).width)
        #expect(abs(widest - AingWidgetLimitsMediumBudget.worstDeviceTailWidth) < 1.5,
                "가장 넓은 꼬리 실측이 \(widest)pt 인데 상수는 \(AingWidgetLimitsMediumBudget.worstDeviceTailWidth)pt 다")
        for tail in ["A1B2", "C3D4", "0000", "FFFF"] {
            let width = Double((AILimitDeviceNameParts.tailText(tail) as NSString).size(withAttributes: [.font: font]).width)
            #expect(width <= widest + 0.01, "`(\(tail))` 가 '가장 넓은 꼬리'보다 넓다 — 상한을 잘못 잡았다")
        }
        for size in [AingWidgetLimitsMediumBudget.narrowSize, AingWidgetLimitsMediumBudget.referenceSize] {
            let budget = AingWidgetLimitsMediumBudget.family(width: size.width, height: size.height,
                                                            providerCount: 3, hasTokens: true)
            #expect(budget.deviceTailAlwaysFits(AingWidgetLimitsMediumBudget.worstDeviceTailWidth),
                    "\(size.width)pt 칸에서 꼬리가 들어갈 자리가 없다 — 긴 이름 앞에서 꼬리가 눌린다")
        }
    }

    enum HeaderRenderFailure: Error { case notLimits }
}

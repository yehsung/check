import AppKit
import Foundation
import SwiftUI
import Testing
import Vision
@testable import check
@testable import CheckCore

// MARK: - v0.3.40 팝오버 공지 카드 + 설정 설치 QR
//
// 이 스위트가 지키는 것:
//  ① 공지가 있으면 카드가 뜨고, 그 높이가 예산 상수(`CheckMenuView.appNoticeCardHeight`)와 **정확히** 맞는다.
//  ② 닫으면 그 자리가 접힌다(팝오버 높이가 공지 없는 그림으로 돌아간다).
//  ③ ★ 업데이트 배너와 **동시에 뜨지 않는다** — 둘 다 후보면 업데이트가 이긴다. 팝오버 높이 예산이 이 슬롯 하나에
//     묶여 있어서, 겹쳐 얹으면 창이 700pt 를 넘는다(0.3.23 의 사고).
//  ④ `linkURL` 이 nil 이거나 생성이 실패하면 QR 자리가 통째로 빠지고 높이도 그쪽 예산으로 줄어든다.
//  ⑤ 설정의 설치 QR 행은 공지와 **무관하게** 늘 있고, 주소는 `CheckAppLinks.iosAppStore`, 문구는 검색어 상수를 쓴다.
//  ⑥ QR: 같은 문자열이면 같은 그림, 잘못된 입력은 nil, 판은 테마와 무관하게 흰 바탕·검은 코드(보간 없음).
//  ⑦ 설정 창 높이 계약이 행만큼 늘어난 상수와 맞는다(일반·관리자).
//  ⑧ 화면 코드는 시계를 읽지 않는다(V0246 이 미니게임 패널에 건 규율).
//
// ⚠️ UserDefaults 는 전부 `CheckTestScratch` 다 — 표준 도메인에는 한 글자도 쓰지 않는다.
// ⚠️ 워크트리에는 `supabase/` 가 없어 마이그레이션 계약 테스트가 빨개진다 — 이 스위트와 무관하다(`--filter V0340`).

// MARK: - ① 공지가 있으면 카드가 뜬다 · 높이 예산

@MainActor
@Test
func 공지가_있으면_카드가_뜨고_높이가_예산과_맞다() throws {
    let plain = try #require(v0340PopoverHeight(CheckMenuView(store: v0340TeamStore())))
    let withNotice = try #require(v0340PopoverHeight(CheckMenuView(store: v0340TeamStore(notice: v0340AppStoreNotice()))))

    // 예산 상수와 **등식**이다(≥ 가 아니다). 모자라면 목록이 한 행 더 남아 창이 상한을 넘고, 남으면 행이 괜히 사라진다.
    #expect(withNotice - plain == CheckMenuView.appNoticeCardHeight,
            "카드가 \(withNotice - plain)pt 늘렸는데 예산은 \(CheckMenuView.appNoticeCardHeight)pt 다")

    // 카드에 QR 판(흰 판)이 **실제로 그려졌다** — 높이만 보면 빈 상자도 통과한다.
    let plainWhite = v0340WhitePixelCount(try #require(v0340PopoverBitmap(CheckMenuView(store: v0340TeamStore()))))
    let noticeWhite = v0340WhitePixelCount(try #require(v0340PopoverBitmap(CheckMenuView(store: v0340TeamStore(notice: v0340AppStoreNotice())))))
    // 판 176×176px(2배) 에서 QR 의 밝은 모듈만 세도 만 단위다.
    #expect(noticeWhite - plainWhite > 10_000, "QR 흰 판이 안 보인다(순백 픽셀 +\(noticeWhite - plainWhite))")

    // 본문 길이는 카드 높이를 바꾸지 않는다(QR 판이 높이를 정한다) — 서버 문구가 길어져도 예산이 산다.
    let longBody = v0340AppStoreNotice(body: v0340ThreeLineBody)
    let withLong = try #require(v0340PopoverHeight(CheckMenuView(store: v0340TeamStore(notice: longBody))))
    #expect(withLong == withNotice, "본문 3줄이 카드를 \(withLong - withNotice)pt 키웠다 — QR 판이 높이를 정해야 한다")

    v0340SavePopover(CheckMenuView(store: v0340TeamStore(notice: v0340AppStoreNotice())), name: "v0340-popover-notice.png")
}

// MARK: - ② 닫으면 접힌다

@MainActor
@Test
func 닫으면_카드가_즉시_접힌다() throws {
    let store = v0340TeamStore(notice: v0340AppStoreNotice())
    let before = try #require(v0340PopoverHeight(CheckMenuView(store: store)))
    #expect(store.appNotice != nil)

    store.dismissAppNotice()

    #expect(store.appNotice == nil, "닫았는데 공지가 남아 있다")
    let after = try #require(v0340PopoverHeight(CheckMenuView(store: store)))
    let plain = try #require(v0340PopoverHeight(CheckMenuView(store: v0340TeamStore())))
    #expect(after == plain, "닫은 뒤 \(after)pt — 공지 없는 그림(\(plain)pt)으로 돌아와야 한다")
    #expect(before - after == CheckMenuView.appNoticeCardHeight)
}

// MARK: - ③ ★ 업데이트 배너와 동시에 뜨지 않는다 — 업데이트가 이긴다

@MainActor
@Test
func 업데이트_배너가_있으면_공지_카드는_양보한다() throws {
    let plain = try #require(v0340PopoverHeight(CheckMenuView(store: v0340TeamStore())))
    let updateOnly = try #require(v0340PopoverHeight(CheckMenuView(store: v0340TeamStore(), previewUpdateBanner: true)))
    let noticeOnly = try #require(v0340PopoverHeight(CheckMenuView(store: v0340TeamStore(notice: v0340AppStoreNotice()))))
    let both = try #require(v0340PopoverHeight(
        CheckMenuView(store: v0340TeamStore(notice: v0340AppStoreNotice()), previewUpdateBanner: true)
    ))

    // 두 후보가 함께면 그림은 **업데이트 배너 하나짜리**와 같다 — 카드는 1pt 도 얹히지 않는다.
    #expect(both == updateOnly, "둘 다 후보일 때 \(both)pt — 업데이트만 \(updateOnly)pt 여야 한다(공지가 함께 그려졌다)")
    #expect(both != noticeOnly, "업데이트 배너가 밀렸다 — 앱 안에서 업데이트로 가는 유일한 경로다")
    #expect(both < plain + CheckMenuView.appNoticeCardHeight + CheckMenuView.updateBannerHeight,
            "둘이 겹쳐 쌓였다(\(both)pt) — 이 슬롯은 한 번에 하나다")

    // 밀린 공지는 **소비되지 않는다** — 업데이트가 사라진 다음 팝오버에 그대로 뜬다.
    let store = v0340TeamStore(notice: v0340AppStoreNotice())
    _ = try #require(v0340PopoverHeight(CheckMenuView(store: store, previewUpdateBanner: true)))
    #expect(store.appNotice != nil)
    let later = try #require(v0340PopoverHeight(CheckMenuView(store: store)))
    #expect(later == noticeOnly)

    // 소스로도 못 박는다: topBanner 안에서 `.update` 판정이 `.appNotice` 판정보다 **앞**에 있다(주석은 걷고 읽는다).
    let source = v0340StrippingSwiftComments(try String(contentsOf: v0340SourceURL("CheckMenuView.swift"), encoding: .utf8))
    let head = try #require(source.range(of: "private var topBanner: TopBanner? {"))
    let tail = try #require(source.range(of: "private var topBannerHeight", range: head.upperBound..<source.endIndex))
    let body = source[head.upperBound..<tail.lowerBound]
    let update = try #require(body.range(of: "return .update"))
    let notice = try #require(body.range(of: "return .appNotice"))
    #expect(update.lowerBound < notice.lowerBound, "topBanner 에서 공지가 업데이트보다 먼저 판정된다")
    // 그리는 자리도 같은 게이트를 지난다 — `if store.appNotice != nil` 같은 우회로 그리면 예산 밖에서 두 개가 선다.
    #expect(source.contains("if topBanner == .appNotice, let notice = store.appNotice {"),
            "공지 카드가 topBanner 게이트 없이 그려진다")
}

// MARK: - ④ linkURL nil / 생성 실패 → QR 자리가 빠진다

@MainActor
@Test
func linkURL_이_없으면_QR_자리가_빠지고_높이도_줄어든다() throws {
    let plain = try #require(v0340PopoverHeight(CheckMenuView(store: v0340TeamStore())))
    let withQR = try #require(v0340PopoverHeight(CheckMenuView(store: v0340TeamStore(notice: v0340AppStoreNotice()))))

    // QR 없는 쪽 예산은 **본문 3줄 최악값**과 등식이다.
    let noLinkLong = v0340Notice(body: v0340ThreeLineBody, linkURL: nil)
    let worst = try #require(v0340PopoverHeight(CheckMenuView(store: v0340TeamStore(notice: noLinkLong))))
    #expect(worst - plain == CheckMenuView.appNoticeCardHeightWithoutQR,
            "QR 없는 카드(본문 3줄)가 \(worst - plain)pt 인데 예산은 \(CheckMenuView.appNoticeCardHeightWithoutQR)pt 다")
    #expect(worst < withQR, "QR 을 뺐는데 카드가 안 낮아졌다")

    // 짧은 본문은 그보다 낮거나 같다(과대 추정은 안전측).
    let noLinkShort = v0340Notice(body: "아이폰 앱이 나왔어요", linkURL: nil)
    let short = try #require(v0340PopoverHeight(CheckMenuView(store: v0340TeamStore(notice: noLinkShort))))
    #expect(short - plain <= CheckMenuView.appNoticeCardHeightWithoutQR)
    #expect(short > plain, "링크가 없어도 카드(제목·본문·닫기)는 있어야 한다")

    // 흰 판이 **없다** — 빈 상자를 그리지 않는다.
    let plainWhite = v0340WhitePixelCount(try #require(v0340PopoverBitmap(CheckMenuView(store: v0340TeamStore()))))
    let noLinkWhite = v0340WhitePixelCount(try #require(v0340PopoverBitmap(CheckMenuView(store: v0340TeamStore(notice: noLinkLong)))))
    #expect(abs(noLinkWhite - plainWhite) < 500, "링크 없는 카드에 흰 판이 있다(순백 픽셀 차 \(noLinkWhite - plainWhite))")

    // 주소가 있어도 **그릴 수 없으면**(너무 긴 문자열) 같은 취급이다 — 예산도 QR 없는 쪽을 읽는다.
    let broken = v0340Notice(body: v0340ThreeLineBody, linkURL: String(repeating: "a", count: 3_000))
    let brokenHeight = try #require(v0340PopoverHeight(CheckMenuView(store: v0340TeamStore(notice: broken))))
    #expect(brokenHeight == worst, "생성 실패인데 QR 자리가 남았다(\(brokenHeight)pt vs \(worst)pt)")

    v0340SavePopover(CheckMenuView(store: v0340TeamStore(notice: noLinkLong)), name: "v0340-popover-notice-nolink.png")
}

// MARK: - ⑤ 설정 QR 행은 공지와 무관하게 늘 있다

@MainActor
@Test
func 설정_QR_행은_공지와_무관하게_항상_있다() throws {
    let suite = v0340Suite()
    defer { v0340Drop(suite) }

    // 공지 없음 · 공지 있음 · 공지 닫음 — 세 상태의 설정 화면이 **같은 그림 높이**다.
    let none = try v0340SettingsHeight(admin: false, notice: nil, characterDefaults: suite.defaults)
    let shown = try v0340SettingsHeight(admin: false, notice: v0340AppStoreNotice(), characterDefaults: suite.defaults)
    let dismissed = try v0340SettingsHeight(admin: false, notice: v0340AppStoreNotice(), dismissed: true,
                                            characterDefaults: suite.defaults)
    #expect(none == shown && shown == dismissed,
            "설정 높이가 공지 상태에 따라 갈린다(없음 \(none) · 있음 \(shown) · 닫음 \(dismissed))")

    // 행이 실제로 QR 을 그린다(흰 판) — 공지가 없는 상태에서.
    let bitmap = try v0340SettingsBitmap(admin: false, notice: nil, characterDefaults: suite.defaults)
    #expect(v0340WhitePixelCount(bitmap) > 10_000, "설정에 QR 흰 판이 없다")

    // 행 하나의 높이는 QR 판과 같다(고정 88pt) — 글 열이 판보다 낮아야 창 계약이 폭에 안 흔들린다.
    let rowHeight = try #require(v0340Height(IOSAppInstallSettingsRow(), width: v0340CardContentWidth))
    #expect(rowHeight == CheckQRCodeView.plateSide(for: IOSAppInstallSettingsRow.qrSide),
            "설치 QR 행이 \(rowHeight)pt — QR 판 \(CheckQRCodeView.plateSide(for: IOSAppInstallSettingsRow.qrSide))pt 여야 한다")

    // 주소는 공지가 아니라 앱스토어 상수다. 문구는 검색어 상수·최소 iOS 상수를 지난다(소스 계약).
    let source = v0340StrippingSwiftComments(try String(contentsOf: v0340SourceURL("CheckSettingsView.swift"), encoding: .utf8))
    let head = try #require(source.range(of: "struct IOSAppInstallSettingsRow: View {"))
    let tail = try #require(source.range(of: "struct WorkShortcutRecorderRow", range: head.upperBound..<source.endIndex))
    let row = source[head.upperBound..<tail.lowerBound]
    #expect(row.contains("CheckAppLinks.iosAppStore"), "설정 QR 이 앱스토어 상수를 안 읽는다")
    #expect(!row.contains("appNotice") && !row.contains("linkURL"), "설정 QR 이 공지의 주소를 읽는다 — 공지는 사라질 수 있다")
    #expect(row.contains("CheckIOSAppText.settingsDetail") && row.contains("CheckIOSAppText.settingsTitle"))
    #expect(source.contains("IOSAppInstallSettingsRow()"), "설정 본문에 행이 안 붙었다")

    // 문구 자체: 검색어와 최소 iOS 가 **둘 다** 들어 있고, 검색어는 등록명 그대로(띄어쓰기 없음)이며 "아잉" 한 단어가 아니다.
    #expect(CheckIOSAppText.settingsDetail.contains(CheckIOSAppText.storeSearchName))
    #expect(CheckIOSAppText.settingsDetail.contains(CheckAppLinks.iosMinimumVersionText))
    #expect(CheckIOSAppText.noticeCaption.contains(CheckIOSAppText.storeSearchName))
    #expect(CheckIOSAppText.noticeCaption.contains(CheckAppLinks.iosMinimumVersionText))
    #expect(!CheckIOSAppText.storeSearchName.contains(" "), "등록명은 붙여쓰기다")
    #expect(CheckIOSAppText.storeSearchName != "아잉", "'아잉' 한 단어는 데이팅·마사지 앱 뒤 7위다")
    #expect(CheckIOSAppText.storeSearchName.hasPrefix("아잉"), "검색어가 앱 이름 계열이 아니다")

    v0340Save(bitmap, name: "v0340-settings-plain.png")
}

// MARK: - ⑥ QR 생성기

@Test
func QR_은_같은_문자열이면_같은_그림이고_잘못된_입력은_nil() throws {
    let url = CheckAppLinks.iosAppStore.absoluteString
    let a = try #require(CheckQRCode.image(for: url))
    let b = try #require(CheckQRCode.image(for: url))
    #expect(v0340PNG(a) == v0340PNG(b), "같은 문자열이 다른 그림을 냈다")
    // 앱스토어 주소(38바이트)는 레벨 M 에서 버전 3(29모듈) + CI 조용 영역 2 = 31 모듈 — 배율 10.
    #expect(a.width == 31 * CheckQRCode.pixelsPerModule && a.height == a.width,
            "\(a.width)px — 정정 레벨이나 배율이 바뀌었다(31 × \(CheckQRCode.pixelsPerModule) 이어야 한다)")
    #expect(v0340PNG(a) != v0340PNG(try #require(CheckQRCode.image(for: url + "x"))), "다른 문자열이 같은 그림이다")

    #expect(CheckQRCode.image(for: "") == nil, "빈 문자열은 찍을 것이 없다")
    #expect(CheckQRCode.image(for: String(repeating: "a", count: 3_000)) == nil, "규격 상한 밖은 nil")
    #expect(CheckQRCode.image(for: String(repeating: "a", count: CheckQRCode.maxInputBytes + 1)) == nil)
    #expect(CheckQRCode.correctionLevel == "M")
}

@MainActor
@Test
func QR_판은_테마와_무관하게_흰_바탕_검은_코드다() throws {
    let image = try #require(CheckQRCode.image(for: CheckAppLinks.iosAppStore.absoluteString))
    let side = AppNoticeCard.qrSide
    // 이 앱의 어두운 카드 위에 놓는다 — 실제로 놓이는 자리다.
    let view = CheckQRCodeView(image: image, side: side).padding(10).background(CheckTheme.panel)
    let bitmap = try #require(v0340Bitmap(view, width: CheckQRCodeView.plateSide(for: side) + 20))

    // 판 모서리 안쪽(조용 영역)은 순백이다.
    let inset = Int((10 + 3) * 2)   // 바깥 여백 10 + 판 안쪽 3pt, 2배
    #expect(v0340Pixel(bitmap, inset, inset) == [255, 255, 255], "조용 영역이 흰색이 아니다 — 테마를 따라가면 폰이 못 읽는다")
    // 코드 영역에는 검은 픽셀이 있고, **회색이 없다**(보간이 끼면 모듈 경계가 회색 띠가 된다).
    let start = Int((10 + CheckQRCodeView.quietZone) * 2)
    let end = start + Int(side * 2)
    var black = 0, grey = 0
    for y in stride(from: start, to: end, by: 2) {
        for x in stride(from: start, to: end, by: 2) {
            let p = v0340Pixel(bitmap, x, y)
            if p[0] < 40 && p[1] < 40 && p[2] < 40 { black += 1 }
            else if !(p[0] > 215 && p[1] > 215 && p[2] > 215) { grey += 1 }
        }
    }
    #expect(black > 300, "검은 모듈이 \(black)개뿐이다 — 코드가 안 그려졌다")
    #expect(grey == 0, "회색 픽셀 \(grey)개 — 보간이 끼었다(interpolation(.none) 가 빠졌나)")
    v0340Save(bitmap, name: "v0340-qr-plate.png")
}

/// 그린 크기 **그대로** 디코딩된다 — 카메라 광학은 못 재지만, 판·여백·보간 없는 축소가 코드를 깨뜨리지 않았다는 사실은 여기서 잰다.
/// 2배(레티나 화면 픽셀)와 **1배**(외장 FHD 모니터 = 코드 한 변 72px) 둘 다 읽혀야 한다.
@MainActor
@Test
func QR_판은_그린_크기_그대로_디코딩된다() throws {
    let url = CheckAppLinks.iosAppStore.absoluteString
    let image = try #require(CheckQRCode.image(for: url))
    let view = CheckQRCodeView(image: image, side: AppNoticeCard.qrSide).padding(10).background(CheckTheme.panel)
    for scale in [CGFloat(2), 1] {
        let renderer = ImageRenderer(content: view.fixedSize())
        renderer.scale = scale
        let cg = try #require(renderer.cgImage)
        #expect(v0340DecodeQR(cg) == url, "배율 \(scale) 로 그린 판이 디코딩되지 않는다(\(cg.width)px)")
    }
}

// MARK: - ⑦ 설정 창 높이 계약(일반·관리자)

@MainActor
@Test
func 설정_창_높이_상수가_설치_QR_행만큼_늘었다() throws {
    let suite = v0340Suite()
    defer { v0340Drop(suite) }
    let plain = try v0340SettingsHeight(admin: false, notice: nil, characterDefaults: suite.defaults)
    let admin = try v0340SettingsHeight(admin: true, notice: nil, characterDefaults: suite.defaults)

    // 일반: 가장 높은 상태(단축키 안내 한 줄) + 되돌리기 확인 여유(13)가 창 안에 든다(V0316·V0336 과 같은 계약).
    #expect(plain + AvatarRemovalSettingsRow.maxExtraHeight <= CheckSettingsWindowController.defaultContentSize.height,
            "일반 설정 \(plain)pt + 여유 13 이 창 \(CheckSettingsWindowController.defaultContentSize.height)pt 를 넘는다")
    // 창 여유는 5pt 규약이다 — 상수를 넉넉히 올려 두면 계약 숫자가 흐려진다.
    #expect(CheckSettingsWindowController.defaultContentSize.height - (plain + AvatarRemovalSettingsRow.maxExtraHeight) == 5,
            "창 여유가 \(CheckSettingsWindowController.defaultContentSize.height - plain - AvatarRemovalSettingsRow.maxExtraHeight)pt — 5pt 규약")
    // 관리자: 전체 렌더 + 여유 = 선언값(V0316 의 등식과 같다).
    #expect(admin + AvatarRemovalSettingsRow.maxExtraHeight == CheckSettingsView.adminContentHeight,
            "관리자 \(admin)pt + 13 ≠ 선언값 \(CheckSettingsView.adminContentHeight)pt")
    v0340Save(try v0340SettingsBitmap(admin: true, notice: nil, characterDefaults: suite.defaults), name: "v0340-settings-admin.png")
}

// MARK: - 팝오버 상한(카드를 얹은 큰 팀)

@MainActor
@Test
func 공지_카드를_얹어도_팝오버는_상한_안이다() throws {
    let store = v0340TeamStore(members: 10, notice: v0340AppStoreNotice())
    let height = try #require(v0340PopoverHeight(CheckMenuView(store: store)))
    #expect(height <= 700, "10명 팀 + 공지 카드가 \(height)pt — 700pt 상한을 넘는다")
}

// MARK: - ⑧ 화면 코드는 시계를 읽지 않는다 · 크롬은 공용 부품

@Test
func 공지_화면_코드는_시계를_읽지_않고_공용_크롬을_쓴다() throws {
    for file in ["CheckAppNoticeCard.swift", "CheckQRCodeView.swift"] {
        let source = v0340StrippingSwiftComments(try String(contentsOf: v0340SourceURL(file), encoding: .utf8))
        for clock in ["Date()", "Timer.publish", "displayNow", "TimelineView"] {
            #expect(!source.contains(clock), "\(file) 이 \(clock) 을 읽는다")
        }
    }
    let card = v0340StrippingSwiftComments(try String(contentsOf: v0340SourceURL("CheckAppNoticeCard.swift"), encoding: .utf8))
    #expect(card.contains(".panelStyle()"), "카드가 공용 크롬(panelStyle)을 안 쓴다")
    #expect(!card.contains("RoundedRectangle("), "카드가 크롬을 새로 그린다")
    #expect(card.contains("store.dismissAppNotice") || card.contains("onDismiss"), "닫기가 스토어 한 줄이 아니다")

    let settings = v0340StrippingSwiftComments(try String(contentsOf: v0340SourceURL("CheckSettingsView.swift"), encoding: .utf8))
    let head = try #require(settings.range(of: "struct IOSAppInstallSettingsRow: View {"))
    let tail = try #require(settings.range(of: "struct WorkShortcutRecorderRow", range: head.upperBound..<settings.endIndex))
    #expect(!settings[head.upperBound..<tail.lowerBound].contains("Date()"))
}

// MARK: - 헬퍼(다른 파일의 것은 private 이라 여기 다시 둔다)

/// 본문 줄 상한(3)을 **넘치는** 문구 — QR 없는 카드(본문 폭 294)에서 네 줄 몫이라 lineLimit 이 3줄로 자른다.
/// 실측(2026-09-28): caption2 로 한 줄에 38자 안팎 · 이 문구는 130자.
private let v0340ThreeLineBody = "앱스토어에서 아잉체크를 검색하거나 QR 을 찍어 설치해 주세요. 근무 현황과 할 일, 미니게임을 폰에서도 볼 수 있어요. 위젯으로 잠금 화면에서 근무 중인 사람을 바로 확인하고, 알림으로 콕을 받아 보세요. 지금 바로 받아 보세요."

/// 카드 안쪽 폭(설정 창 폭 하한 380 − 바깥 여백 14×2 − 카드 여백 12×2). V0336 과 같은 값.
private let v0340CardContentWidth: CGFloat = 328

private func v0340AppStoreNotice(body: String = "앱스토어에서 아잉체크를 검색하거나 QR 을 찍어 주세요") -> AppNotice {
    v0340Notice(body: body, linkURL: CheckAppLinks.iosAppStore.absoluteString)
}

private func v0340Notice(body: String, linkURL: String?) -> AppNotice {
    AppNotice(id: "ios-launch-2026-09", title: "아이폰 앱도 있어요", body: body, linkURL: linkURL, linkLabel: nil)
}

/// 공지를 스토어에 심는 **유일한 문**. 앱이 실제로 쓰는 문과 같다 — `CheckApp` 의 `onNoticeFetched` 가 부르는
/// `applyAppNotice(_:)` 다(V0340AppNoticeTests 가 그 배선을 따로 잰다). 테스트 전용 뒷문을 두지 않는 이유가 여기 있다:
/// 뒷문으로 심으면 "앱이 실제로 거치는 경로"를 안 지나므로, 그 경로가 끊겨도 이 파일은 초록으로 남는다.
@MainActor
private func v0340Seed(_ store: WorkTimerStore, notice: AppNotice?) {
    store.applyAppNotice(notice)
}

@MainActor
private func v0340InertTokenStore(_ label: String, function: String) -> TokenUsageStore {
    let home = CheckTestScratch.directory("token-" + label, function: function)
    return TokenUsageStore(
        defaults: CheckTestScratch.defaults("token-" + label, function: function),
        homeDirectory: home.appendingPathComponent("home", isDirectory: true),
        cacheURL: home.appendingPathComponent("cache.json", isDirectory: false)
    )
}

/// 로그인 + 팀 확정(메인 화면) 스토어. `#line` 을 섞는 이유: 한 테스트가 스토어를 여럿 세워 서로 견준다.
@MainActor
private func v0340TeamStore(members: Int = 1, notice: AppNotice? = nil,
                            function: String = #function, line: Int = #line) -> WorkTimerStore {
    let now = Date()
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: CheckTestScratch.defaults("team-L\(line)", function: function),
        tokenUsage: v0340InertTokenStore("team-L\(line)", function: function)
    )
    // 렌더 결정성: onAppear 의 setMenuPresented(true) 가 != 가드로 no-op 되도록 선세팅한다.
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil,
                                    userID: "00000000-0000-0000-0000-000000000002")
    store.displayNow = now
    store.currentTeamID = "00000000-0000-0000-0000-0000000000aa"
    store.teamName = "아잉팀"
    store.myCenterLoaded = true
    store.myCenter = CenterLabel.seoul
    let names = ["영식", "민수", "지현", "서준", "하윤", "도현", "예린", "yesung", "태우", "보라"]
    store.teamMembers = Array(names.prefix(members)).enumerated().map { index, name in
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-00000000000\(index)",
            name: name,
            status: index % 3 == 2 ? .offWork : .working,
            updatedAt: nil,
            currentSessionStartedAt: index % 3 == 2 ? nil : now.addingTimeInterval(-3_600 - Double(index) * 600),
            weeklyDurationSeconds: 7_200 + index * 3_600
        )
    }
    v0340Seed(store, notice: notice)
    return store
}

private struct V0340Suite {
    let name: String
    let defaults: UserDefaults
}

private func v0340Suite(function: String = #function, line: Int = #line) -> V0340Suite {
    let tag = "chars-L\(line)"
    return V0340Suite(name: CheckTestScratch.suitePath(tag, function: function),
                      defaults: CheckTestScratch.defaults(tag, function: function))
}

/// 같은 프로세스 안 뒤따르는 읽기를 막는 보험일 뿐이다 — 진짜 정리는 `CheckTestScratch` 가 시작할 때 한다.
private func v0340Drop(_ suite: V0340Suite) {
    suite.defaults.removePersistentDomain(forName: suite.name)
    UserDefaults.standard.removeSuite(named: suite.name)
}

private enum V0340Error: Error { case renderFailed }

@MainActor
private func v0340Bitmap(_ view: some View, width: CGFloat) -> NSBitmapImageRep? {
    // 배율은 **언제나 명시한다** — 기본값은 주 디스플레이 backingScaleFactor 라 기계마다 갈린다.
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap
}

@MainActor
private func v0340Height(_ view: some View, width: CGFloat) -> CGFloat? {
    v0340Bitmap(view, width: width).map { CGFloat($0.pixelsHigh) / 2 }
}

/// 팝오버는 **자연 폭**으로 그린다(메인 화면은 레일이 붙어 414 — 폭을 고정하면 본문이 밀린다).
@MainActor
private func v0340PopoverBitmap(_ view: CheckMenuView) -> NSBitmapImageRep? {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap
}

@MainActor
private func v0340PopoverHeight(_ view: CheckMenuView) -> CGFloat? {
    v0340PopoverBitmap(view).map { CGFloat($0.pixelsHigh) / 2 }
}

/// 설정 화면 전체를 창 폭 하한에서, **가장 높은 상태**(단축키 안내 한 줄 켬)로 그린다 — V0316·V0336 과 같은 규약.
@MainActor
private func v0340SettingsBitmap(admin: Bool, notice: AppNotice?, dismissed: Bool = false,
                                 characterDefaults: UserDefaults,
                                 function: String = #function, line: Int = #line) throws -> NSBitmapImageRep {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon"],
        defaults: CheckTestScratch.defaults("settings-\(admin)-L\(line)", function: function)
    )
    store.myCenterLoaded = true
    store.myCenter = CenterLabel.seoul
    store.ultraUnlimited = admin
    store.workShortcutStatus = .conflict
    v0340Seed(store, notice: notice)
    if dismissed { store.dismissAppNotice() }
    // launchAtLoginSeed 를 반드시 준다 — 안 주면 렌더가 실제 로그인 항목(SMAppService)을 읽는다.
    guard let bitmap = v0340Bitmap(
        CheckSettingsView(store: store, launchAtLoginSeed: false, characterDefaults: characterDefaults),
        width: CheckSettingsView.preferredWidth
    ) else { throw V0340Error.renderFailed }
    return bitmap
}

@MainActor
private func v0340SettingsHeight(admin: Bool, notice: AppNotice?, dismissed: Bool = false,
                                 characterDefaults: UserDefaults,
                                 function: String = #function, line: Int = #line) throws -> CGFloat {
    CGFloat(try v0340SettingsBitmap(admin: admin, notice: notice, dismissed: dismissed,
                                    characterDefaults: characterDefaults, function: function, line: line).pixelsHigh) / 2
}

private func v0340Pixel(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> [Int] {
    guard let data = bitmap.bitmapData else { return [] }
    let o = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel
    return [Int(data[o]), Int(data[o + 1]), Int(data[o + 2])]
}

/// 순백(255,255,255) 픽셀 수. 이 앱의 글자는 흰색 94% 라 순백에 거의 안 닿고, QR 판만 순백이다.
private func v0340WhitePixelCount(_ bitmap: NSBitmapImageRep) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var count = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            if data[o] == 255 && data[o + 1] == 255 && data[o + 2] == 255 { count += 1 }
        }
    }
    return count
}

private func v0340PNG(_ image: CGImage) -> Data? {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

/// macOS 내장 Vision 으로 QR 을 읽는다(외부 의존성 없음). 못 읽으면 nil.
private func v0340DecodeQR(_ image: CGImage) -> String? {
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    guard (try? handler.perform([request])) != nil else { return nil }
    return request.results?.first?.payloadStringValue
}

private func v0340SourceURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/check/\(name)")
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(하우스 규칙). 문자열 리터럴 안의 `//` 는 남긴다.
private func v0340StrippingSwiftComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character = " "
    let characters = Array(source)
    var index = 0
    while index < characters.count {
        let character = characters[index]
        let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
        if inLineComment {
            if character == "\n" {
                inLineComment = false
                result.append(character)
            }
        } else if inBlockComment {
            if character == "*", next == "/" {
                inBlockComment = false
                index += 1
            }
        } else if inString {
            if character == "\"", previous != "\\" { inString = false }
            result.append(character)
        } else if character == "/", next == "/" {
            inLineComment = true
            index += 1
        } else if character == "/", next == "*" {
            inBlockComment = true
            index += 1
        } else if character == "\"" {
            inString = true
            result.append(character)
        } else {
            result.append(character)
        }
        previous = character
        index += 1
    }
    return result
}

private func v0340Save(_ bitmap: NSBitmapImageRep, name: String) {
    let dir = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-v0340", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: dir.appendingPathComponent(name))
}

@MainActor
private func v0340SavePopover(_ view: CheckMenuView, name: String) {
    guard let bitmap = v0340PopoverBitmap(view) else { return }
    v0340Save(bitmap, name: name)
}

import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import check

// v0.3.30 M2 — 메뉴바 빨간 점의 사유가 셋이 됐다(새 메시지 · 오목 신청 · 업데이트) + 레일 [콕찌르기] 칸의 안 읽음 점.
//
// 지키는 것:
//  (a) 셋 다 꺼지면 라벨은 **점이 생기기 전 그림과 같다**(인자 없는 라벨 · v0.3.19 라벨 사본 — 기준선이 둘인 이유는
//      V0320MenuBarUpdateDotTests 머리 주석: 같은 입력 기준선 하나면 "항상 점"인 결함이 초록이다). "같다"는 바이트 일치이고,
//      다른 렌더 스위트와 함께 돌 때만 보이는 재표본 흔들림(3px · 채널 차 1)만 허용한다(`M2DLabelPixels.matches` 주석).
//  (b) 하나라도 켜지면 **업데이트 점과 같은** 그림이다(같은 빨간 점 — 사유마다 다른 얼굴이 아니다).
//  (c) 보이스오버 설명은 켜진 사유들을 " · " 로 잇고, 상태바 버튼이 받는 **새 이미지**에 실린다(공유 인스턴스는 그대로).
//  (d) 앱이 스토어 두 값을 라벨에 넘긴다(소스) — 라벨 인자만 있고 배선이 없으면 (a)~(c) 는 초록인 채로 점이 안 뜬다.
//  (e) 레일 [콕찌르기] 칸: 안 읽은 메시지가 있으면 그 칸 오른쪽 위 모서리에만 점이 생긴다(픽셀).

private let m2dSnapshots: [(name: String, snapshot: WorkStatusSnapshot)] = [
    ("off", WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)),
    ("working", WorkStatusSnapshot(status: .working, elapsedSeconds: 3_661))
]

/// v0.3.19 까지의 `MenuBarStatusLabel.body` 사본(점을 한 줄도 모르는 기준선). V0320 스위트의 사본과 같은 내용이다 —
/// 그쪽은 private 이라 이 파일이 따로 든다. 라벨 모양을 일부러 바꾸는 날엔 이 사본도 함께 고쳐라.
private struct M2DLegacyMenuBarLabel: View {
    let snapshot: WorkStatusSnapshot
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            if let mascot = CheckMascotAssets.menuBarImage(for: snapshot) {
                Image(nsImage: mascot)
            } else {
                Image(systemName: MenuBarStatusFormatter.symbolName(for: snapshot))
                    .symbolRenderingMode(.hierarchical)
                    .imageScale(.medium)
            }
            Text(title)
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
        }
    }
}

@MainActor
private func m2dWithAing<R>(_ body: () throws -> R) rethrows -> R {
    try CheckMascotAssets.$characterIDOverride.withValue(CharacterCatalog.builtInAingID, operation: body)
}

/// 메뉴바 틀(높이 22 · 좌우 6 · 어두운 바)로 그린 그림(sRGB RGBA8 버퍼).
private struct M2DLabelPixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    /// 바이트 지문(실패 메시지가 큰 배열 차분을 계산하느라 멎지 않게 해시로 비교한다 — V0320 과 같은 이유).
    var digest: String {
        var hasher = SHA256()
        hasher.update(data: Data("\(width)x\(height)".utf8))
        hasher.update(data: Data(bytes))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 같은 그림인가: **바이트가 같거나**, 다른 픽셀이 한 줌(≤ 16)이고 채널 차가 ≤ 2 인가.
    ///
    /// ★ 왜 문턱이 있나(2026-09-16 실측): 이 스위트를 다른 렌더 스위트와 **함께** 돌리면, 코드가 한 줄도 안 다른
    ///   인자 없는 라벨과 v0.3.19 사본조차 바이트가 갈린다 — 3픽셀 · 채널 차 1. 캐시의 공유 NSImage 를 다른 테스트가 그리는
    ///   순간 재표본이 한 단계 흔들리는 것으로 보인다(단독 실행에선 0). 점이 잘못 켜지거나 꺼지면 빨강(≈ 채널 차 200)이
    ///   수백 픽셀 바뀌므로 이 문턱은 그 결함을 가리지 못한다(변이 검증에서 확인).
    func matches(_ other: M2DLabelPixels) -> Bool {
        if digest == other.digest { return true }
        let diff = difference(from: other)
        return diff.pixels >= 0 && diff.pixels <= 16 && diff.maxDelta <= 2
    }

    /// 다른 그림과 바이트가 다른 픽셀 수와 가장 큰 채널 차(크기가 다르면 -1).
    func difference(from other: M2DLabelPixels) -> (pixels: Int, maxDelta: Int) {
        guard width == other.width, height == other.height else { return (-1, -1) }
        var pixels = 0, maxDelta = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            var delta = 0
            for channel in 0..<4 { delta = max(delta, abs(Int(bytes[index + channel]) - Int(other.bytes[index + channel]))) }
            if delta > 0 { pixels += 1; maxDelta = max(maxDelta, delta) }
        }
        return (pixels, maxDelta)
    }
}

@MainActor
private func m2dLabelPixels(_ label: some View) throws -> M2DLabelPixels {
    let view = label
        .frame(height: 22)
        .padding(.horizontal, 6)
        .background(Color(red: 0.12, green: 0.13, blue: 0.17))
        .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.cgImage, "메뉴바 라벨이 그려지지 않았다")
    let width = image.width, height = image.height
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    buffer.withUnsafeMutableBytes { raw in
        let context = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return M2DLabelPixels(width: width, height: height, bytes: buffer)
}

private func m2dSource(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check/\(name)")
    return m2dStripComments(try String(contentsOf: url, encoding: .utf8))
}

private func m2dStripComments(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let nextIndex = source.index(after: index)
        let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = nextIndex }
        } else if inString {
            out.append(c)
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true; index = nextIndex
        } else if c == "\"" {
            inString = true; out.append(c)
        } else {
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out
}

// MARK: - 레일 픽스처

private enum M2DRenderError: Error { case failed }

@MainActor
private func m2dMenuBitmap(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: CheckMenuView(store: store, previewClipsOverflowList: true, previewPlainTextEditors: true))
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw M2DRenderError.failed }
    return bitmap
}

/// 메인 화면(로그인 + 팀 확정) 스토어. **비근무**다 — 이 기능의 주인공이다.
@MainActor
private func m2dMainScreenStore(_ label: String) -> WorkTimerStore {
    let store = makeMessageReadStore(label).store
    store.isMenuPresented = true
    store.displayNow = MessageReadFixture.now
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
    store.teamMembers = [
        TeamMemberStatus(id: MessageReadFixture.me, name: "영식", status: .offWork, updatedAt: nil,
                         currentSessionStartedAt: nil, weeklyDurationSeconds: 7_200)
    ]
    return store
}

/// 레일 i번째 칸(pt, 창 좌표). 숫자는 전부 레이아웃 상수에서 온다(CheckMenuRenderTests.railButtonRect 와 같은 계산 — 위 칸만).
@MainActor
private func m2dRailButtonRect(_ index: Int) -> CGRect {
    let left = 12 + CheckMenuView.contentColumnWidth + 10
    let top = 12 + CGFloat(index) * (CheckMenuSideRail.buttonHeight + CheckMenuSideRail.buttonSpacing)
    return CGRect(x: left, y: top, width: CheckMenuSideRail.width, height: CheckMenuSideRail.buttonHeight)
}

/// 두 그림이 다른 픽셀(pt 좌표 목록 대신 개수 · 경계).
private func m2dDiff(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> (count: Int, box: CGRect, blue: Int) {
    guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh,
          let a = lhs.bitmapData, let b = rhs.bitmapData else { return (-1, .null, 0) }
    let bpr = lhs.bytesPerRow, spp = lhs.samplesPerPixel
    var count = 0, blue = 0
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<lhs.pixelsHigh {
        for x in 0..<lhs.pixelsWide {
            let o = y * bpr + x * spp
            let d = abs(Int(a[o]) - Int(b[o])) + abs(Int(a[o + 1]) - Int(b[o + 1])) + abs(Int(a[o + 2]) - Int(b[o + 2]))
            guard d > 24 else { continue }
            count += 1
            if Int(a[o + 2]) > 150 && Int(a[o + 2]) > Int(a[o]) + 60 { blue += 1 }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard count > 0 else { return (0, .null, 0) }
    return (count, CGRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2,
                          width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2), blue)
}

@MainActor
@Suite("V0330MenuBarDot")
struct V0330MenuBarDotTests {
    // MARK: (a)(b) 조합 표 — 바이트

    /// 기준 그림은 **조합마다 바로 옆에서** 다시 그린다(V0320 (a) 와 같은 방식). 한참 전에 그린 기준과 맞대면 그사이 다른
    /// 테스트가 캐시의 공유 NSImage 를 그려 표현 캐시가 바뀌었을 때 바이트가 갈린다(실측: 세 스위트를 함께 돌릴 때 한 번) —
    /// 그건 이 기능의 결함이 아니라 기준선이 낡은 것이다.
    @Test func 사유_조합_표_셋_다_꺼지면_옛_그림_하나라도_켜지면_업데이트_점과_같은_그림() throws {
        try m2dWithAing {
            for fixture in m2dSnapshots {
                let title = MenuBarStatusFormatter.title(for: fixture.snapshot)
                for messages in [false, true] {
                    for gomoku in [false, true] {
                        for update in [false, true] {
                            let tag = "\(fixture.name) 메시지=\(messages) 오목=\(gomoku) 업데이트=\(update)"
                            let legacy = try m2dLabelPixels(M2DLegacyMenuBarLabel(snapshot: fixture.snapshot, title: title))
                            let updateOnly = try m2dLabelPixels(
                                MenuBarStatusLabel(snapshot: fixture.snapshot, title: title, updateAvailable: true)
                            )
                            let combo = try m2dLabelPixels(MenuBarStatusLabel(
                                snapshot: fixture.snapshot, title: title, updateAvailable: update,
                                hasUnreadMessages: messages, hasGomokuInvite: gomoku
                            ))
                            #expect(!updateOnly.matches(legacy), "\(tag): 업데이트 점이 안 그려진다 — 비교가 헛돈다")
                            if !messages && !gomoku && !update {
                                let omitted = try m2dLabelPixels(MenuBarStatusLabel(snapshot: fixture.snapshot, title: title))
                                #expect(combo.matches(legacy),
                                        "\(tag): 셋 다 꺼졌는데 옛 그림과 다르다 \(combo.difference(from: legacy))")
                                #expect(omitted.matches(legacy), "\(tag): 인자 없는 라벨이 옛 그림과 다르다")
                            } else {
                                #expect(combo.matches(updateOnly),
                                        "\(tag): 점이 업데이트 점과 같은 그림이 아니다 \(combo.difference(from: updateOnly))")
                                #expect(!combo.matches(legacy), "\(tag): 사유가 켜졌는데 점이 없다 \(combo.difference(from: legacy))")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: (c) 보이스오버

    @Test func 보이스오버_설명은_켜진_사유를_순서대로_잇는다() {
        typealias R = MenuBarDotReasons
        #expect(R().isEmpty && R().accessibilityDescription == nil)
        #expect(R(unreadMessages: true).accessibilityDescription == "새 메시지")
        #expect(R(gomokuInvite: true).accessibilityDescription == "오목 신청")
        #expect(R(updateAvailable: true).accessibilityDescription == "업데이트 있음")
        #expect(R(unreadMessages: true, gomokuInvite: true).accessibilityDescription == "새 메시지 · 오목 신청")
        #expect(R(unreadMessages: true, updateAvailable: true).accessibilityDescription == "새 메시지 · 업데이트 있음")
        #expect(R(gomokuInvite: true, updateAvailable: true).accessibilityDescription == "오목 신청 · 업데이트 있음")
        #expect(R(unreadMessages: true, gomokuInvite: true, updateAvailable: true).accessibilityDescription
                == "새 메시지 · 오목 신청 · 업데이트 있음")
        for reasons in [R(unreadMessages: true), R(gomokuInvite: true), R(updateAvailable: true)] {
            #expect(!reasons.isEmpty)
        }
        // 라벨의 파생값이 세 인자를 그대로 옮긴다.
        let label = MenuBarStatusLabel(
            snapshot: WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0), title: "오프",
            updateAvailable: false, hasUnreadMessages: true, hasGomokuInvite: true
        )
        #expect(label.dotReasons == R(unreadMessages: true, gomokuInvite: true, updateAvailable: false))
    }

    /// 상태바 버튼이 받는 이미지(점을 구운 새 인스턴스)에 사유 설명이 실리고, 캐시의 공유 인스턴스는 건드리지 않는다.
    @Test func 설명은_점을_구운_새_이미지에만_실린다() throws {
        let mascot = try #require(
            CheckMascotAssets.menuBarImage(for: .negative, characterID: CharacterCatalog.builtInAingID), "아잉 메뉴바 초상이 없다"
        )
        let before = mascot.accessibilityDescription
        let reasons = MenuBarDotReasons(unreadMessages: true, gomokuInvite: true)
        let image = MenuBarStatusLabel.describing(MenuBarStatusLabel.updateBadged(mascot), reasons)
        #expect(image !== mascot)
        #expect(image.accessibilityDescription == "새 메시지 · 오목 신청")
        #expect(mascot.accessibilityDescription == before, "공유 인스턴스의 보이스오버 문구를 덮어썼다")
        #expect(image.size == mascot.size, "점이 이미지 크기를 바꿨다 — 시계 글자가 떨린다")
        // 업데이트만이면 v0.3.20 문구 그대로다.
        #expect(MenuBarStatusLabel.describing(MenuBarStatusLabel.updateBadged(mascot), MenuBarDotReasons(updateAvailable: true))
            .accessibilityDescription == "업데이트 있음")
        let symbol = try #require(MenuBarStatusLabel.updateBadgedSymbol(
            named: MenuBarStatusFormatter.symbolName(for: WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0))
        ))
        #expect(MenuBarStatusLabel.describing(symbol, MenuBarDotReasons(gomokuInvite: true)).accessibilityDescription == "오목 신청")
    }

    // MARK: (d) 배선 · 그리는 방식(소스)

    @Test func 앱이_메시지와_오목_신청을_라벨에_넘기고_점은_이미지에_굽는다() throws {
        let app = try m2dSource("CheckApp.swift")
        #expect(app.components(separatedBy: "MenuBarStatusLabel(").count - 1 == 1)
        #expect(app.contains("updateAvailable: appDelegate.updateCheck.isUpdateAvailable"))
        #expect(app.contains("hasUnreadMessages: appDelegate.store.hasUnreadMessages"),
                "메뉴바 라벨이 안 읽은 메시지를 안 읽는다 — 팝오버를 안 여는 사람은 근무 밖 메시지를 모른다")
        #expect(app.contains("hasGomokuInvite: !appDelegate.store.gomoku.pendingIncomingInvites.isEmpty"),
                "메뉴바 라벨이 받은 오목 신청을 안 읽는다")

        let menu = try m2dSource("CheckMenuView.swift")
        let start = try #require(menu.range(of: "struct MenuBarStatusLabel: View {"))
        let end = try #require(menu.range(of: "\n}\n", range: start.upperBound..<menu.endIndex))
        let label = String(menu[start.lowerBound..<end.lowerBound])
        #expect(!label.contains(".overlay"), "점을 SwiftUI overlay 로 그린다 — 실제 메뉴바엔 안 뜬다")
        #expect(!label.contains(".accessibilityLabel"))
        #expect(label.contains("dotReasons.isEmpty ? mascot : Self.describing(Self.updateBadged(mascot), dotReasons)"),
                "캐릭터 아이콘의 점이 세 사유를 다 안 본다")
        #expect(label.contains("Image(nsImage: Self.describing(badged, dotReasons))"), "폴백 심볼의 설명이 사유를 안 싣는다")
        #expect(label.contains("} else if !dotReasons.isEmpty,"), "폴백 심볼 점이 업데이트만 본다")
        // 라벨이 시계를 읽지 않는다(신청 만료는 스토어 타이머가 내린다).
        for clock in ["Date()", "expiresAt", "displayNow"] {
            #expect(!label.contains(clock), "메뉴바 라벨이 '\(clock)' 를 읽는다")
        }
    }

    // MARK: (e) 레일 [콕찌르기] 칸의 안 읽음 점

    /// 안 읽은 메시지(서버 판정 — 이력의 isUnread)가 생기면 **레일 둘째 칸의 오른쪽 위 모서리**만 파란 점만큼 바뀐다.
    @Test(.gomokuDefaultsCleanup)
    func 안_읽은_메시지가_있으면_레일_콕찌르기_칸_모서리에_점이_생긴다() throws {
        let store = m2dMainScreenStore("m2-rail-dot")
        let plain = try m2dMenuBitmap(store)
        #expect(!store.hasUnreadMessages)

        store.messageHistory = [
            MessageHistoryEntry(id: "m1", peerUserID: MessageReadFixture.peerA, peerName: "민수", peerAvatarURL: nil,
                                body: "퇴근하셨어요?", createdAt: MessageReadFixture.now, isMine: false, isUnread: true)
        ]
        store.messageHistoryReadSnapshot = MessageHistoryReadSnapshot(serial: 1, serverOrder: ["m1": 0])
        #expect(store.hasUnreadMessages, "픽스처가 안 읽음을 만들지 못했다")
        let dotted = try m2dMenuBitmap(store)
        MiniGameSnapshots.save(dotted, name: "v0330-rail-unread-dot.png", sub: "messages")

        let diff = m2dDiff(dotted, plain)
        let poke = m2dRailButtonRect(1)
        #expect(diff.count > 20, "안 읽은 메시지가 생겼는데 팝오버 그림이 거의 안 바뀌었다(\(diff.count))")
        // 점 안쪽(지름 7 − 테 1.5 ≈ 반지름 2.75pt → 약 24pt² = 96px @2x)이 accent 다. 테(패널색)는 파랗지 않다.
        #expect(diff.blue >= 60, "바뀐 픽셀 중 accent 점이 \(diff.blue)px 뿐이다(전체 \(diff.count))")
        // 콕찌르기 칸 오른쪽 위 모서리(±6pt) 안에서만 바뀐다.
        let corner = CGRect(x: poke.maxX - 12, y: poke.minY - 6, width: 18, height: 18)
        #expect(corner.contains(diff.box), "점이 콕찌르기 칸 모서리(\(corner)) 밖(\(diff.box))까지 번졌다")

        // 대조: 읽음 처리(낙관 읽음)로 점이 꺼지면 그림도 원래대로다.
        store.messageOptimisticReads[MessageReadFixture.peerA] = MessageOptimisticRead(throughID: "m1", recordedSerial: 2)
        #expect(!store.hasUnreadMessages)
        #expect(m2dDiff(try m2dMenuBitmap(store), plain).count == 0, "안 읽음이 사라졌는데 레일 점이 남았다")
    }

    @Test func 레일_점은_잎에서_읽고_툴팁도_사실을_말한다() throws {
        #expect(MessageUnreadRailHelp.text(warns: false, hasUnreadMessages: false) == "콕 찌르기 · 메시지")
        #expect(MessageUnreadRailHelp.text(warns: false, hasUnreadMessages: true) == "콕 찌르기 · 메시지 — 안 읽은 메시지가 있어요")
        // 연결 경고가 이긴다(이 칸이 리얼타임 고장을 표면화하는 유일한 자리다).
        #expect(MessageUnreadRailHelp.text(warns: true, hasUnreadMessages: true) == PokeConnectionNotice.iconHelp)

        let menu = try m2dSource("CheckMenuView.swift")
        let leaf = try #require(menu.range(of: "private struct PokeEntryIconButton: View {"))
        let leafEnd = try #require(menu.range(of: "\n}\n", range: leaf.upperBound..<menu.endIndex))
        let leafBody = String(menu[leaf.upperBound..<leafEnd.lowerBound])
        #expect(leafBody.contains("store.hasUnreadMessages"))
        #expect(leafBody.contains("showsDot: unread"))
        // 레일 본체는 안 읽음을 모른다 — 메시지가 올 때마다 여섯 칸이 통째로 다시 그려지지 않게.
        let rail = try #require(menu.range(of: "struct CheckMenuSideRail: View {"))
        let railEnd = try #require(menu.range(of: "\n}\n", range: rail.upperBound..<menu.endIndex))
        #expect(!String(menu[rail.upperBound..<railEnd.lowerBound]).contains("hasUnreadMessages"))
    }
}

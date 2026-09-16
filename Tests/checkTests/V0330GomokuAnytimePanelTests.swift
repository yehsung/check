import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.30 M2(B2) — 오목 **화면**의 근무 조건 삭제 · 근무 밖 신청 배너.
//
// 서버(S3)가 gomoku_challenge·gomoku_respond 의 근무 조건을 지웠고 M1 이 스토어 게이트를 걷었다. 여기는 뷰 쪽 짝이다:
//  · 로비 [도전] 버튼이 비근무 상대에게도 켜진다(판정 표 + 픽셀 — 판정 함수만 재면 행이 그 함수를 안 쓰는 결함이 초록이다).
//  · 비근무 사용자의 신청·수락이 서버까지 간다(스토어 문 — 스텁 호출 수).
//  · 팝오버 배너: 비근무 사용자에게 뜨고 · **헤더 카드 아래**에 서고 · 남은 초와 [보기]가 그려지고 · 만료·처리되면 사라진다.
//  · 팝오버를 열면 받은 신청을 새로 받는다(60초 스로틀은 M1 스위트가 잰다 — 여기는 비근무에서도 불리는가).

private enum M2GRenderError: Error { case failed }

@MainActor
private func m2gBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw M2GRenderError.failed }
    return bitmap
}

/// 채운 accent(84,171,255) 계열 픽셀 수(사각형 pt 안).
private func m2gAccentPixels(_ bitmap: NSBitmapImageRep, in rect: CGRect) -> Int {
    guard let data = bitmap.bitmapData else { return -1 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh, Int(rect.maxY * 2))
    var hits = 0
    for y in y0..<y1 {
        for x in x0..<x1 {
            let o = y * bpr + x * spp
            let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
            if b >= 230 && r >= 60 && r <= 110 && g >= 150 && g <= 190 { hits += 1 }
        }
    }
    return hits
}

/// 두 같은 크기 그림에서 처음으로 달라지는 행(pt). 같으면 nil.
private func m2gFirstDifferentRow(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> CGFloat? {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData else { return nil }
    let width = min(lhs.pixelsWide, rhs.pixelsWide), height = min(lhs.pixelsHigh, rhs.pixelsHigh)
    for y in 0..<height {
        for x in 0..<width {
            let oa = y * lhs.bytesPerRow + x * lhs.samplesPerPixel
            let ob = y * rhs.bytesPerRow + x * rhs.samplesPerPixel
            if abs(Int(a[oa]) - Int(b[ob])) + abs(Int(a[oa + 1]) - Int(b[ob + 1])) + abs(Int(a[oa + 2]) - Int(b[ob + 2])) > 24 {
                return CGFloat(y) / 2
            }
        }
    }
    return nil
}

private func m2gSource(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("\(CheckCoreSourceLayout.directory(for: name))/\(name)")
    return m2gStripComments(try String(contentsOf: url, encoding: .utf8))
}

private func m2gStripComments(_ source: String) -> String {
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

private func m2gRegion(_ source: String, from start: String, to end: String) -> String? {
    guard let head = source.range(of: start) else { return nil }
    let tail = source.range(of: end, range: head.upperBound..<source.endIndex)?.lowerBound ?? source.endIndex
    return String(source[head.upperBound..<tail])
}

private func m2gUser(_ name: String, _ suffix: Int, working: Bool, capable: Bool = true, inMatch: Bool = false) -> GomokuUser {
    GomokuUser(
        id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))",
        displayName: name, avatarURL: nil, characterID: "shiba",
        isWorking: working, isCapable: capable, inMatch: inMatch
    )
}

private let m2gMe = GomokuPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

/// 메인 화면(로그인 + 팀 확정) · **비근무** 스토어.
@MainActor
private func m2gMainScreenStore(_ label: String) -> (store: WorkTimerStore, host: String) {
    let made = makeMessageReadStore(label)
    let store = made.store
    store.isMenuPresented = true
    store.displayNow = MessageReadFixture.now
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
    store.teamMembers = [
        TeamMemberStatus(id: MessageReadFixture.me, name: "영식", status: .offWork, updatedAt: nil,
                         currentSessionStartedAt: nil, weeklyDurationSeconds: 7_200)
    ]
    return made
}

@MainActor
private func m2gMenu(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
    try m2gBitmap(CheckMenuView(store: store, previewClipsOverflowList: true, previewPlainTextEditors: true))
}

@MainActor
@Suite("V0330GomokuAnytimePanel")
struct V0330GomokuAnytimePanelTests {
    // MARK: [도전] 활성 조건

    @Test(.gomokuDefaultsCleanup)
    func 도전_버튼_활성_조건_표에는_근무가_없다() {
        let store = GomokuStore()
        let free = m2gUser("민수", 1, working: false)
        #expect(GomokuChallengeGate.isEnabled(user: free, store: store), "근무 안 하는 상대에게 [도전]이 꺼졌다")
        #expect(GomokuChallengeGate.isEnabled(user: m2gUser("준호", 2, working: true), store: store))
        // 남는 조건들 — 전부 여전히 끈다.
        #expect(!GomokuChallengeGate.isEnabled(user: m2gUser("옛버전", 3, working: false, capable: false), store: store))
        #expect(!GomokuChallengeGate.isEnabled(user: m2gUser("대국중", 4, working: false, inMatch: true), store: store))
        store.outgoing = GomokuInvite(id: "out-1", peer: free, stake: 3, expiresAt: Date().addingTimeInterval(40))
        #expect(!GomokuChallengeGate.isEnabled(user: free, store: store), "보낸 신청이 떠 있는데 [도전]이 켜졌다")
        store.outgoing = nil
        store.isBusy = true
        #expect(!GomokuChallengeGate.isEnabled(user: free, store: store), "왕복 중인데 [도전]이 켜졌다")
        store.isBusy = false
        store.match = GomokuMatchState(
            id: "m1", stake: 3, myColor: .black, opponent: free, board: GomokuBoard(), lastMove: nil, moveCount: 0,
            turn: .black, deadline: nil, isFinished: false, outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false
        )
        #expect(!GomokuChallengeGate.isEnabled(user: free, store: store), "대국 중인데 [도전]이 켜졌다")
    }

    /// 로비 행이 판정을 **실제로** 쓴다: 비근무 상대 행의 [도전]은 채운 accent 버튼이고, 신청이 성립할 수 없는 상대
    /// (대국 중) 행은 테두리뿐이다. 두 그림의 [도전] 자리 accent 픽셀 수가 확실히 갈린다.
    @Test(.gomokuDefaultsCleanup)
    func 로비의_비근무_상대_행에서_도전_버튼이_켜져_그려진다() throws {
        func lobby(_ user: GomokuUser) throws -> NSBitmapImageRep {
            let store = GomokuStore()
            store.users = [user]
            store.hasLoadedLobby = true
            store.rubyBalance = 20
            return try m2gBitmap(GomokuPanel(store: store, me: { m2gMe }, clipsOverflowInsteadOfScroll: true))
        }
        let enabled = try lobby(m2gUser("민수", 11, working: false))
        let disabled = try lobby(m2gUser("민수", 11, working: false, inMatch: true))
        MiniGameSnapshots.save(enabled, name: "v0330-lobby-offwork-challenge.png", sub: "gomoku")
        let list = CGRect(
            x: GomokuWindowLayout.contentPadding,
            y: GomokuWindowLayout.contentPadding + GomokuWindowLayout.headerHeight + GomokuWindowLayout.headerSpacing,
            width: GomokuWindowLayout.lobbyListWidth, height: 140
        )
        let on = m2gAccentPixels(enabled, in: list)
        let off = m2gAccentPixels(disabled, in: list)
        #expect(on > 1000, "비근무 상대 행에 채운 [도전] 버튼이 없다(accent \(on)px)")
        #expect(on > off * 3, "켜진 [도전]과 꺼진 [도전]이 픽셀로 안 갈린다(\(on) vs \(off))")

        let panel = try m2gSource("GomokuPanel.swift")
        let row = try #require(m2gRegion(panel, from: "private struct GomokuOpponentRow: View {", to: "// MARK: - 로비: 오른쪽 열"))
        #expect(row.contains("GomokuChallengeGate.isEnabled(user: user, store: store)"))
        #expect(row.contains("isEnabled: canChallenge"))
        let gate = try #require(m2gRegion(panel, from: "enum GomokuChallengeGate {", to: "private struct GomokuOpponentRow: View {"))
        #expect(!gate.contains("isWorking"), "[도전] 활성 조건에 근무가 되살아났다")
        // 로비 안내가 옛 규칙을 말하지 않는다.
        #expect(!GomokuText.lobbyCaption.contains("근무 중일 때"))
        for word in ["서버", "로컬", "계정", "실시간", "status", "null"] {
            #expect(!GomokuText.lobbyCaption.contains(word) && !GomokuText.viewInvite.contains(word)
                    && !GomokuText.viewInviteHelp.contains(word))
        }
        // 정렬의 근무 우선은 그대로다(보기 좋게 두는 용도).
        #expect(GomokuStore.sortedForLobby([m2gUser("가", 1, working: false), m2gUser("나", 2, working: true)]).first?.displayName == "나")
    }

    // MARK: 신청 · 수락이 서버까지

    /// 대조군 실험(스토어 문): **비근무** 사용자의 신청(판돈 창이 부르는 `challenge(userID:)`)과 수락(배너·카드가 부르는
    /// `respond`)이 각각 RPC 1회로 나간다. 옛 뷰에서는 [도전]이 꺼져 이 문에 닿지 못했다(위 판정 표 · 픽셀 테스트가 그 짝).
    @Test(.gomokuDefaultsCleanup)
    func 비근무_사용자의_신청과_수락이_서버까지_간다() async {
        let (store, host) = makeMessageReadStore("m2-gomoku-rpc")
        #expect(store.startedAt == nil)
        let gomoku = store.gomoku
        let target = m2gUser("민수", 21, working: false)
        gomoku.users = [target]
        #expect(GomokuChallengeGate.isEnabled(user: target, store: gomoku))
        await gomoku.challenge(userID: target.id)
        #expect(MessageReadStubProtocol.count(host: host, rpc: "gomoku_challenge") == 1)
        #expect(gomoku.notice != GomokuNoticeText.challenge(.notWorking), "비근무 안내가 떴다 — 신청 선게이트가 남아 있다")

        await gomoku.respond(inviteID: "11111111-2222-3333-4444-555555555555", accept: true)
        #expect(MessageReadStubProtocol.count(host: host, rpc: "gomoku_respond") == 1)
    }

    /// 팝오버를 여는 순간(비근무) 받은 신청을 새로 받는다 — 배너·메뉴바 점의 신선도가 이 계기에 기댄다.
    @Test(.gomokuDefaultsCleanup)
    func 비근무_사용자가_팝오버를_열면_받은_신청을_새로_받는다() async {
        let (store, host) = makeMessageReadStore("m2-gomoku-menu-open")
        #expect(store.startedAt == nil)
        store.setMenuPresented(true)
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "gomoku_inbox") >= 1 }
        #expect(MessageReadStubProtocol.count(host: host, rpc: "gomoku_inbox") == 1)
        store.setMenuPresented(false)
    }

    // MARK: 팝오버 배너

    /// 비근무 메인 화면에 받은 신청이 있으면 배너가 **헤더 카드 아래**에 선다: 팝오버가 예산만큼 자라고, 그림이 처음 갈리는
    /// 줄이 최상단(12pt)이 아니라 헤더 카드 밑이다. 만료되면(스토어 타이머가 걷는 경로) 그림이 배너 전과 바이트가 같다.
    @Test(.gomokuDefaultsCleanup)
    func 비근무_팝오버에_헤더_아래_배너가_서고_만료되면_사라진다() throws {
        let store = m2gMainScreenStore("m2-gomoku-banner").store
        let plain = try m2gMenu(store)

        let invite = GomokuInvite(id: "in-1", peer: m2gUser("민수", 31, working: true), stake: 5,
                                  expiresAt: Date().addingTimeInterval(45))
        store.gomoku.incoming = [invite]
        #expect(!store.gomoku.pendingIncomingInvites.isEmpty)
        let banner = try m2gMenu(store)
        MiniGameSnapshots.save(banner, name: "v0330-popover-offwork-invite-banner.png", sub: "gomoku")

        let grown = Double(banner.pixelsHigh - plain.pixelsHigh) / 2
        #expect(abs(grown - Double(CheckMenuView.gomokuInviteBannerHeight)) <= 1,
                "배너가 팝오버를 \(grown)pt 늘렸다(예산 \(CheckMenuView.gomokuInviteBannerHeight)pt) — 비근무라 안 그려졌거나 예산이 틀렸다")
        #expect(Double(banner.pixelsHigh) / 2 <= 700)
        let firstDiff = try #require(m2gFirstDifferentRow(banner, plain), "배너를 얹었는데 그림이 같다")
        #expect(firstDiff > 60, "배너가 헤더 카드 위(\(firstDiff)pt)에 섰다 — 자리는 헤더 카드 아래다")

        // 만료: 스토어가 만료 시각에 걷는 경로 그대로.
        store.gomoku.pruneExpiredInvites(now: invite.expiresAt.addingTimeInterval(1))
        #expect(store.gomoku.pendingIncomingInvites.isEmpty)
        // 바이트가 아니라 **눈에 보이는 차이**로 잰다: 같은 스토어를 레이아웃이 한 번 바뀐 뒤 다시 그리면 안티에일리어싱이
        // 채널 합 24 이하로 흔들린다(실측 — 크기는 같고 문턱을 넘는 픽셀은 0). 배너가 남으면 크기부터 다르다.
        let expired = try m2gMenu(store)
        #expect(expired.pixelsHigh == plain.pixelsHigh && m2gFirstDifferentRow(expired, plain) == nil, "만료된 신청의 배너가 남았다")

        // 처리(수락·거절 성공은 incoming 에서 뺀다): 다시 세웠다가 비우면 사라진다.
        store.gomoku.incoming = [GomokuInvite(id: "in-2", peer: invite.peer, stake: 3, expiresAt: Date().addingTimeInterval(50))]
        #expect(try m2gMenu(store).pixelsHigh > plain.pixelsHigh)
        store.gomoku.incoming = []
        let handled = try m2gMenu(store)
        #expect(handled.pixelsHigh == plain.pixelsHigh && m2gFirstDifferentRow(handled, plain) == nil, "처리된 신청의 배너가 남았다")
    }

    /// 무소속 화면(헤더 카드 없음)에도 배너가 선다 — 오목 상대는 앱 사용자 전체다.
    @Test(.gomokuDefaultsCleanup)
    func 무소속_화면에도_배너가_선다() throws {
        let store = makeMessageReadStore("m2-gomoku-teamless").store
        store.isMenuPresented = true
        #expect(store.isTeamless)
        let plain = try m2gMenu(store)
        store.gomoku.incoming = [GomokuInvite(id: "in-3", peer: m2gUser("민수", 41, working: false), stake: 10,
                                              expiresAt: Date().addingTimeInterval(40))]
        let banner = try m2gMenu(store)
        #expect(abs(Double(banner.pixelsHigh - plain.pixelsHigh) / 2 - Double(CheckMenuView.gomokuInviteBannerHeight)) <= 1)
    }

    /// 배너가 **남은 초**와 **[보기]**를 그린다(픽셀). 남은 초가 다르면 그림이 다르고, [보기] 문이 없으면 버튼이 없다.
    @Test func 배너는_남은_초와_보기_버튼을_그린다() throws {
        let peer = m2gUser("민수", 51, working: false)
        func banner(expiresIn seconds: TimeInterval, open: Bool) throws -> NSBitmapImageRep {
            let invite = GomokuInvite(id: "in-9", peer: peer, stake: 5, expiresAt: Date().addingTimeInterval(seconds))
            return try m2gBitmap(
                GomokuInviteBanner(invite: invite, onAccept: {}, onDecline: {}, onOpen: open ? {} : nil)
                    .frame(width: CheckMenuView.contentColumnWidth)
                    .background(CheckTheme.background)
            )
        }
        let long = try banner(expiresIn: 48.5, open: true)
        let short = try banner(expiresIn: 12.5, open: true)
        let noOpen = try banner(expiresIn: 48.5, open: false)
        MiniGameSnapshots.save(long, name: "v0330-invite-banner.png", sub: "gomoku")
        #expect(m2gFirstDifferentRow(long, short) != nil, "남은 초가 달라도 배너 그림이 같다 — 초가 안 그려진다")
        #expect(m2gFirstDifferentRow(long, noOpen) != nil, "[보기] 버튼이 안 그려진다")
        // 대조군: 같은 조건 두 번은 눈에 보이는 차이가 없다(위 두 차이는 초·버튼에서만 온다).
        #expect(m2gFirstDifferentRow(long, try banner(expiresIn: 48.5, open: true)) == nil)
        #expect(long.pixelsHigh == noOpen.pixelsHigh, "[보기]가 배너 높이를 바꿨다 — 팝오버 예산이 어긋난다")
        #expect(Double(long.pixelsHigh) / 2 <= Double(CheckMenuView.gomokuInviteBannerHeight))
    }

    /// 배선(소스): 팝오버가 [보기]를 창 열기 → 팝오버 닫기 순서로 잇고, 배너는 헤더 카드 뒤에 서며, 초는 잎에서만 읽는다.
    @Test func 배너_배선과_시계_격리() throws {
        let menu = try m2gSource("CheckMenuView.swift")
        let open = try #require(m2gRegion(menu, from: "private func openGomokuInvite(_ invite: GomokuInvite) {", to: "\n    }\n"))
        let window = try #require(open.range(of: "store.gomoku.openWindow(focusMatchID: invite.id)"), "[보기]가 그 신청으로 창을 안 연다")
        let dismiss = try #require(open.range(of: "WindowTopAnchor.dismissMenuPopover()"))
        #expect(window.lowerBound < dismiss.lowerBound, "팝오버를 먼저 닫는다 — 창이 뜨기 전 한 틱 동안 표면이 없다")
        #expect(menu.contains("onOpen: { openGomokuInvite(invite) }"))
        // 배너는 최상단이 아니라 헤더 카드 아래다.
        let column = try #require(m2gRegion(menu, from: "private var bodyColumn: some View {", to: "private var content: some View {"))
        #expect(!column.contains("GomokuInviteBanner("), "배너가 아직 팝오버 최상단에 있다")
        let header = try #require(menu.range(of: "HeaderCard(\n"))
        let afterHeader = try #require(menu.range(of: "gomokuInviteBanner\n", range: header.upperBound..<menu.endIndex))
        let tokenRow = try #require(menu.range(of: "if showsTokenUsageRow {", range: header.upperBound..<menu.endIndex))
        #expect(afterHeader.lowerBound < tokenRow.lowerBound, "배너가 헤더 카드 바로 아래가 아니다")
        #expect(!menu.contains("expiresAt"), "팝오버가 신청 만료 시각을 직접 비교한다")
        // 배너 판정은 여전히 topBanner 하나다(한 번에 하나 예산).
        let property = try #require(m2gRegion(menu, from: "private var gomokuInviteBanner: some View {", to: "\n    }\n"))
        #expect(property.contains("if topBanner == .gomokuInvite, let invite = gomokuBannerInvite {"))
        for gate in ["isWorking", "startedAt"] {
            #expect(!property.contains(gate), "배너가 '\(gate)' 를 본다 — 근무 밖 신청이 안 보인다")
        }
        #expect(menu.contains("if store.isSignedIn, gomokuBannerInvite != nil { return .gomokuInvite }"), "배너 순위 판정에 조건이 붙었다")

        let panel = try m2gSource("GomokuPanel.swift")
        let banner = try #require(m2gRegion(panel, from: "struct GomokuInviteBanner: View {", to: "private struct GomokuActionButton: View {"))
        #expect(banner.contains("GomokuInviteBannerCountdown(invite: invite)"))
        for clock in ["TimelineView", "expiresAt", "Date(", "displayNow"] {
            #expect(!banner.contains(clock), "배너 본체가 '\(clock)' 를 읽는다 — 팝오버가 매초 다시 그려진다")
        }
        let leaf = try #require(m2gRegion(panel, from: "struct GomokuInviteBannerCountdown: View {", to: "private struct GomokuNoticeLine: View {"))
        #expect(leaf.contains("GomokuCountdownText(expiresAt: invite.expiresAt, isLive: controlActiveState != .inactive)"),
                "초 잎이 닫힌 팝오버에서도 돈다(또는 스토어 시계를 읽어 비근무에서 멈춘다)")
    }
}

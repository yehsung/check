import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 뒤집기(내부 이름 reversi) — **공용 접점 배선**(FLIP/SPEC.md §4.6 체크리스트 #1~#19 · #21~#23, §6.3 T 줄).
// 스토어·창은 다른 갈래(C·U)가 채웠다. 여기서는 "그 문이 공용 파일에 꽂혀 있는가"를 소스 계약(주석 걷기 → 공백 접기 →
// 글자 그대로)으로 재고, 소스 계약이 모양만 잰다는 한계(메모리 tests-measure-shape-not-result)를 메우려고 **부르는 자리의 결과**를
// 같이 잰다 — 링이 실제로 가르는 효과 · 실제 `WorkTimerStore` 의 차단 거울 · 배너 미룸 판정 · 미션 아이콘 · 말풍선 큐 · 팝오버 높이.
// 결과 단언마다 **값 하나만 바꾼 기준선**을 함께 둔다(같은 입력이면 영원히 초록이다 — 메모리 comparison-baseline-must-differ).
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).
// 버전이 정해지면 파일 이름과 `@Suite` 이름을 함께 `V03NN…` 으로 바꾼다(SPEC §1).

private let rwtT0 = Date(timeIntervalSince1970: 1_800_000_000)
private let rwtMe = "00000000-0000-0000-0000-0000000000a1"
private let rwtRival = ReversiUser(id: "00000000-0000-0000-0000-0000000000b2", displayName: "민수", characterID: "fox",
                                   isWorking: true)

private func rwtSubscribedLink() -> RealtimeLink {
    var link = RealtimeLink(transportAvailable: true)
    _ = link.apply(.signedIn(accessToken: "tok"), now: rwtT0, jitter: { $0 })
    _ = link.apply(.transport(.joined), now: rwtT0, jitter: { $0 })
    return link
}

private func rwtCollapsed(_ source: String) -> String {
    source.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func rwtCount(_ needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

/// Sources/check(+CheckCore) 파일을 주석 걷고 공백 접어 읽는다.
private func rwtMac(_ name: String) throws -> String {
    rwtCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source(name)))
}

/// 저장소 뿌리(이 파일 기준 세 단계 위).
private func rwtRepoRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

/// 폰 러너는 Sources/CheckMobileKit 에 산다(맥 시험이 모바일 세션 파일을 글자로만 읽는다 — 컴파일 의존 없음).
private func rwtPhoneRunner() throws -> String {
    let url = rwtRepoRoot().appendingPathComponent("Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift")
    return rwtCollapsed(V0317ShopTests.stripped(try String(contentsOf: url, encoding: .utf8)))
}

/// `start` 부터 `end` 앞까지(둘 다 없으면 nil).
private func rwtBetween(_ source: String, _ start: String, _ end: String) -> String? {
    guard let head = source.range(of: start),
          let tail = source.range(of: end, range: head.upperBound..<source.endIndex) else { return nil }
    return String(source[head.lowerBound..<tail.lowerBound])
}

// MARK: 서버 초안(리버시 전용 변수 — SPEC §6.2)

/// 리버시 마이그레이션 한 장의 위치. 공용 `CHECK_MIGRATIONS_DIR` 가 **아니다**(그 변수는 체인 전체를 읽는 시험 수십 개가 같이 본다).
private func rwtMigrationURL() -> URL? {
    let fileManager = FileManager.default
    if let path = ProcessInfo.processInfo.environment["REVERSI_MIGRATION_SQL"], !path.isEmpty {
        return fileManager.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
    let candidate = rwtRepoRoot().appendingPathComponent("supabase/migrations/20261108200000_reversi.sql")
    return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
}

private let rwtMigrationRequired = ProcessInfo.processInfo.environment["REVERSI_REQUIRE_MIGRATION"] == "1"
/// 마이그레이션을 읽는 시험이 돌아야 하는가 — 파일이 있거나, 없으면 빨개져야 할 때(REQUIRE).
private let rwtMigrationGate = rwtMigrationURL() != nil || rwtMigrationRequired

/// `perform realtime.send(<payload>, '<이벤트>', …)` 의 이벤트 글자들. payload 괄호는 짝을 맞춰 건넌다.
/// `perform` 머리만 센다 — 사후 단언의 함수 이름 목록(`'realtime.send(jsonb,…)'`)과 `comment on` 문자열 안의 설명은 호출이 아니다.
private func rwtRealtimeSendEvents(_ sql: String) -> [String] {
    let chars = Array(sql)
    let needle = Array("perform realtime.send(")
    var events: [String] = []
    var i = 0
    while i + needle.count <= chars.count {
        guard Array(chars[i..<(i + needle.count)]) == needle else { i += 1; continue }
        var j = i + needle.count
        var depth = 1
        // 첫 인자(payload) 끝의 쉼표까지 — 괄호 깊이 1 에서 만나는 첫 쉼표.
        while j < chars.count {
            if chars[j] == "(" { depth += 1 }
            if chars[j] == ")" { depth -= 1 }
            if chars[j] == ",", depth == 1 { break }
            j += 1
        }
        j += 1
        while j < chars.count, chars[j].isWhitespace { j += 1 }
        guard j < chars.count, chars[j] == "'" else { events.append("<문자열 아님>"); i = j; continue }
        var k = j + 1
        while k < chars.count, chars[k] != "'" { k += 1 }
        events.append(String(chars[(j + 1)..<min(k, chars.count)]))
        i = k
    }
    return events
}

// MARK: 화면 조립

@MainActor
private func rwtDefaults(_ name: String) -> UserDefaults {
    let path = CheckTestScratch.suitePath(named: name)
    let defaults = UserDefaults(suiteName: path)!
    defaults.removePersistentDomain(forName: path)
    return defaults
}

@MainActor
private func rwtStore(_ name: String) -> WorkTimerStore {
    WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"], defaults: rwtDefaults(name),
                   workspaceNotifications: nil)
}

/// 팝오버 높이를 재는 스토어. `teamless` 면 무소속 화면(헤더 카드 없이 배너가 맨 위에 선다).
@MainActor
private func rwtMenuStore(teamless: Bool) -> WorkTimerStore {
    let store = rwtStore(teamless ? "v03xx-reversi-wiring-menu-teamless" : "v03xx-reversi-wiring-menu")
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: rwtMe)
    if !teamless {
        store.currentTeamID = "11111111-1111-1111-1111-111111111111"
        store.teamName = "아잉팀"
        // 팀원 셋 — 본문이 레일보다 길게 시작해야 배너 높이가 창 높이 차로 그대로 드러난다(V0360 과 같은 이유).
        store.teamMembers = (0..<3).map { index in
            TeamMemberStatus(id: "00000000-0000-0000-0000-0000000000c\(index)", name: "멤버\(index)", status: .offWork,
                             updatedAt: nil, currentSessionStartedAt: nil, weeklyDurationSeconds: 3_600)
        }
    }
    store.isMenuPresented = true
    return store
}

@MainActor
private func rwtOverlay() -> (ReactionEngine, CheckOverlayController, WorkTimerStore) {
    let store = rwtStore("v03xx-reversi-wiring-overlay")
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 900_000) })
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: rwtDefaults("v03xx-reversi-wiring-overlay"), workspaceNotifications: nil)
    return (engine, controller, store)
}

private func rwtInvite(_ id: String, expiresIn seconds: TimeInterval = 50) -> ReversiInvite {
    ReversiInvite(id: id, peer: rwtRival, stake: 5, expiresAt: Date().addingTimeInterval(seconds))
}

private enum RWTError: Error { case render }

@MainActor
private func rwtBitmap(_ view: some View) throws -> NSBitmapImageRep {
    guard let bitmap = CheckRenderSettle.bitmap(view.fixedSize(), scale: 2) else { throw RWTError.render }
    return bitmap
}

@MainActor
@Suite(.serialized)
struct V03xxReversiWiringTests {
    // MARK: #1~#3 링

    /// 없으면: 'reversi' 가 '모르는 이름' 과 같은 갈래로 떨어져 **수마다 take_pokes 가 한 번씩 더** 나가고 소켓은 아잉 뒤집기
    /// 상태를 한 번도 당기지 않는다(스토어 시험은 초인종을 직접 부르므로 초록이다). 서버 이벤트 글자와 갈려도 같은 결함이다.
    @Test
    func theReversiRingIsItsOwnBranchAndNotATakePokesDrain() throws {
        #expect(RealtimeLinkConstants.reversiBroadcastEvent == "reversi")
        var link = rwtSubscribedLink()
        #expect(link.apply(.transport(.broadcast(event: "reversi")), now: rwtT0 + 1, jitter: { $0 }) == [.reversiSignal])
        // 아잉 뒤집기 신호도 소켓이 살아 있다는 증거다(좀비 판정 시계를 민다).
        #expect(link.state == .subscribed(since: rwtT0, lastHeardAt: rwtT0 + 1))
        // ★ 기준선이 갈린다: 문자 그대로만 가른다 — 대문자는 모르는 이름이라 예전 그대로 drain 이다.
        #expect(link.apply(.transport(.broadcast(event: "REVERSI")), now: rwtT0 + 2, jitter: { $0 }) == [.drain])
        // 이웃 갈래는 그대로다(새 줄이 앞을 가로채지 않는다).
        let rummy = link.apply(.transport(.broadcast(event: "rummy")), now: rwtT0 + 3, jitter: { $0 })
        let chess = link.apply(.transport(.broadcast(event: "chess")), now: rwtT0 + 4, jitter: { $0 })
        let unknown = link.apply(.transport(.broadcast(event: "모르는이름")), now: rwtT0 + 5, jitter: { $0 })
        #expect(rummy == [.rummySignal] && chess == [.chessSignal] && unknown == [.drain])
        #expect(Set([[RealtimeEffect.reversiSignal], rummy, chess, unknown].map { "\($0)" }).count == 4)
        // 구독 전에는 아무것도 시키지 않는다.
        var connecting = RealtimeLink(transportAvailable: true)
        _ = connecting.apply(.signedIn(accessToken: "tok"), now: rwtT0, jitter: { $0 })
        #expect(connecting.apply(.transport(.broadcast(event: "reversi")), now: rwtT0 + 1, jitter: { $0 }) == [])
    }

    /// 없으면: 새 줄이 큐브·테트리스·오목·체스 한 문장 **사이**에 끼어 V0369·V0360·V0327 계약을 깨거나, drain 기본값 **뒤**에
    /// 서서 영영 닿지 않는다(이름 분기가 죽은 코드 — 컴파일은 초록).
    @Test
    func theReversiRouteStandsInFrontOfTheRummySentence() throws {
        let link = try rwtMac("RealtimeLink.swift")
        #expect(link.contains("package static let reversiBroadcastEvent = \"reversi\""))
        #expect(link.contains("case rummySignal case reversiSignal"), "효과 case 가 큐브 뒤에 없다")
        let sentence: String = [
            "if event == RealtimeLinkConstants.reversiBroadcastEvent { return [.reversiSignal] } ",
            "if event == RealtimeLinkConstants.rummyBroadcastEvent { return [.rummySignal] } ",
            "if event == RealtimeLinkConstants.tetrisBroadcastEvent { return [.tetrisSignal] } ",
            "if event == RealtimeLinkConstants.gomokuBroadcastEvent { return [.gomokuSignal] } ",
            "if event == RealtimeLinkConstants.chessBroadcastEvent { return [.chessSignal] } ",
            "return [.drain]",
        ].joined()
        #expect(link.contains(sentence))
    }

    /// 없으면: 서버 초인종(`reversi__ring`)과 클라 상수의 글자가 갈려도 스텁 시험은 초록이다 — 스텁은 클라 상수를 그대로 보낸다
    /// (메모리 stub-tests-hide-roundtrip-bugs). 실제로는 모든 수가 drain 으로 떨어진다.
    @Test(.enabled(if: rwtMigrationGate))
    func theServerDraftRingsTheSameEventName() throws {
        guard let url = rwtMigrationURL() else {
            Issue.record("""
                리버시 마이그레이션이 없다(REVERSI_MIGRATION_SQL=\(ProcessInfo.processInfo.environment["REVERSI_MIGRATION_SQL"] ?? "(없음)")) — \
                REVERSI_REQUIRE_MIGRATION=1 이라 건너뛰지 않는다
                """)
            return
        }
        let sql = try String(contentsOf: url, encoding: .utf8)
        let events = rwtRealtimeSendEvents(sql)
        #expect(!events.isEmpty, "마이그레이션에 `perform realtime.send(` 호출이 없다 — 초인종이 안 울린다")
        for event in events {
            #expect(event == RealtimeLinkConstants.reversiBroadcastEvent,
                    "서버가 '\(event)' 로 울리는데 클라는 '\(RealtimeLinkConstants.reversiBroadcastEvent)' 만 가른다")
        }
        // ★ 기준선이 갈린다: 같은 꼴에서 글자만 다른 호출은 다른 이벤트로 읽힌다(파서가 무엇이든 'reversi' 를 돌려주지 않는다).
        let skewed = rwtRealtimeSendEvents("perform realtime.send(jsonb_build_object('v', 1, 'm', x), 'Reversi', t, true);")
        #expect(skewed == ["Reversi"] && skewed != [RealtimeLinkConstants.reversiBroadcastEvent])
    }

    // MARK: #4 폰 러너(모바일 세션 파일 — 폰 1.0.17 부터 잇는다)

    /// 없으면: 폰 러너의 exhaustive switch 가 컴파일되지 않거나(가지 없음 — `#if os(iOS)` 밖이라 맥 빌드도 깨진다), `.drain` 으로
    /// 떨어뜨리면 같은 계정의 맥이 판을 하는 동안 수마다 폰이 **메시지** 요약·이력을 한 번씩 더 조회한다. 가지가 비면(1.0.16 까지의 `break`)
    /// 폰 판이 신청·수락·상대 수를 다음 폴링까지 모른다 — 한 수 30초라 그 사이 서버가 대신 둔다.
    /// 폰 1.0.17(대표 답 #d_DdwzmxPClGqk "다 넣기")부터 `reversi?.handleSignal()` 로 잇고 조인 따라잡기에 `reversi?.realtimeDidJoin()` 을 더한다.
    /// 요청 건수로 재는 못은 `GamesReversiWiringTests`(폰 스위트)에 있다.
    @Test
    func thePhoneRunnerWiresTheReversiBranchToTheStore() throws {
        let runner = try rwtPhoneRunner()
        #expect(rwtCount("case .reversiSignal", in: runner) == 1, "폰 러너에 아잉 뒤집기 가지가 하나가 아니다")
        let branch = try #require(rwtBetween(runner, "case .reversiSignal:", "case .megaphoneSignal:"))
        #expect(branch == "case .reversiSignal: reversi?.handleSignal() ", "폰 러너의 아잉 뒤집기 가지가 스토어로 안 간다: \(branch)")
        #expect(!branch.contains("requestDrain") && !branch.contains("requestMessageActivity"), "아잉 뒤집기 초인종이 메시지 조회로 샌다")
        #expect(runner.contains("rummy?.realtimeDidJoin() reversi?.realtimeDidJoin()"), "조인 따라잡기에 아잉 뒤집기가 없다(큐브 바로 뒤)")
        #expect(runner.contains("@ObservationIgnored package weak var reversi: ReversiStore?"), "러너가 스토어를 약한 참조로 들지 않는다")
        // ★ 기준선: 큐브 가지는 같은 읽기로 '잇는 가지'다 · 체스 가지는 여전히 비어 있다(같은 읽기가 빈 가지를 알아본다).
        let rummy = try #require(rwtBetween(runner, "case .rummySignal:", "case .reversiSignal:"))
        #expect(rummy.contains("rummy?.handleSignal()"))
        let chess = try #require(rwtBetween(runner, "case .chessSignal:", "case .tetrisSignal:"))
        #expect(chess == "case .chessSignal: break ", "기준선이 안 갈린다 — 빈 가지 읽기가 바뀌었다: \(chess)")
    }

    // MARK: #5~#12 맥 소유 배선(WorkTimerStore · WorkTimerStoreRealtime)

    /// 없으면: 소유자가 `reset()` 을 빠뜨리면 다음 사람이 앞 계정의 판·신청을 보고, 팝오버 계기를 빠뜨리면 창을 안 연 사람에게
    /// 신청(TTL 60초)이 안 닿고, 결과 계기를 빠뜨리면 일일 미션이 다음 박자까지 안 오른다 — 스토어 시험은 전부 초록이다.
    @Test
    func theMacOwnerWiresTheReversiStoreAfterRummy() throws {
        let owner = try rwtMac("WorkTimerStore.swift")
        #expect(owner.contains("let reversi: ReversiStore"))
        #expect(owner.contains("self.rummy = RummyStore() self.reversi = ReversiStore()"))
        #expect(owner.contains("rummy.attach(host: self) reversi.attach(host: self)"))
        #expect(rwtCount("reversi.reset()", in: owner) == 2, "로그아웃·계정 전환 두 길에서 모두 내려야 한다")
        #expect(rwtCount("rummy.reset() reversi.reset()", in: owner) == 2, "두 길 모두 큐브 바로 뒤가 아니다")
        let mirror: String = [
            "rummy.setHiddenPeers(Set(blockHiddenPeerIDs.compactMap { UUID(uuidString: $0) })) ",
            "if reversi.hiddenPeerIDs != blockHiddenPeerIDs { reversi.hiddenPeerIDs = blockHiddenPeerIDs }",
        ].joined()
        #expect(owner.contains(mirror), "차단 거울에 아잉 뒤집기가 없다")
        #expect(owner.contains("rummy.refreshLobbyIfStale() reversi.refreshLobbyIfStale()"), "팝오버 열기 계기에 아잉 뒤집기가 없다")
        #expect(owner.contains(
            "reversi.onMatchFinished = { [weak self] in self?.refreshAchievementsAfterGameResult(game: \"reversi\") }"))
        // 그 게임 이름이 일일 미션 키(서버 `daily_reversi`)의 꼬리다.
        #expect(DailyMissionStatus.key(game: "reversi") == "daily_reversi")

        let realtime = try rwtMac("WorkTimerStoreRealtime.swift")
        #expect(realtime.contains("case .reversiSignal: reversi.handleSignal()"),
                "아잉 뒤집기 신호 가지가 없다 — 초인종마다 take_pokes 가 샌다")
        #expect(realtime.contains("rummy.realtimeDidJoin() reversi.realtimeDidJoin()"), "조인 직후 따라잡기에 아잉 뒤집기가 없다")
        // 깨어남은 **별도 블록**(V0327 계약이 오목·체스 중괄호를 글자 그대로 읽는다).
        let wake: String = [
            "if case .didWake = event, !realtime.transportAvailable { rummy.systemDidWake() } ",
            "if case .didWake = event, !realtime.transportAvailable { reversi.systemDidWake() }",
        ].joined()
        #expect(realtime.contains(wake), "전송자 없는 맥의 깨어남이 아잉 뒤집기를 안 본다")
    }

    /// 없으면(결과): 소스에 줄이 있어도 엉뚱한 칸을 비추면(예: 차단 거울을 다른 스토어로) 차단한 사람의 신청이 배너·말풍선·점에
    /// 남는다. 실제 `WorkTimerStore` 에서 차단을 바꿔 스토어 칸이 따라가는지 잰다. 호스트도 실제로 물렸는가(없으면 네트워크 0건).
    @Test
    func theRealOwnerMirrorsBlocksAndAttachesItself() throws {
        let store = rwtStore("v03xx-reversi-wiring-owner")
        #expect(store.reversi.host as AnyObject? === store, "소유자가 자신을 호스트로 넘기지 않았다 — 요청이 한 건도 안 나간다")
        // ★ 기준선: 차단 전에는 비어 있다.
        #expect(store.reversi.hiddenPeerIDs.isEmpty)
        store.blockHiddenPeerIDs = [rwtRival.id]
        #expect(store.reversi.hiddenPeerIDs == [rwtRival.id], "차단 거울이 아잉 뒤집기 스토어에 닿지 않는다")
        // 그 결과: 차단한 사람의 신청이 보이는 목록에서 빠진다(점·배너·말풍선이 읽는 값).
        store.reversi.incoming = [rwtInvite("r-blocked")]
        #expect(store.reversi.visibleIncoming == nil)
        store.blockHiddenPeerIDs = []
        #expect(store.reversi.hiddenPeerIDs.isEmpty)
        #expect(store.reversi.visibleIncoming?.id == "r-blocked")
        // 일일 미션 꼬리도 실제로 물려 있다(옵셔널 문 — 빠지면 `?.` 가 삼킨다).
        #expect(store.reversi.onMatchFinished != nil)
        store.reversi.incoming = []
    }

    // MARK: #13 CheckApp — 문 · 창 배선 · 계정 전환 감시

    /// 없으면: 스토어 쪽 문이 옵셔널이라 `?.` 가 삼켜 **창이 안 뜨고**(presentWindow), 말풍선이 안 오고(onInviteArrived·onAttention),
    /// 로그아웃해도 창이 남는다(dismissWindow·감시자). 순위·관전 스위치가 빠지면 순위 열이 영영 로딩이다. 컴파일·스토어 시험은 초록이다.
    @Test
    func theAppWiresEveryReversiDoor() throws {
        let app = try rwtMac("CheckApp.swift")
        #expect(app.contains("wireRummy() wireReversi() wireMegaphoneBanner()"), "실행 시 wireReversi() 를 큐브 뒤·확성기 앞에 부르지 않는다")
        let body = try #require(rwtBetween(app, "private func wireReversi() {", "static func closeRummyWindow() {"))
        let doors: String = [
            "let reversi = store.reversi reversi.rankingEnabled = true reversi.spectatorFeaturesEnabled = true ",
            "reversi.presentWindow = { CheckReversiWindowController.shared.show() } ",
            "reversi.dismissWindow = { CheckReversiWindowController.shared.close() } ",
            "CheckReversiWindowController.shared.onClosed = { [weak self] byUser in self?.store.duelWindowDidClose(.reversi, byUser: byUser) } ",
            "reversi.requestAttention = { if !NSApp.isActive { NSApp.requestUserAttention(.criticalRequest) } } ",
            "reversi.onInviteArrived = { [weak self] invite in self?.overlayController?.enqueueReversiInvite(invite) } ",
            "reversi.onAttention = { [weak self] attention in self?.overlayController?.enqueueReversiAttention(attention) } ",
            "overlayController?.onOpenReversi = { [weak self] matchID in self?.store.reversi.openWindow(focusMatchID: matchID) } ",
            "ChessAccountWatcher(userID: { [weak self] in self?.store.session?.userID }) { [weak self] in ",
            "CheckReversiWindowController.shared.close() self?.overlayController?.clearReversiInvites() }.start() }",
        ].joined()
        #expect(body.contains(doors), "wireReversi 본문이 순서대로 문을 다 잇지 않는다: \(body)")
        let configure: String = [
            "CheckReversiWindowController.shared.configure(store: store.reversi, me: { [weak self] in ",
            "guard let self else { return ReversiPlayerFace.fallback } return ReversiPlayerFace.me(from: self.store) }, safety: store)",
        ].joined()
        #expect(app.contains(configure), "창 배선(configure)이 없다 — 창이 스토어 없이 뜨거나 내 얼굴·순위표 내 줄이 빈다")
        // 결과: 창 식별자는 자동저장·스페이스 키 등록이 같이 쓰는 그 글자다.
        #expect(CheckReversiWindowController.frameAutosaveName == "check.reversi.window")
    }

    // MARK: #14 메뉴바 점(세 자리)

    /// 없으면: 세 칸 모두 기본값 false 라 **한쪽만 빠뜨려도** 컴파일·시험이 초록이고 점만 영영 안 켜진다(메모리 client-gates-come-in-pairs).
    /// 신청은 TTL 60초 — 캐릭터를 꺼 둔 사람에게는 점과 배너가 아는 길 전부다.
    @Test
    func theMenuBarDotLightsForAReversiInvite() throws {
        let reasons = MenuBarDotReasons(reversiInvite: true)
        #expect(!reasons.isEmpty)
        #expect(reasons.accessibilityDescription == "아잉 뒤집기 신청")
        #expect(MenuBarDotReasons.reversiInviteText == ReversiText.dotReason)
        // 기준선: 아무 사유도 없으면 점이 없다(한 값만 바꿨다). 순서는 큐브 뒤다(설계 D7).
        #expect(MenuBarDotReasons().isEmpty)
        #expect(MenuBarDotReasons(rummyInvite: true, reversiInvite: true).accessibilityDescription == "아잉 큐브 초대 · 아잉 뒤집기 신청")
        // 결과: 라벨의 칸이 사유로 옮겨진다(②③ — 라벨 칸 · dotReasons 인자).
        let off = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        #expect(MenuBarStatusLabel(snapshot: off, title: "오프", hasReversiInvite: true).dotReasons == MenuBarDotReasons(reversiInvite: true))
        #expect(MenuBarStatusLabel(snapshot: off, title: "오프", hasRummyInvite: true).dotReasons.reversiInvite == false)

        // ① 앱이 실제 사실(차단·만료를 걷은 첫 신청)을 넘긴다.
        let app = try rwtMac("CheckApp.swift")
        let label: String = [
            "hasRummyInvite: appDelegate.store.rummy.hasIncomingInvite, ",
            "hasReversiInvite: appDelegate.store.reversi.visibleIncoming != nil",
        ].joined()
        #expect(app.contains(label), "메뉴바 라벨이 아잉 뒤집기 신청을 안 읽는다")
        let menu = try rwtMac("CheckMenuView.swift")
        #expect(menu.contains("var hasRummyInvite: Bool = false var hasReversiInvite = false"))
        #expect(menu.contains("rummyInvite: hasRummyInvite, reversiInvite: hasReversiInvite"))
    }

    // MARK: #15 팝오버 배너(두 자리)

    /// 없으면: 팝오버에 신청 배너가 안 서거나(우선순위 줄 누락) 높이 예산에서 빠져 팝오버가 잘리고, 무소속 자리를 빠뜨리면 팀 없는
    /// 사람은 배너를 못 본다. [수락]이 창을 먼저 띄우지 않으면 수락 순간 흑 시계가 도는데 판을 못 본다.
    @Test
    func thePopoverShowsTheReversiInviteBannerInBothSpots() throws {
        let menu = try rwtMac("CheckMenuView.swift")
        let priority: String = [
            "if store.isSignedIn, rummyBannerInvite != nil { return .rummyInvite } ",
            "if store.isSignedIn, reversiBannerInvite != nil { return .reversiInvite }",
        ].joined()
        #expect(menu.contains(priority))
        #expect(menu.contains("case .reversiInvite: return Self.reversiInviteBannerHeight"))
        #expect(CheckMenuView.reversiInviteBannerHeight == CheckMenuView.chessInviteBannerHeight)
        #expect(menu.contains("previewReversiInvite ?? store.reversi.visibleIncoming"))
        #expect(rwtCount("rummyInviteBanner reversiInviteBanner", in: menu) == 2, "두 자리(무소속 · 머리 카드 아래) 모두 큐브 배너 뒤가 아니다")
        let accept: String = [
            "await reversi.respond(inviteID: invite.id, accept: true) reversi.openWindow(focusMatchID: invite.id) ",
            "WindowTopAnchor.dismissMenuPopover()",
        ].joined()
        #expect(menu.contains(accept))
        #expect(menu.contains("await reversi.respond(inviteID: invite.id, accept: false)"))

        // 결과: 두 자리 모두에서 배너가 실제로 그려진다(팝오버가 예산만큼 자란다). 기준선은 배너 없는 같은 팝오버.
        let invite = rwtInvite("invite-1", expiresIn: 48)
        for teamless in [false, true] {
            let store = rwtMenuStore(teamless: teamless)
            let with = try rwtBitmap(CheckMenuView(store: store, previewReversiInvite: invite))
            let without = try rwtBitmap(CheckMenuView(store: store))
            let grew = Double(with.pixelsHigh - without.pixelsHigh) / 2
            print("[배너] 아잉 뒤집기 배너(\(teamless ? "무소속" : "팀")) 높이 \(grew)pt (예산 \(CheckMenuView.reversiInviteBannerHeight)pt)")
            #expect(with.pixelsHigh > without.pixelsHigh, "\(teamless ? "무소속" : "팀") 화면에 아잉 뒤집기 배너가 안 그려진다")
            #expect(abs(grew - Double(CheckMenuView.reversiInviteBannerHeight)) < 24,
                    "배너 높이 예산(\(CheckMenuView.reversiInviteBannerHeight)pt)과 실제(\(grew)pt)가 크게 다르다")
            if !teamless {
                // 체스와 함께 오면 체스가 이긴다(배너는 한 번에 하나 — 창 높이 예산).
                let both = try rwtBitmap(CheckMenuView(store: store, previewChessInvite: ChessInvite(
                    id: "c-1", peer: ChessUser(id: rwtRival.id, displayName: "민수", avatarURL: nil, characterID: "fox",
                                               isWorking: true, isCapable: true, inMatch: false),
                    stake: 5, expiresAt: invite.expiresAt), previewReversiInvite: invite))
                #expect(both.pixelsHigh == with.pixelsHigh, "체스·아잉 뒤집기 배너가 함께 그려졌다 — 창이 700pt 상한을 넘는다")
                MiniGameSnapshots.save(with, name: "popover-reversi-invite-banner.png", sub: "reversi")
            }
        }
    }

    // MARK: #16 캐릭터 말풍선

    /// 없으면: 창을 닫아 둔 사람은 신청도 "내 차례"도 모른다 — 한 수 30초가 그대로 흘러 자동 착수 3번이면 **판돈 패**.
    /// 몸체 히트테스트가 말풍선을 놓치면 클릭이 뒤 앱으로 새고, 클릭 자리가 없으면 눌러도 창이 안 열린다.
    @Test
    func theOverlayCarriesReversiBubblesInTheTetrisShape() throws {
        let overlay = rwtCollapsed(V0317ShopTests.stripped(try CheckCoreSourceLayout.joinedSplitSource("CheckOverlayWindow.swift")))
        #expect(overlay.contains("if let rect = reversiInviteBubbleScreenRect(), rect.contains(screenPoint) { return true }"),
                "몸체 히트테스트가 아잉 뒤집기 말풍선을 모른다")
        let click: String = [
            "if let rect = reversiInviteBubbleScreenRect(), rect.contains(location), ",
            "let matchID = reversiBubbleMatchID() { onOpenReversi?(matchID) return }",
        ].joined()
        #expect(overlay.contains(click), "말풍선을 눌러도 아잉 뒤집기 창이 안 열린다")
        // 살아 있는 신청 거르기는 **테트리스형**(목록 전체) — 체스형(첫 건 한 칸)을 베끼면 둘째 신청부터 큐에서 조용히 지워진다.
        #expect(overlay.contains("let alive = Set(store.reversi.visibleIncomingInvites.map(\\.id))"))
        #expect(!overlay.contains("store.reversi.visibleIncoming?.id"), "체스형(첫 건 한 칸) 거르기가 섞였다")
        // 문구 글자는 맥 문구 집 한 곳(`ReversiText`) — 오버레이에 직접 쓰지 않는다.
        #expect(overlay.contains("let text = ReversiText.bubbleText(name: invite.peer.displayName, stake: invite.stake)"))
        #expect(overlay.contains("let text = ReversiText.attentionText(attention)"))

        // 문구: 긴 이름에서도 캡슐에 든다(세 단계 접기), 판돈 숫자는 남는다.
        let long = ReversiText.bubbleText(name: String(repeating: "가", count: 40), stake: 10)
        #expect(OverlayMessageBubble.fitsCapsule(long), "긴 이름에서 말풍선 문구가 캡슐을 넘친다: \(long)")
        #expect(long.hasSuffix("루비 10") && long.contains("아잉 뒤집기"))
    }

    /// 없으면(결과): 체스형 거르기를 베끼면 **둘째 신청부터** 큐에서 조용히 지워진다 — 소스 계약은 줄만 보고, 스토어 시험은 큐를 안 본다.
    /// 처리된 신청이 뒤늦게 뜨거나 못 띄운 신청을 큐에서 빼도 같은 곳에서 잡힌다.
    @Test
    func twoLiveInvitesBothReachTheCharacter() throws {
        let (engine, controller, store) = rwtOverlay()
        defer {
            controller.clearReversiInvites()
            controller.updateWorking(false)
        }
        let first = rwtInvite("invite-1"), second = rwtInvite("invite-2")
        store.reversi.incoming = [first, second]
        controller.enqueueReversiInvite(first)
        controller.enqueueReversiInvite(first)
        controller.enqueueReversiInvite(second)
        #expect(controller.reversiInviteQueue.map(\.id) == ["invite-1", "invite-2"], "같은 신청이 두 번 들어갔다")
        #expect(controller.showNextReversiInviteBubble())
        #expect(engine.greetingText == ReversiText.bubbleText(name: "민수", stake: 5))
        // ★ 둘째 신청이 큐에 **남아 있다**(체스형이면 여기서 지워진다 — 결과가 갈리는 자리).
        #expect(controller.reversiInviteQueue.map(\.id) == ["invite-2"], "살아 있는 둘째 신청이 큐에서 지워졌다")
        #expect(controller.reversiInviteBubbleScreenRect() == nil, "배선 전인데 클릭 자리가 생겼다")
        controller.onOpenReversi = { _ in }
        #expect(controller.reversiBubbleMatchID() == "invite-1", "말풍선을 눌러도 그 신청의 창을 열 수 없다")
        engine.greetingText = nil
        // 캐릭터가 아직 찔린 연출 중이면 둘째는 **기다린다**(소비하지 않는다) — 펌프가 다음 박자에 띄운다.
        if controller.showNextReversiInviteBubble() == false {
            #expect(controller.reversiInviteQueue.map(\.id) == ["invite-2"], "못 띄운 둘째 신청을 큐에서 뺐다")
        }

        // 처리된(스토어에서 사라진) 신청은 뒤늦게 뜨지 않는다 — 기준선: 위와 같은 큐인데 스토어 목록만 비었다.
        store.reversi.incoming = []
        controller.enqueueReversiInvite(rwtInvite("handled"))
        #expect(controller.showNextReversiInviteBubble() == false)
        #expect(controller.reversiInviteQueue.isEmpty, "이미 처리된 신청이 뒤늦게 말풍선으로 뜬다")
        // 떠 있는 말풍선 뒤에서는 기다린다(소비하지 않는다).
        engine.showBubble("다른 안내", seconds: 60)
        let waiting = rwtInvite("waiting")
        store.reversi.incoming = [waiting]
        controller.enqueueReversiInvite(waiting)
        #expect(controller.showNextReversiInviteBubble() == false)
        #expect(controller.reversiInviteQueue.map(\.id) == ["waiting"], "못 띄운 신청을 큐에서 뺐다")
        store.reversi.incoming = []
    }

    /// 없으면(결과): 낡은 "내 차례"(두 수 전 · 끝난 판 · 창이 이미 보임)가 뜨거나, 진짜 내 차례가 안 뜬다. 차례 30초라 둘 다 손해다.
    @Test
    func theTurnBubbleOnlyShowsTheCurrentHiddenTurn() throws {
        let (engine, controller, store) = rwtOverlay()
        defer {
            controller.clearReversiInvites()
            controller.updateWorking(false)
        }
        let reversi = store.reversi
        let matchID = "7e7e0000-0000-4000-8000-0000000000f1"
        reversi.match = ReversiMatchState(id: matchID, stake: 5, myColor: .black, opponent: rwtRival, moveCount: 4, turn: .black)
        reversi.isWindowVisible = false
        let attention = ReversiAttention(kind: .myTurn, matchID: matchID, opponentName: "민수", moveCount: 4)
        #expect(CheckOverlayController.reversiAttentionIsCurrent(attention, in: reversi))
        // ★ 기준선 셋 — 값 하나씩만 바꿨다.
        let stale = ReversiAttention(kind: .myTurn, matchID: matchID, opponentName: "민수", moveCount: 2)
        #expect(!CheckOverlayController.reversiAttentionIsCurrent(stale, in: reversi), "두 수 전의 내 차례를 띄운다")
        reversi.isWindowVisible = true
        #expect(!CheckOverlayController.reversiAttentionIsCurrent(attention, in: reversi), "창이 보이는데 말풍선을 띄운다")
        // ★ 열려 있어도 완전히 가려진 창(다른 전체 화면 앱·다른 스페이스)은 화면이 말하지 못한다 — 말풍선이 사실이다(적대 검증 V2-01).
        reversi.windowOcclusionDidChange(visible: false)
        #expect(CheckOverlayController.reversiAttentionIsCurrent(attention, in: reversi), "가려진 창인데 차례 말풍선을 버린다")
        reversi.windowOcclusionDidChange(visible: true)
        #expect(!CheckOverlayController.reversiAttentionIsCurrent(attention, in: reversi), "가림이 풀린 창인데 말풍선을 띄운다")
        reversi.isWindowVisible = false
        reversi.match?.turn = .white
        #expect(!CheckOverlayController.reversiAttentionIsCurrent(attention, in: reversi), "상대 차례인데 내 차례라고 한다")
        reversi.match?.turn = .black

        controller.enqueueReversiAttention(attention)
        #expect(controller.showPendingReversiAttentionBubble())
        #expect(engine.greetingText == ReversiText.attentionText(attention))
        #expect(engine.greetingText?.contains("아잉 뒤집기") == true, "차례 말풍선이 어느 게임인지 말하지 않는다")
        controller.onOpenReversi = { _ in }
        #expect(controller.reversiBubbleMatchID() == matchID, "차례 말풍선을 눌러도 그 판을 열 수 없다")
        // 사실이 아니면 **버린다**(기다리지 않는다).
        engine.greetingText = nil
        controller.enqueueReversiAttention(stale)
        #expect(controller.showPendingReversiAttentionBubble() == false)
        #expect(controller.pendingReversiAttention == nil, "사실이 아닌 차례 알림이 큐에 남았다")
        reversi.match = nil
    }

    // MARK: #17~#19 미니게임 창 — 스페이스 키 등록 · 사이드바 문 · 여는 길

    /// 없으면: 미니게임 창을 띄워 둔 채 아잉 뒤집기 창의 단추를 스페이스로 누르면 미니게임 모니터가 먼저 삼키고(등록 누락),
    /// 사이드바에 문이 없어 창을 여는 길이 아예 없고, 문을 눌러도 미니게임 창이 남아 두 창이 겹친다.
    @Test
    func theMiniGameWindowOpensTheReversiWindow() throws {
        #expect(MiniGameSpaceKey.standaloneWindowIDs.contains("check.reversi.window"))
        #expect(MiniGameSpaceKey.standaloneWindowIDs.contains(CheckReversiWindowController.frameAutosaveName))
        #expect(MiniGameSpaceKey.standaloneWindowIDs.count == 8)

        #expect(MiniGameReversiEntryButton.title == "아잉 뒤집기")
        #expect(MiniGameReversiEntryButton.help == "리버시 규칙 1:1 대결 창을 열어요")
        let panel = try rwtMac("MiniGamePanel.swift")
        let group: String = [
            "MiniGameRummyEntryButton(hasInvite: invites.rummy) { onRummy() } ",
            "MiniGameReversiEntryButton(hasInvite: invites.reversi) { onReversi() }",
        ].joined()
        #expect(panel.contains(group), "같이 하기 묶음에 아잉 뒤집기 문이 큐브 뒤에 없다")
        #expect(panel.contains("onRummy: { store.openRummyFromMiniGame() }, onReversi: { store.openReversiFromMiniGame() }"))
        // 사이드바는 문을 **기본값 없이** 받는다 — 기본값 `{}` 가 있으면 배선을 빠뜨린 문이 조용히 아무 일도 안 한다.
        #expect(panel.contains("let onRummy: () -> Void let onReversi: () -> Void"), "사이드바가 아잉 뒤집기 문을 기본값 없이 받지 않는다")
        #expect(!panel.contains("var onReversi: () -> Void = {}"), "아잉 뒤집기 문에 빈 기본값이 남았다")
        // 점 칸: 명시 init 맨 뒤 기본값(기존 호출 보호) + 창이 부르는 생성자가 메뉴바와 같은 사실을 읽는다.
        #expect(panel.contains("init(gomoku: Bool = false, chess: Bool = false, tetris: Bool = false, rummy: Bool = false, reversi: Bool = false)"))
        #expect(panel.contains("rummy: store.rummy.hasIncomingInvite, reversi: store.reversi.visibleIncoming != nil"))
        // 문 struct 는 큐브 문 struct 뒤에 선다(설계 §4.6 #18).
        let rummyDoor = try #require(panel.range(of: "struct MiniGameRummyEntryButton: View {"))
        let reversiDoor = try #require(panel.range(of: "struct MiniGameReversiEntryButton: View {"))
        #expect(rummyDoor.upperBound <= reversiDoor.lowerBound)

        let miniGame = try rwtMac("WorkTimerStoreMiniGame.swift")
        #expect(miniGame.contains("func openReversiFromMiniGame() { noteMiniGameDuelReturn(.reversi) reversi.openWindow(focusMatchID: nil) closeMiniGamePanel() }"),
                "아잉 뒤집기 창을 먼저 띄우고 미니게임 창을 내려야 한다")
    }

    // MARK: #21 확성기 배너 미룸

    /// 없으면: 판 중에 확성기 배너가 판 위로 떠 30초 차례를 가리고, 판이 끝나도 배너가 안 풀린다 — 배너 시험은 기본값 false 로 초록이다.
    @Test
    func theMegaphoneBannerWaitsForAReversiMatch() throws {
        #expect(MegaphoneBannerDeferral.isDeferred(gomoku: .lobby, chess: .lobby, tetris: .lobby, miniGameRoundLive: false,
                                                   reversiLive: true))
        // ★ 기준선: 같은 인자에서 그 한 칸만 거짓이면 미루지 않는다.
        #expect(!MegaphoneBannerDeferral.isDeferred(gomoku: .lobby, chess: .lobby, tetris: .lobby, miniGameRoundLive: false,
                                                    reversiLive: false))
        // 넘기는 값은 스토어의 판정(대국 중일 때만 참)이다.
        let reversi = ReversiStore()
        #expect(reversi.defersMegaphoneBanner == false)
        reversi.phase = .playing
        #expect(reversi.defersMegaphoneBanner)
        let src = try rwtMac("WorkTimerStoreMegaphoneBanner.swift")
        #expect(src.contains("rummyLive: rummy.defersMegaphoneBanner, reversiLive: reversi.defersMegaphoneBanner)"))
        #expect(src.contains("rummyLive: Bool = false, reversiLive: Bool = false) -> Bool {"))
        #expect(src.contains("if reversiLive { return true }"))
    }

    // MARK: #22 미션 아이콘

    /// 없으면: 일일 미션 `daily_reversi` 줄이 모르는 게임의 별(fallback)로 그려진다 — 미션 시험은 아이콘 이름을 안 본다.
    @Test
    func theDailyMissionRowUsesTheReversiDoorIcon() throws {
        #expect(DailyMissionCopy.icon(game: "reversi") == ReversiEntryIcon.resolved)
        // ★ 기준선: 모르는 게임은 별이다 — 위 값이 별이면 배선이 빠진 것이다.
        #expect(DailyMissionCopy.icon(game: "reversi") != AchievementCopy.fallbackIcon)
        #expect(DailyMissionCopy.icon(game: "reversi_typo") == AchievementCopy.fallbackIcon)
        #expect(NSImage(systemSymbolName: ReversiEntryIcon.resolved, accessibilityDescription: nil) != nil,
                "아잉 뒤집기 아이콘(\(ReversiEntryIcon.resolved))이 이 맥에서 안 풀린다")
    }
}

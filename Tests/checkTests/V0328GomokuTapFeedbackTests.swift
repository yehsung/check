import Foundation
import Testing
@testable import check

// v0.3.28 — 판을 눌렀는데 **아무 반응이 없다**를 없앤 자리.
//
// 0.3.27 까지 착수 거절은 뷰(`GomokuPlayBoard` 탭 제스처)와 스토어(`place(_:)`) 양쪽의 `guard` 한 줄씩에 뭉쳐
// 있었고, 그 안의 네 갈래 — 내 차례가 아님 · 왕복 중이라 잠김(`isBusy`) · 이미 돌이 있음 · 판이 끝남 — 이 **전부
// 무음**이었다. 운영에서 사용자가 돌을 못 놓아 판돈을 잃었는데 앱이 사유를 하나도 말해 주지 않아, 원인 규명이
// 며칠치 조사로 번졌다.
//
// 여기서 지키는 것 셋:
//  ① 거절마다 `store.notice` 에 **서로 다른 한 줄**이 선다(문구는 `GomokuNoticeText` 한 곳에서만 나온다).
//  ② 거절은 그대로 거절이다 — 안내를 더한다고 서버로 헛요청이 나가면 안 된다(무료 플랜).
//  ③ 소스에 **말없이 되돌아가는 `return`** 이 남아 있지 않다. 예외는 단 하나, 격자 **판 밖** 탭이다.
//     (주석을 걷어내고 대조한다 — 안 그러면 설명을 지워야만 초록이 되는 테스트가 된다.)
//
// 관례는 V0327GomokuStoreTests · V0328GomokuChatStoreTests 그대로다: 호스트별 URLProtocol 스텁(테스트마다 고유
// 호스트라 병렬 스위트가 서로의 기록을 안 덮는다) · `WorkTimerStore` 를 `_` 로 버리지 않는다(오목 스토어가
// 약참조라 해제되면 요청이 한 건도 안 나간다) · UserDefaults 스위트는 `.gomokuDefaultsCleanup` 이 지운다.

// MARK: - 픽스처

private let tfMe = "00000000-0000-0000-0000-0000000000a1"
private let tfRival = "00000000-0000-0000-0000-0000000000b2"
private let tfMatch = "99998888-7777-6666-5555-444433332222"

private func tfJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func tfMove(_ seq: Int, _ color: String, _ x: Int, _ y: Int) -> [String: Any] {
    ["seq": seq, "color": color, "x": x, "y": y, "kind": "stone"]
}

private func tfState(
    myColor: String = "black",
    turn: String? = "black",
    matchStatus: String = "active",
    moves: [[String: Any]] = [],
    moveCount: Int? = nil,
    result: String? = nil,
    endReason: String? = nil
) -> [String: Any] {
    var match: [String: Any] = [
        "id": tfMatch,
        "status": matchStatus,
        "stake": 5,
        "black": myColor == "black" ? tfMe : tfRival,
        "white": myColor == "black" ? tfRival : tfMe,
        "challenger": tfRival,
        "opponent": tfMe,
        "move_count": moveCount ?? moves.count,
        "turn": turn ?? NSNull(),
        "deadline_ms": NSNull(),
        "result": NSNull(),
        "end_reason": NSNull(),
        "winner": NSNull(),
        "invite_expires_ms": NSNull()
    ]
    if let result { match["result"] = result }
    if let endReason { match["end_reason"] = endReason }
    return [
        "status": "ok",
        "match": match,
        "moves": moves,
        "my_color": myColor,
        "opponent": ["user_id": tfRival, "display_name": "라이벌",
                     "avatar_url": NSNull(), "character": "aing"] as [String: Any],
        "ruby_balance": NSNull(),
        "server_now_ms": NSNull()
    ]
}

private func tfDecode(_ object: [String: Any]) -> GomokuStatePayload {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(GomokuStatePayload.self, from: Data(tfJSON(object).utf8))
}

/// 오목 스토어는 WorkTimerStore 를 **약참조**한다 — 튜플에서 버리면 곧바로 해제되어 요청이 한 건도 안 나간다.
@MainActor
private enum TapTestRetention {
    static var stores: [WorkTimerStore] = []
}

@MainActor
private func makeTapStore(
    _ label: String,
    handler: @escaping GomokuStubProtocol.Handler = { _, _, _ in nil }
) -> (WorkTimerStore, GomokuStore, String) {
    let host = "v0328-tap-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: GomokuStubProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0328-tap"),
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: tfMe)
    TapTestRetention.stores.append(store)
    return (store, store.gomoku, host)
}

private let tfDiagnosticWords = [
    "서버", "상태", "동기화", "토큰", "세션", "RPC", "status", "_", "오류", "에러", "unknown", "실패", "stale"
]

// MARK: - 1. 문구 표

@Test(.gomokuDefaultsCleanup)
func 탭_거절_문구는_문구표_한_곳에서_나온다() {
    #expect(GomokuNoticeText.tapRefusal(.busy) == "보내는 중이에요")
    #expect(GomokuNoticeText.tapRefusal(.occupied) == "이미 돌이 놓인 자리예요")
    // 나머지 넷은 **이미 있는 문구를 다시 쓴다** — 같은 사실이 화면마다 다른 말을 하면 그게 다음 조사거리다.
    #expect(GomokuNoticeText.tapRefusal(.notYourTurn) == GomokuNoticeText.notYourTurn)
    #expect(GomokuNoticeText.tapRefusal(.finished) == GomokuNoticeText.finishedMatch)
    #expect(GomokuNoticeText.tapRefusal(.signedOut) == GomokuNoticeText.signInAgain)
    #expect(GomokuNoticeText.tapRefusal(.forbidden, reason: .doubleThree) == GomokuNoticeText.forbidden(.doubleThree))
    #expect(GomokuNoticeText.tapRefusal(.forbidden) == GomokuNoticeText.cannotPlace)
    // 판이 없으면 볼 화면도 없다 — 유일하게 말하지 않는 갈래다(그래도 진단 줄은 남는다).
    #expect(GomokuNoticeText.tapRefusal(.noMatch) == nil)

    // 갈래마다 **다른** 말을 해야 한다: 둘이 같은 문구면 그 한 줄로는 원인을 못 가른다.
    let spoken = GomokuTapRefusal.allCases.compactMap { GomokuNoticeText.tapRefusal($0) }
    #expect(spoken.count == GomokuTapRefusal.allCases.count - 1, "noMatch 말고 말없는 갈래가 또 있다")
    #expect(Set(spoken).count == spoken.count, "두 거절이 같은 문구를 쓴다: \(spoken)")

    for text in spoken {
        #expect(!text.isEmpty)
        for word in tfDiagnosticWords {
            #expect(!text.contains(word), "안내 문구에 진단 어휘 '\(word)': \(text)")
        }
    }

    // 로그 어휘는 고정 문자열이라 그대로 공개로 찍는다 — 겹치면 두 갈래가 같은 줄로 보인다.
    let reasons = GomokuTapRefusal.allCases.map(\.rawValue)
    #expect(Set(reasons).count == reasons.count)
    #expect(reasons.allSatisfy { reason in
        !reason.isEmpty && reason.allSatisfy { character in character.isLowercase || character == "-" }
    }, "로그 사유에 대문자·공백이 섞였다: \(reasons)")
}

// MARK: - 2. 거절마다 한 줄 (동작)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 무음이던_네_거절이_저마다_다른_한_줄을_남긴다() async {
    // ① 보내는 중 — 앞 착수가 왕복 중이라 잠겼다.
    let (_, busy, busyHost) = makeTapStore("busy")
    busy.applyState(tfDecode(tfState()))
    busy.isBusy = true
    await busy.place(GomokuPoint(x: 7, y: 7)!)
    #expect(busy.notice == GomokuNoticeText.sending)
    #expect(GomokuStubProtocol.count(host: busyHost, rpc: "gomoku_move") == 0, "잠긴 채로 서버에 보냈다")

    // ② 상대 차례.
    let (_, theirs, theirsHost) = makeTapStore("their-turn")
    theirs.applyState(tfDecode(tfState(turn: "white", moves: [tfMove(1, "black", 7, 7)])))
    await theirs.place(GomokuPoint(x: 3, y: 3)!)
    #expect(theirs.notice == GomokuNoticeText.notYourTurn)
    #expect(GomokuStubProtocol.count(host: theirsHost, rpc: "gomoku_move") == 0)

    // ③ 이미 돌이 놓인 자리(상대 돌).
    let (_, taken, takenHost) = makeTapStore("occupied")
    taken.applyState(tfDecode(tfState(
        turn: "black", moves: [tfMove(1, "black", 7, 7), tfMove(2, "white", 8, 7)])))
    await taken.place(GomokuPoint(x: 8, y: 7)!)
    #expect(taken.notice == GomokuNoticeText.occupied)
    #expect(GomokuStubProtocol.count(host: takenHost, rpc: "gomoku_move") == 0)

    // ④ 끝난 판.
    let (_, over, overHost) = makeTapStore("finished")
    over.applyState(tfDecode(tfState(
        turn: nil, matchStatus: "finished", moves: [tfMove(1, "black", 7, 7)],
        result: "white_win", endReason: "resign")))
    #expect(over.match?.isFinished == true)
    await over.place(GomokuPoint(x: 3, y: 3)!)
    #expect(over.notice == GomokuNoticeText.finishedMatch)
    #expect(GomokuStubProtocol.count(host: overHost, rpc: "gomoku_move") == 0)

    // ⑤ 로그인이 풀렸다(창은 아직 떠 있다).
    let (owner, signedOut, signedOutHost) = makeTapStore("signed-out")
    signedOut.applyState(tfDecode(tfState()))
    owner.session = nil
    await signedOut.place(GomokuPoint(x: 7, y: 7)!)
    #expect(signedOut.notice == GomokuNoticeText.signInAgain)
    #expect(GomokuStubProtocol.count(host: signedOutHost, rpc: "gomoku_move") == 0)

    // 넷이 서로 다른 말을 했는가 — 같은 줄이 둘이면 그 한 줄로는 원인을 못 가른다.
    let said = [busy.notice, theirs.notice, taken.notice, over.notice, signedOut.notice].compactMap { $0 }
    #expect(said.count == 5 && Set(said).count == 5, "거절 다섯이 낸 말: \(said)")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 판이_없는_탭은_말하지_않지만_서버로도_안_나간다() async {
    let (_, gomoku, host) = makeTapStore("no-match")
    #expect(gomoku.match == nil)
    await gomoku.place(GomokuPoint(x: 7, y: 7)!)
    // 볼 화면이 없는 거절은 상태줄을 건드리지 않는다(진단 줄만 남는다).
    #expect(gomoku.notice == nil)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_move") == 0)
}

/// 기준선 — 안내를 더하면서 **정상 착수까지 막지는 않았다**. 이 시험이 없으면 `place(_:)` 를 통째로
/// 거절로 만들어도 위 시험들이 전부 초록이다.
@MainActor
@Test(.gomokuDefaultsCleanup)
func 둘_수_있는_자리는_그대로_서버로_간다() async {
    let (_, gomoku, host) = makeTapStore("allowed") { rpc, _, _ in
        guard rpc == "gomoku_move" else { return nil }
        return GomokuStubProtocol.Reply(body: tfJSON([
            "status": "ok",
            "state": tfState(turn: "white", moves: [tfMove(1, "black", 7, 7)], moveCount: 1)
        ]))
    }
    gomoku.applyState(tfDecode(tfState()))

    await gomoku.place(GomokuPoint(x: 7, y: 7)!)

    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_move") == 1, "거절 안내가 정상 착수까지 막았다")
    #expect(gomoku.notice == nil, "성공은 말하지 않는다 — 돌이 놓이는 것이 곧 답이다")
    #expect(gomoku.match?.board[GomokuPoint(x: 7, y: 7)!] == .black)
    #expect(gomoku.isBusy == false)
}

// MARK: - 3. 소스 계약 (주석을 걷어낸 뒤)

@Test
func 탭_경로와_착수에는_말없이_되돌아가는_길이_없다() throws {
    let panel = V0317ShopTests.stripped(try V0317ShopTests.source("GomokuPanel.swift"))
    let store = V0317ShopTests.stripped(try V0317ShopTests.source("GomokuStore.swift"))

    // ① 판 탭 제스처 — 조용히 되돌아가도 되는 길은 **판 밖 하나뿐**이다.
    let tap = try #require(gomokuBody(of: "SpatialTapGesture().onEnded", in: panel))
    let tapReturns = tap.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.contains("return") }
    #expect(tapReturns.count == 1, "탭 경로에 되돌아가는 길이 \(tapReturns.count) 개다: \(tapReturns)")
    #expect(tapReturns.first?.contains("g.point(at: value.location)") == true,
            "판 밖 말고 다른 곳에서 조용히 되돌아간다: \(tapReturns)")
    // 뭉쳐 있던 무음 가드가 되살아나지 않는다(그 한 줄이 세 가지 거절을 통째로 삼켰다).
    #expect(!tap.contains("canPlace"), "탭 경로가 canPlace 로 다시 조용히 걸러 낸다")
    #expect(!tap.contains("match.board[point]"), "탭 경로가 이미 놓인 자리를 조용히 걸러 낸다")
    #expect(tap.contains("store.place(point)"), "탭이 스토어를 안 부른다")

    // ② place(_:) 의 **보내기 전 구간** — 모든 return 앞에 refuseTap( 이 선다.
    //    (보낸 뒤의 `perform` nil 은 계정이 바뀌었거나 스토어가 리셋된 길이라 일부러 조용하다 — 아래에서 따로 짚는다.)
    let body = try #require(gomokuBody(of: "func place(_ point: GomokuPoint)", in: store))
    let send = try #require(body.range(of: "await perform("))
    let guards = String(body[body.startIndex..<send.lowerBound])
    let lines = guards.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var silent: [String] = []
    for (index, line) in lines.enumerated() where line.contains("return") {
        let window = lines[max(0, index - 2)...index].joined(separator: " ")
        if !window.contains("refuseTap(") { silent.append(line.trimmingCharacters(in: .whitespaces)) }
    }
    #expect(silent.isEmpty, "말없이 되돌아가는 길: \(silent)")

    // 갈래가 전부 서 있는지 이름으로 되묻는다 — 하나를 통째로 지워도 위 검사만으로는 초록이다.
    for refusal in [".busy", ".noMatch", ".finished", ".notYourTurn", ".occupied", ".forbidden", ".signedOut"] {
        #expect(guards.contains("refuseTap(\(refusal)"), "refuseTap(\(refusal) 갈래가 없다")
    }

    // ③ 진단 줄은 **좌표와 사유만** 싣는다 — 로그는 기기에 남고 제보에 실려 나간다.
    let refuse = try #require(gomokuBody(of: "private func refuseTap(", in: store))
    #expect(refuse.contains("tap refused reason="), "진단 줄의 머리말이 바뀌었다")
    for field in ["point=", "turn=", "mine=", "busy="] {
        #expect(refuse.contains(field), "진단 줄에 \(field) 가 없다")
    }
    for leak in ["displayName", "opponent", "accessToken", "session", "current.id", "match?.id",
                 "userID", "chat", "board", "serverString"] {
        #expect(!refuse.contains(leak), "진단 줄에 '\(leak)' 이 실린다 — 개인정보·판 내용은 넣지 않는다")
    }

    // ④ 문구는 GomokuNoticeText 한 곳에만 있다 — 화면 파일에 거절 문구를 새로 두지 않는다.
    for text in [GomokuNoticeText.sending, GomokuNoticeText.occupied] {
        #expect(!panel.contains(text), "화면 파일이 '\(text)' 를 직접 들고 있다")
    }

    // ⑤ 상태줄 우선순위(호버 금수 이유가 1순위)는 그대로다 — 거절 문구는 notice 경로로 흐른다.
    let side = try #require(gomokuBody(of: "private var statusLine: (text: String, tint: Color)", in: panel))
    let hoverAt = try #require(side.range(of: "hoveredReason"))
    let noticeAt = try #require(side.range(of: "store.notice"))
    #expect(hoverAt.lowerBound < noticeAt.lowerBound, "안내가 호버 금수 이유보다 먼저 선다 — 기존 우선순위를 깼다")
}

// 원본: Sources/CheckCore/RummyNoticeText.swift @ 1a5eeca6 (골든 생성기 — 아잉 큐브 안내 문구)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// 아잉 큐브 안내 문구 골든(rummy/notice): 맥과 폰이 같은 서버 응답을 같은 말로 옮기도록 status × 동작 표 전부 · 판정 이유 · 초대 · 첫 등록 진행 · 고정 글자를 글자 그대로 잰다.

@Suite("GoldenExport rummy — 안내 문구(rummy/notice)")
struct GoldenExportRummyNotice {
    /// RummyRPCStatus 전부(CaseIterable 이 아니라 손으로 적는다 — 글자 왕복을 대조해 빠지면 빨갛다).
    private static let statuses: [RummyRPCStatus] = [
        .ok, .unauthorized, .unsupportedClient, .invalid, .busy, .alreadyInRoom, .insufficient, .notHost, .blackout, .targetFocused, .targetOutdated,
        .targetBusy, .roomFull, .tooManyInvites, .alreadyInvited, .roomClosed, .notInvited, .notEnoughPlayers, .seatsDropped, .notFound, .notYourTurn,
        .stale, .malformed, .tooFast, .rejected, .notActive, .unknown,
    ]
    private static let actions: [RummyNoticeText.Action] = [.lobby, .create, .invite, .join, .decline, .leave, .start, .state, .draft, .play, .draw, .ranking]

    @Test("rummy/notice — status × 동작 · 판정 이유 · 초대 · 진행 · 고정 글자")
    func notice() {
        var cases: [GoldenJSON] = []
        for status in Self.statuses {
            #expect(RummyRPCStatus(rawValue: status.rawValue) == status)
            var texts: [String: GoldenJSON] = [:]
            for action in Self.actions { texts[action.rawValue] = .string(RummyNoticeText.status(status, for: action)) }
            cases.append(["id": .string("status-\(status.rawValue)"), "kind_": "status", "status": .string(status.rawValue), "texts": .object(texts)])
        }
        for reason in RummyTurnReason.allCases {
            for points in [nil, 0, 18, 29] as [Int?] {
                let text = RummyNoticeText.reason(reason, initialPoints: points)
                cases.append(["id": .string("reason-\(reason.rawValue)-\(points.map(String.init) ?? "nil")"), "kind_": "reason", "reason": .string(reason.rawValue), "points": points.map { .int($0) } ?? .null, "text": text.map { .string($0) } ?? .null])
            }
        }
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let rooms: [(String, String?, Bool, Int?)] = [("named", "영식", true, 5), ("noname", nil, true, 3), ("empty", "", true, 10), ("nohost", nil, false, 5), ("nostake", "민수", true, nil), ("nostake-nohost", nil, false, nil)]
        for (name, display, hasHost, stake) in rooms {
            let room = RummyRoom(id: id, host: hasHost ? RummyPeer(id: id, displayName: display) : nil, stake: stake)
            cases.append(["id": .string("invite-\(name)"), "kind_": "invitation", "hostName": display.map { .string($0) } ?? .null, "hasHost": .bool(hasHost), "stake": stake.map { .int($0) } ?? .null, "text": .string(RummyNoticeText.invitation(room))])
        }
        for points in [0, 18, 30, 45] {
            cases.append(["id": .string("progress-\(points)"), "kind_": "progress", "points": .int(points), "text": .string(RummyNoticeText.initialProgress(points))])
        }
        let constants: [(String, String)] = [
            ("tryAgain", RummyNoticeText.tryAgain), ("checkConnection", RummyNoticeText.checkConnection), ("updateRequired", RummyNoticeText.updateRequired),
            ("signInAgain", RummyNoticeText.signInAgain), ("unavailable", RummyNoticeText.unavailable), ("invited", RummyNoticeText.invited),
            ("roomClosed", RummyNoticeText.roomClosed), ("droppedFromRoom", RummyNoticeText.droppedFromRoom), ("turnPassed", RummyNoticeText.turnPassed),
            ("tableChanged", RummyNoticeText.tableChanged), ("finishedMatch", RummyNoticeText.finishedMatch), ("myTurnAttention", RummyNoticeText.myTurnAttention),
            ("matchStartedAttention", RummyNoticeText.matchStartedAttention),
        ]
        for (name, text) in constants { cases.append(["id": .string("const-\(name)"), "kind_": "constant", "name": .string(name), "text": .string(text)]) }

        goldenEmit(GoldenFile(
            golden: "rummy/notice",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/RummyNoticeText.swift"],
            spec: [
                "kind_": "status(RummyRPCStatus 원시값 → texts: Action 원시값 12개 → 글자) · reason(RummyTurnReason × initialPoints → 글자 또는 null) · invitation · progress · constant.",
                "scope": "표 밖에서 문구를 만들지 않는다(설계서 §4.3). 화면 고정 글자는 이 표가 아니다.",
            ],
            cases: cases
        ))
    }
}

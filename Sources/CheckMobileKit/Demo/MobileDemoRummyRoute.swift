#if DEBUG
import CheckCore
import Foundation

/// 데모 스크린샷 라우트 `games/rummy/…`(아잉 큐브 · 1.0.17)를 **값으로 푼 것**(DEBUG 전용).
/// 왜 `Demo/` 안이고 파일 통째가 `#if DEBUG` 인가 · 왜 `#if os(iOS)` 를 더하면 안 되는가는 `MobileDemoTetrisRoute` 머리말과 같다(출시 게이트 · 맥 스위트가 값으로 재는 자리).
///
/// | 라우트                         | 장면 폴더                       | 열 판(바늘)   | 로비 탭 | 그 밖                         |
/// | ------------------------------ | ------------------------------- | ------------- | ------- | ----------------------------- |
/// | `games/rummy/lobby`            | (없음 — 바깥 층)                 | nil           | 사람    |                               |
/// | `games/rummy/ranking`          | (없음 — 바깥 층)                 | nil           | 순위    |                               |
/// | `games/rummy/rules`            | (없음 — 바깥 층)                 | nil           | 사람    | 규칙 시트를 연다               |
/// | `games/rummy/room`             | `_games-rummy-room`             | …c001         | 사람    | 내가 방장 · 3명 + 초대 1      |
/// | `games/rummy/match/my-turn`    | `_games-rummy-match-my-turn`    | …c002         | 사람    | 내 차례 · 첫 등록 전 · 15장    |
/// | `games/rummy/match/waiting`    | `_games-rummy-match-waiting`    | …c003         | 사람    | 남의 차례 · 작업 판 · 판 가득 |
/// | `games/rummy/match/edited`     | `_games-rummy-match-edited`     | …c002         | 사람    | 내 차례 + 받침대에서 3장 낸 판 |
/// | `games/rummy/match/elsewhere`  | `_games-rummy-match-elsewhere`  | …c002         | 사람    | 이 기기가 손대지 않은 판       |
/// | `games/rummy/result`           | (없음 — 바깥 층)                 | …c004         | 사람    | 끝난 판 · 판돈 5 · 4인         |
/// | `games/rummy/room/guest`       | `_games-rummy-room-guest`       | …c005         | 사람    | 손님으로 앉은 공개 방 · 2명    |
/// | `games/rummy/lobby/empty`      | `_games-rummy-lobby-empty`      | nil           | 사람    | 초대·공개 방·사람 없음         |
/// | `games/rummy/lobby/failed`     | `_games-rummy-lobby-failed`     | nil           | 사람    | 로비 조회 실패                 |
/// | `games/rummy/lobby/short`      | `_games-rummy-lobby-short`      | nil           | 사람    | 내 루비 2(판돈 전부 모자람)    |
/// | `games/rummy/lobby/update`     | `_games-rummy-lobby-update`     | nil           | 사람    | 서버가 이 빌드를 거절          |
/// | `games/rummy/lobby/missing`    | `_games-rummy-lobby-missing`    | nil           | 사람    | 서버에 함수 없음               |
/// | `games/rummy/lobby/people`     | `_games-rummy-lobby-people`     | nil           | 사람    | 초대·공개 방 없이 사람 8       |
/// | `games/rummy/lobby/busy`       | `_games-rummy-lobby-busy`       | nil           | 사람    | 바쁜 2 · 업데이트 필요 2(펴짐) |
/// | `games/rummy/lobby/sheet`      | (없음 — 바깥 층)                 | nil           | 사람    | 판돈 시트를 연다               |
/// | `games/rummy/ranking/failed`   | `_games-rummy-ranking-failed`   | nil           | 순위    | 순위 조회 실패                 |
///
/// 판 장면은 테트리스처럼 **두 길**로 같은 판을 연다: 장면 폴더의 로비 `me.active_match_id`(코어만으로 선다) + `focusMatchID`(`openWindow`). 같은 id 라 겹쳐도 멱등이다.
/// 결과는 끝난 판이라 로비가 가리키지 않는다 — `focusMatchID` 한 길이다.
///
/// 실행:
/// ```
/// xcrun simctl launch <기기> com.yehsung.aingcheck -AingCheckDemo YES -AingCheckDemoRoute games/rummy/match/my-turn
/// ```
package struct MobileDemoRummyRoute: Hashable, Sendable {
    package enum Scene: String, Hashable, Sendable, CaseIterable {
        case lobby = "games/rummy/lobby"
        case ranking = "games/rummy/ranking"
        case rules = "games/rummy/rules"
        case room = "games/rummy/room"
        case matchMyTurn = "games/rummy/match/my-turn"
        case matchWaiting = "games/rummy/match/waiting"
        case matchEdited = "games/rummy/match/edited"
        case matchElsewhere = "games/rummy/match/elsewhere"
        case result = "games/rummy/result"
        case roomGuest = "games/rummy/room/guest"
        case lobbyEmpty = "games/rummy/lobby/empty"
        case lobbyFailed = "games/rummy/lobby/failed"
        case lobbyShort = "games/rummy/lobby/short"
        case lobbyUpdate = "games/rummy/lobby/update"
        case lobbyMissing = "games/rummy/lobby/missing"
        case lobbyPeople = "games/rummy/lobby/people"
        case lobbyBusy = "games/rummy/lobby/busy"
        case lobbySheet = "games/rummy/lobby/sheet"
        case rankingFailed = "games/rummy/ranking/failed"

        package var scenario: String { rawValue.replacingOccurrences(of: "/", with: "-") }

        /// 이 장면이 세우는 판.
        package var focusMatchID: UUID? {
            switch self {
            case .lobby, .ranking, .rules, .lobbyEmpty, .lobbyFailed, .lobbyShort, .lobbyUpdate, .lobbyMissing, .lobbyPeople, .lobbyBusy, .lobbySheet, .rankingFailed:
                return nil
            case .room: return Self.roomID
            case .roomGuest: return Self.guestRoomID
            case .matchMyTurn, .matchEdited, .matchElsewhere: return Self.myTurnID
            case .matchWaiting: return Self.waitingID
            case .result: return Self.resultID
            }
        }

        /// 이 기기가 손댄 판인가. 놀던 기기 장면만 아니다 — 데모는 앞 차례의 쓰기가 없어 장부가 비어 있으므로 라우트가 적어 준다.
        package var engages: Bool {
            switch self {
            case .lobby, .ranking, .rules, .matchElsewhere, .lobbyEmpty, .lobbyFailed, .lobbyShort, .lobbyUpdate, .lobbyMissing, .lobbyPeople, .lobbyBusy, .lobbySheet, .rankingFailed:
                return false
            case .room, .roomGuest, .matchMyTurn, .matchWaiting, .matchEdited, .result: return true
            }
        }

        package var lobbyTab: LobbyTab { self == .ranking || self == .rankingFailed ? .ranking : .people }

        package static let roomID = UUID(uuidString: "d0000000-0000-4000-8000-00000000c001")!
        package static let myTurnID = UUID(uuidString: "d0000000-0000-4000-8000-00000000c002")!
        package static let waitingID = UUID(uuidString: "d0000000-0000-4000-8000-00000000c003")!
        package static let resultID = UUID(uuidString: "d0000000-0000-4000-8000-00000000c004")!
        package static let guestRoomID = UUID(uuidString: "d0000000-0000-4000-8000-00000000c005")!
    }

    package enum LobbyTab: String, Hashable, Sendable { case people, ranking }

    package var scene: Scene

    package init(scene: Scene) {
        self.scene = scene
    }

    package var focusMatchID: UUID? { scene.focusMatchID }
    package var lobbyTab: LobbyTab { scene.lobbyTab }
    package var scenario: String { scene.scenario }
    package var destination: GamesDestination { .rummy }

    /// 데모 라우트 글자 → 값. 큐브 라우트가 아니면 nil. 모르는 꼬리는 로비 머리로 접는다(틀린 꼬리가 **보이게** — 테트리스와 같은 규약).
    package init?(demoRoute raw: String) {
        let path = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard path == "games/rummy" || path.hasPrefix("games/rummy/") else { return nil }
        self.init(scene: Scene(rawValue: path) ?? .lobby)
    }

    /// 화면이 처음 설 때(판을 읽기 전) 스토어에 적을 것 — 손댄 판 장부 · 규칙 시트.
    @MainActor
    package func prepare(_ store: RummyStore) {
        if scene.engages, let id = focusMatchID { store.markEngaged(id) }
        if scene == .rules { store.rulesShown = true }
    }

    /// `match/edited` 장면: 받침대의 A10 A11 A12 를 판 왼쪽 아래 빈자리에 낸 작업 판을 세운다(편집기가 선 뒤 한 번 · 다시 불러도 멱등).
    /// 받침대에서 3장 빠지고 묶음 하나가 늘어 첫 등록 33/30 점 — [완료]가 켜지는 장면이다.
    @MainActor
    package func applyEdit(to store: RummyStore) {
        guard scene == .matchEdited, let editor = store.editor, !editor.isChanged else { return }
        let wanted = ["A10", "A11", "A12"]
        let ids = wanted.compactMap { text in editor.rack.first { $0.face.text == text }?.id }
        guard ids.count == wanted.count else { return }
        store.moveTiles(ids, to: .newMeldAt(RummyPoint(x: 40, y: 420)))
    }
}
#endif

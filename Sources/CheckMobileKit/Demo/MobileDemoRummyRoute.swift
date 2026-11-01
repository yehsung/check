#if DEBUG
import CheckCore
import CoreGraphics
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
/// | `games/rummy/match/full`       | `_games-rummy-match-full`       | …c005         | 사람    | 내 차례 · 판 타일 84장 · 첫 등록 뒤 |
/// | `games/rummy/match/overview`   | `_games-rummy-match-overview`   | …c005         | 사람    | 빽빽한 판을 [전체 보기]로      |
/// | `games/rummy/match/many`       | `_games-rummy-match-many`       | …c006         | 사람    | 내 차례 · 받침대 33장(3줄) · 아래 밖 묶음 · 기권 자리 |
/// | `games/rummy/match/narrow`     | `_games-rummy-match-narrow`     | …c002         | 사람    | 판 화면을 667×354 로 그린다(작은 기기) |
/// | `games/rummy/match/tiny`       | `_games-rummy-match-tiny`       | …c002         | 사람    | 판 화면을 568×320 으로 그린다(시스템 '화면 확대') |
/// | `games/rummy/match/dragging`   | `_games-rummy-match-dragging`   | …c005         | 사람    | 받침대 타일을 묶음 위에 끼우는 중(캐럿) |
/// | `games/rummy/match/attach`     | `_games-rummy-match-attach`     | …c006         | 사람    | 받침대 타일을 묶음 끝 곁에 붙이는 중(자석) |
/// | `games/rummy/match/placing`    | `_games-rummy-match-placing`    | …c002         | 사람    | 받침대 덩어리를 빈 펠트로 끄는 중 |
/// | `games/rummy/match/refused`    | `_games-rummy-match-refused`    | …c005         | 사람    | 판 타일을 받침대로 끄는 중(R-14) |
/// | `games/rummy/match/lifted`     | `_games-rummy-match-lifted`     | …c002         | 사람    | 받침대 덩어리를 꾹 눌러 든 순간 |
/// | `games/rummy/match/handle`     | `_games-rummy-match-handle`     | …c002         | 사람    | 손잡이로 묶음을 옮기는 중      |
/// | `games/rummy/match/reaction`   | `_games-rummy-match-reaction`   | …c002         | 사람    | 말풍선 셋(상대 둘 · 내 자리)    |
/// | `games/rummy/match/reaction-picker` | `_games-rummy-match-reaction-picker` | …c002 | 사람    | 반응 작은 판을 연다            |
/// | `games/rummy/match/exit`       | `_games-rummy-match-exit`       | …c002         | 사람    | 기권 확인을 연다               |
/// | `games/rummy/match/motion`     | `_games-rummy-match-motion`     | …c005         | 사람    | 정렬 · 묶음 이동 · 뽑기를 차례로 튼다(녹화용) |
/// | `games/rummy/match/rules`      | `_games-rummy-match-rules`      | …c002         | 사람    | 판 위에 규칙 시트를 연다(가로) |
/// | `games/rummy/match/leave`      | `_games-rummy-match-leave`      | …c002         | 사람    | 판(가로)을 열고 5초 뒤 게임 첫 화면으로(세로로 돌아오나) |
/// | `games/rummy/match/signout`    | `_games-rummy-match-signout`    | …c002         | 사람    | 판(가로)을 열고 5초 뒤 로그아웃(세로로 돌아오나) |
/// | `games/rummy/result`           | (없음 — 바깥 층)                 | …c004         | 사람    | 끝난 판 · 판돈 5 · 4인         |
/// | `games/rummy/result/board`     | (없음 — 바깥 층)                 | …c004         | 사람    | 결과의 [최종 판]               |
/// | `games/rummy/result/won`       | `_games-rummy-result-won`       | …c004         | 사람    | 내가 1등 · 판돈 10 · 2인        |
/// | `games/rummy/room/guest`       | `_games-rummy-room-guest`       | …c007         | 사람    | 손님으로 앉은 공개 방 · 2명    |
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
        case matchFull = "games/rummy/match/full"
        case matchOverview = "games/rummy/match/overview"
        case matchMany = "games/rummy/match/many"
        case matchNarrow = "games/rummy/match/narrow"
        case matchTiny = "games/rummy/match/tiny"
        case matchDragging = "games/rummy/match/dragging"
        case matchAttach = "games/rummy/match/attach"
        case matchPlacing = "games/rummy/match/placing"
        case matchRefused = "games/rummy/match/refused"
        case matchLifted = "games/rummy/match/lifted"
        case matchHandle = "games/rummy/match/handle"
        case matchReaction = "games/rummy/match/reaction"
        case matchReactionPicker = "games/rummy/match/reaction-picker"
        case matchExit = "games/rummy/match/exit"
        case matchMotion = "games/rummy/match/motion"
        case matchRules = "games/rummy/match/rules"
        case matchLeave = "games/rummy/match/leave"
        case matchSignOut = "games/rummy/match/signout"
        case result = "games/rummy/result"
        case resultBoard = "games/rummy/result/board"
        case resultWon = "games/rummy/result/won"
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
            case .matchMyTurn, .matchEdited, .matchElsewhere, .matchNarrow, .matchTiny, .matchPlacing, .matchLifted, .matchHandle,
                 .matchReaction, .matchReactionPicker, .matchExit, .matchRules, .matchLeave, .matchSignOut:
                return Self.myTurnID
            case .matchWaiting: return Self.waitingID
            case .matchFull, .matchOverview, .matchDragging, .matchRefused, .matchMotion: return Self.fullID
            case .matchMany, .matchAttach: return Self.manyID
            case .result, .resultBoard, .resultWon: return Self.resultID
            }
        }

        /// 이 기기가 손댄 판인가. 놀던 기기 장면만 아니다 — 데모는 앞 차례의 쓰기가 없어 장부가 비어 있으므로 라우트가 적어 준다.
        package var engages: Bool {
            switch self {
            case .lobby, .ranking, .rules, .matchElsewhere, .lobbyEmpty, .lobbyFailed, .lobbyShort, .lobbyUpdate, .lobbyMissing, .lobbyPeople, .lobbyBusy, .lobbySheet, .rankingFailed:
                return false
            case .room, .roomGuest, .matchMyTurn, .matchWaiting, .matchEdited, .matchFull, .matchOverview, .matchMany, .matchNarrow, .matchTiny, .matchDragging, .matchAttach,
                 .matchPlacing, .matchRefused, .matchLifted, .matchHandle, .matchReaction, .matchReactionPicker, .matchExit, .matchMotion, .matchRules, .matchLeave, .matchSignOut,
                 .result, .resultBoard, .resultWon:
                return true
            }
        }

        package var lobbyTab: LobbyTab { self == .ranking || self == .rankingFailed ? .ranking : .people }

        package static let roomID = UUID(uuidString: "d0000000-0000-4000-8000-00000000c001")!
        package static let myTurnID = UUID(uuidString: "d0000000-0000-4000-8000-00000000c002")!
        package static let waitingID = UUID(uuidString: "d0000000-0000-4000-8000-00000000c003")!
        package static let resultID = UUID(uuidString: "d0000000-0000-4000-8000-00000000c004")!
        package static let fullID = UUID(uuidString: "d0000000-0000-4000-8000-00000000c005")!
        package static let manyID = UUID(uuidString: "d0000000-0000-4000-8000-00000000c006")!
        package static let guestRoomID = UUID(uuidString: "d0000000-0000-4000-8000-00000000c007")!
    }

    /// 끌기 도중 모습 장면이 밟을 손 궤적(값 — 놓지 않고 렌더만 한다. 끌기 판정 자체는 `GamesRummyMatchInputTests` 가 값으로 잰다).
    package enum DemoTouch: Hashable, Sendable {
        /// 받침대 타일을 꾹 눌러 들기만.
        case lift(face: String)
        /// 받침대 타일 한 장을 묶음 오른끝 위로.
        case rackToMeld(face: String, meld: Int)
        /// 받침대 타일 한 장을 빈 펠트(논리 좌표) 위로.
        case rackToFelt(face: String, x: CGFloat, y: CGFloat)
        /// 받침대 덩어리를 꾹 눌러 빈 펠트(논리 좌표) 위로.
        case chainToFelt(face: String, x: CGFloat, y: CGFloat)
        /// 판 타일을 받침대 위로(거절).
        case boardToRack(face: String)
        /// 손잡이로 묶음을 빈 펠트(논리 좌표) 위로.
        case handle(set: Int, x: CGFloat, y: CGFloat)
    }

    package var demoTouch: DemoTouch? {
        switch scene {
        case .matchDragging: return .rackToMeld(face: "A9", meld: 0)
        case .matchAttach: return .rackToFelt(face: "A13", x: 408, y: 68)
        case .matchPlacing: return .chainToFelt(face: "A11", x: 120, y: 300)
        case .matchRefused: return .boardToRack(face: "A6")
        case .matchLifted: return .lift(face: "A11")
        case .matchHandle: return .handle(set: 0, x: 120, y: 330)
        default: return nil
        }
    }

    /// `match/motion` 장면이 묶음 하나를 옮겨 놓을 빈자리(논리 좌표).
    package static let motionDemoSpot = RummyPoint(x: 120, y: 380)

    /// 처음부터 [전체 보기]로 연다.
    package var demoFullView: Bool { scene == .matchOverview }

    /// 판 화면을 이 크기로 그린다(가장 작은 가로 칸 — 그 기기를 안 띄워도 눈으로 보는 자리).
    package var demoSize: CGSize? {
        switch scene {
        case .matchNarrow: return CGSize(width: 667, height: 354)
        case .matchTiny: return CGSize(width: 568, height: 320)
        default: return nil
        }
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
        if scene == .rules || scene == .matchRules { store.rulesShown = true }
    }

    /// `match/edited` 장면: 받침대의 A10 A11 A12 를 판 왼쪽 아래 빈자리에 낸 작업 판을 세운다(편집기가 선 뒤 한 번 · 다시 불러도 멱등).
    /// 받침대에서 3장 빠지고 묶음 하나가 늘어 첫 등록 33/30 점 — [완료]가 켜지는 장면이다.
    @MainActor
    package func applyEdit(to store: RummyStore) {
        guard scene == .matchEdited, let editor = store.editor, !editor.isChanged else { return }
        let wanted = ["A10", "A11", "A12"]
        let ids = wanted.compactMap { text in editor.rack.first { $0.face.text == text }?.id }
        guard ids.count == wanted.count else { return }
        store.moveTiles(ids, to: .newMeldAt(RummyPoint(x: 40, y: 330)))
    }
}
#endif

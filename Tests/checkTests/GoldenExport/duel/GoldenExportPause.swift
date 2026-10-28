// 원본: 없음 — W2-e 미니게임 자동 일시정지 골든 `pause/transitions`(G §8-2 "PauseState 전이 표를 W2-e 골든으로" · §8-3 `pause` 폴더).
// 원본 상태는 Sources/check/MiniGamePanel.swift 의 CheckMiniGameWindowView.PauseState @ 1b8260d. Kotlin 대조:
// multiplatform/core/stores/src/commonTest/…/minigame/MiniGamePauseGoldenTest.kt.
import CheckGoldenSupport
import Foundation
import Testing
@testable import check
@testable import CheckCore

// 전이 표: 다섯 상태(none · paused · resuming 1·2·3) × 진행 여부(참·거짓) 마다 toggled · resigningKey · steppedDown 과 읽기 셋
// (isFrozen · showsCard · countdown). 그리고 게임별 '접어도 기록이 남는가'(정지 상한을 거는가)와 상수 둘. 마지막으로 사건 열 두 벌 —
// 같은 규칙을 이어 붙였을 때의 상태 열(한 번씩만 재면 놓치는 조합: 정지 중 키 상실 · 카운트다운 중 키 상실 · 끝난 판의 ESC).
// ESC 의 창 대조(`escaped(eventWindow:gameWindow:isPlaying:)`)는 NSWindow 객체 판정이라 싣지 않는다 — 그 규칙의 몸통인 toggled 를 싣는다.

private typealias Pause = CheckMiniGameWindowView.PauseState

@MainActor
@Suite("GoldenExport pause — 미니게임 일시정지 전이(PauseState): 상태 5 × 진행 2 · 게임별 상한 · 사건 열")
struct GoldenExportPause {
    fileprivate static let states: [(String, Pause)] = [
        ("none", .none), ("paused", .paused), ("resuming-1", .resuming(1)), ("resuming-2", .resuming(2)), ("resuming-3", .resuming(3)),
    ]

    fileprivate static func name(_ state: Pause?) -> GoldenJSON {
        guard let state else { return .null }
        switch state {
        case .none: return "none"
        case .paused: return "paused"
        case .resuming(let n): return .string("resuming-\(n)")
        }
    }

    fileprivate static func reads(_ state: Pause) -> GoldenJSON {
        ["isFrozen": .bool(state.isFrozen), "showsCard": .bool(state.showsCard), "countdown": state.countdown.map(GoldenJSON.int) ?? .null]
    }

    /// 사건 열: "toggle"·"resign"·"step" 은 지금 진행 여부로, "play"·"stop" 은 진행 여부를 바꾼다(판이 시작됐다·끝났다).
    fileprivate static let sequences: [(String, [String])] = [
        ("walk-a", ["resign", "play", "resign", "resign", "toggle", "step", "resign", "toggle", "step", "step", "step", "step",
                    "toggle", "toggle", "step", "stop", "toggle", "resign", "play", "toggle", "step", "toggle", "toggle", "step"]),
        ("walk-b", ["play", "toggle", "toggle", "step", "step", "resign", "toggle", "stop", "step", "step", "step", "toggle",
                    "play", "resign", "step", "toggle", "step", "step", "step", "step"]),
    ]

    @Test("pause/transitions — 전이 표 10 · 게임 4 · 상수 · 사건 열 2")
    func transitions() {
        var cases: [GoldenJSON] = []
        for (id, state) in Self.states {
            for playing in [false, true] {
                cases.append([
                    "id": .string("\(id)-\(playing ? "playing" : "idle")"),
                    "state": .string(id),
                    "isPlaying": .bool(playing),
                    "toggled": Self.name(state.toggled(isPlaying: playing)),
                    "resigningKey": Self.name(state.resigningKey(isPlaying: playing)),
                    "steppedDown": Self.name(state.steppedDown()),
                    "reads": Self.reads(state),
                ])
            }
        }
        cases.append([
            "id": "quitting-keeps-the-score",
            "kinds": .array(MiniGameKind.allCases.map { kind in
                ["kind": .string(kind.rawValue), "keeps": .bool(Pause.quittingKeepsTheScore(kind))]
            }),
        ])
        cases.append(["id": "constants", "countdownStart": .int(Pause.countdownStart), "pauseLimitSeconds": .int(Pause.pauseLimitSeconds)])
        for (id, events) in Self.sequences {
            var state: Pause = .none
            var playing = false
            var trail: [GoldenJSON] = []
            for event in events {
                switch event {
                case "toggle": state = state.toggled(isPlaying: playing)
                case "resign": state = state.resigningKey(isPlaying: playing) ?? state
                case "step": state = state.steppedDown()
                case "play": playing = true
                case "stop": playing = false
                default: preconditionFailure(event)
                }
                trail.append(Self.name(state))
            }
            cases.append(["id": .string(id), "events": .array(events.map(GoldenJSON.string)), "trail": .array(trail)])
        }
        goldenEmit(GoldenFile(
            golden: "pause/transitions",
            equivalence: .bit,
            swiftSources: ["Sources/check/MiniGamePanel.swift", "Sources/CheckCore/MiniGameEngine.swift"],
            spec: [
                "state": "CheckMiniGameWindowView.PauseState — none · paused · resuming(n)(이름 'resuming-n')",
                "row": "toggled(isPlaying:) · resigningKey(isPlaying:)(null = 그대로 둔다) · steppedDown() · 읽기(isFrozen · showsCard · countdown)",
                "quitting-keeps-the-score": "PauseState.quittingKeepsTheScore(kind) — MiniGameKind.allCases 순서",
                "walk-*": "사건 열: toggle·resign·step 은 지금 진행 여부로, play·stop 은 진행 여부를 바꾼다. resign 이 null 이면 상태 유지. trail = 사건마다 뒤 상태",
            ],
            cases: cases
        ))
    }
}

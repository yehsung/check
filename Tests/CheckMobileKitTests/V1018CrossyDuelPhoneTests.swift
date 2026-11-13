@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.18 — 1:1 길건너(대표 지시 11-10 · 루비 그대로 #d_t103CxfPGinB). 맥 0.3.78 과 같은 서버 · 같은 코어 스토어.
@Suite("폰 1.0.18 — 1:1 길건너")
struct V1018CrossyDuelPhoneTests {
    @Test("겹 우선순위: 결과 > 판정 기다림 > 부활 > 카운트다운 · 로비 · 준비엔 없음(맥과 같은 판정)")
    func overlayPriority() {
        let snap = CrossyDuelRaceSnapshot(myScore: 40, opponentScore: 30, goal: 100, myDeaths: 1, opponentDeaths: 0,
                                          countdown: 2.2, remaining: 90, respawnIn: 1.4)
        #expect(CrossyDuelPhoneOverlay.resolve(phase: .finished, isFinished: true, outcome: .win, snapshot: snap) == .result(.win))
        #expect(CrossyDuelPhoneOverlay.resolve(phase: .playing, isFinished: false, outcome: nil, snapshot: snap) == .respawn("2"))
        var waiting = snap; waiting.waitingForResult = true
        #expect(CrossyDuelPhoneOverlay.resolve(phase: .playing, isFinished: false, outcome: nil, snapshot: waiting) == .waiting(goal: false))
        var goal = snap; goal.myScore = 100
        #expect(CrossyDuelPhoneOverlay.resolve(phase: .playing, isFinished: false, outcome: nil, snapshot: goal) == .waiting(goal: true))
        var counting = snap; counting.respawnIn = nil
        #expect(CrossyDuelPhoneOverlay.resolve(phase: .countdown, isFinished: false, outcome: nil, snapshot: counting) == .countdown("3"))
        #expect(CrossyDuelPhoneOverlay.resolve(phase: .ready, isFinished: false, outcome: nil, snapshot: snap) == nil)
        #expect(CrossyDuelPhoneOverlay.resolve(phase: .lobby, isFinished: false, outcome: nil, snapshot: nil) == nil)
    }

    @Test("로비 줄: 업데이트 필요 · 대결 중 · 집중이면 신청 못 함 · 근무 중/대결 가능은 신청")
    func userStatus() {
        #expect(CrossyDuelPhoneText.userStatus(CrossyDuelUser(id: "a", displayName: "가", isCapable: false)) == (CrossyDuelPhoneText.needsUpdate, false))
        #expect(CrossyDuelPhoneText.userStatus(CrossyDuelUser(id: "a", displayName: "가", inMatch: true)) == (CrossyDuelPhoneText.inMatch, false))
        #expect(CrossyDuelPhoneText.userStatus(CrossyDuelUser(id: "a", displayName: "가", isFocused: true)) == (CrossyDuelPhoneText.focused, false))
        #expect(CrossyDuelPhoneText.userStatus(CrossyDuelUser(id: "a", displayName: "가", isWorking: true)) == (CrossyDuelPhoneText.working, true))
        #expect(CrossyDuelPhoneText.userStatus(CrossyDuelUser(id: "a", displayName: "가")) == (CrossyDuelPhoneText.available, true))
        #expect(CrossyDuelPhoneText.stakeLine(5) == "5 · 이기면 +\(DuelFee.winnerNet(stake: 5))")
        #expect(CrossyDuelPhoneText.clock(65.2) == "1:06" && CrossyDuelPhoneText.rubyLine(-5) == "-5" && CrossyDuelPhoneText.rubyLine(0) == "±0")
    }

    @Test("배선: 앱 모델(호스트 · 시계 · 장부 · 순위 · 초인종 · 미션 · reset) · 러너(신호 · 조인) · 게임 탭(입구 막기 여섯 · 배지 · 화면) — 주석을 걷고 본다")
    @MainActor
    func wiring() throws {
        func code(_ path: String) throws -> String { try IntegrationContractTests.code(path).filter { !$0.isWhitespace } }
        let app = try code("Sources/CheckMobileKit/App/MobileAppModel.swift")
        for needle in ["letcrossyDuel=CrossyDuelStore()", "crossyDuel.attach(host:host)", "crossyDuel.deviceLedger.defaults=env.storage.defaults",
                       "crossyDuel.rankingEnabled=true", "realtime.crossyDuel=crossyDuel", "refreshAchievementsAfterGameResult(game:\"crossy_duel\")",
                       "crossyDuel.reset()"] {
            #expect(app.contains(needle), "앱 모델 배선이 없다: \(needle)")
        }
        let runner = try code("Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift")
        #expect(runner.contains("case.crossyDuelSignal:crossyDuel?.handleSignal()") && runner.contains("crossyDuel?.realtimeDidJoin()"))
        let games = try code("Sources/CheckMobileKit/Games/GamesStore.swift")
        // 다른 여섯 입구(오목 · 체스 · 테트리스 · 큐브 · 뒤집기 · 알까기)가 모두 길건너 판을 본다(알까기 입구는 마지막 줄 꼴).
        let ifForm = games.components(separatedBy: "ifhasLiveCrossyDuelMatch{return.crossyDuel}").count - 1
        let returnForm = games.components(separatedBy: "returnhasLiveCrossyDuelMatch?.crossyDuel:nil").count - 1
        #expect(ifForm + returnForm == 7, "일곱 입구(1.0.18 마작 포함) 중 길건너를 안 막는 곳이 있다(\(ifForm) + \(returnForm))")
        #expect(games.contains("+context.crossyDuel.visibleIncomingInvites.count"), "탭 배지가 길건너 받은 신청을 안 센다")
        #expect(games.contains("ifcontext.crossyDuel.holdsActivity{returntrue}"), "판 중 화면 꺼짐 방지가 길건너를 모른다")
        #expect(GamesBusyGame.crossyDuel.text == .crossyDuel && ChessPhoneText.BusyGame.crossyDuel.gameName == "1:1 길건너")
        #expect(ChessPhoneText.busyTitle(.crossyDuel) == "1:1 길건너 대결 중이에요")
        let tab = try code("Sources/CheckMobileKit/Games/GamesTab.swift")
        #expect(tab.contains("case.crossyDuel:GamesCrossyDuelScreen(store:store)") && tab.contains("crossyDuelCard"))
        #expect(MeText.dailyMissionCaption(game: "crossy_duel", detail: "맥에서 할 수 있어요").isEmpty)
    }
}

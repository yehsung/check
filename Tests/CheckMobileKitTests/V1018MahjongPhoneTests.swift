@testable import CheckCore
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.18 — 아잉 마작(대표 판 나누기 답 "한 판에 전부" #d_xB6BJcn2nsCq · 루비 그대로 #d_t103CxfPGinB). 맥 0.3.76 과 같은 서버 · 같은 코어 스토어.
@Suite("폰 1.0.18 — 아잉 마작")
struct V1018MahjongPhoneTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test("문구: 맥 `MahjongText` · 규칙 표와 글자가 같다(같은 서버 규칙을 두 기기가 다르게 말하지 않게) · 점수표 칸은 규칙 Swift 값")
    @MainActor
    func textMatchesMac() throws {
        let mac = try String(contentsOf: Self.root.appendingPathComponent("Sources/check/MahjongPanel.swift"), encoding: .utf8)
        for line in [GamesMahjongText.subtitle, GamesMahjongText.noRoomHint, GamesMahjongText.needFour, GamesMahjongText.unseenDrop,
                     GamesMahjongText.riichiArmedHint, GamesMahjongText.kuikaeHint, GamesMahjongText.furitenChip, GamesMahjongText.awayHint] {
            #expect(mac.contains("\"\(line)\""), "맥 문구와 갈렸다: \(line)")
        }
        #expect(GamesMahjongText.title == MahjongNoticeText.gameName)
        #expect(GamesMahjongText.split(stake: 5) == "1위 +10 · 2위 본전 · 3·4위 −5")
        #expect(GamesMahjongText.roundName(round: 1, handNo: 2) == "남 3국")
        #expect(GamesMahjongText.record(avg: nil, games: 3) == "3판 · 10판부터 순위")
        let rules = try String(contentsOf: Self.root.appendingPathComponent("Sources/check/MahjongPanelRules.swift"), encoding: .utf8)
        #expect(GamesMahjongRulesText.rules.count == 10)
        for line in GamesMahjongRulesText.rules { #expect(rules.contains("\"\(line.title)\""), "맥 규칙 제목과 갈렸다: \(line.title)") }
        #expect(GamesMahjongRulesText.yakuTable.count == 30 && GamesMahjongRulesText.yakumanList.count == 15)
        // 점수표 칸 — 자 30부 1판 론 1000 · 친 1500(손으로 적지 않고 규칙 Swift 에서 온다).
        #expect(GamesMahjongScoreCell.text(han: 1, fu: 30) == "1000/1500")
        #expect(GamesMahjongPhoneText.entrySymbol == MeText.dailyMissionIcon(game: "mahjong"), "카드 그림이 일일 미션 줄 · 맥 입구와 갈렸다")
    }

    @Test("화면 고르기: 연습판 = 판 · 내 자리 있는 진행 판 = 판 · 끝난 판은 [로비로] 전까지 판 · 문 닫힘 = 곧 열려요(연습판은 열림)")
    @MainActor
    func screenRule() {
        let store = MahjongStore()
        #expect(GamesMahjongScreenRule.of(store, dismissedMatchID: nil) == .lobby)
        var payload = MahjongStatePayload()
        payload.match = MahjongStateMatch(id: "m1", status: "active")
        payload.mySeat = 2
        store.match = payload
        #expect(GamesMahjongScreenRule.of(store, dismissedMatchID: nil) == .table)
        store.match?.match?.status = "finished"
        #expect(GamesMahjongScreenRule.of(store, dismissedMatchID: nil) == .table, "끝난 판의 결과를 못 본다")
        #expect(GamesMahjongScreenRule.of(store, dismissedMatchID: "m1") == .lobby, "[로비로] 를 눌러도 판이 남는다")
        store.match?.match?.status = "forming"
        #expect(GamesMahjongScreenRule.of(store, dismissedMatchID: nil) == .lobby, "방은 로비에서 보인다")
        store.availability = .serverMissing
        #expect(GamesMahjongScreenRule.of(store, dismissedMatchID: nil) == .unavailable)
    }

    @Test("가로 판 칸: 흔한 폰 가로 크기에서 펠트 · 손 · 양옆 열이 화면 안이고 서로 안 겹친다 · 펠트는 맥 884×502 비율 그대로")
    func tableLayoutFits() {
        for size in [CGSize(width: 734, height: 372), CGSize(width: 667, height: 375), CGSize(width: 812, height: 354),
                     CGSize(width: 874, height: 402), CGSize(width: 568, height: 320)] {
            let layout = GamesMahjongTableLayout(size: size)
            let bounds = CGRect(origin: .zero, size: size)
            for rect in [layout.felt, layout.hand, layout.info, layout.chrome, layout.leftSeat, layout.mySeat, layout.topSeat,
                         layout.rightSeat, layout.aids, layout.actions] {
                #expect(bounds.contains(rect.insetBy(dx: 0.5, dy: 0.5)), "\(size): 화면 밖 \(rect)")
            }
            #expect(!layout.felt.intersects(layout.hand) && !layout.felt.intersects(layout.leftSeat)
                    && !layout.felt.intersects(layout.rightSeat) && !layout.felt.intersects(layout.actions), "\(size): 펠트가 겹친다")
            #expect(!layout.hand.intersects(layout.actions), "\(size): 손이 동작 열 밑으로 들어간다")
            #expect(abs(layout.felt.width / layout.felt.height - 884.0 / 502.0) < 0.01)
            // 손 열네 장 + 쯔모 간격이 손 칸에 든다(부로 없음 — 가장 긴 꼴).
            let tileW = layout.handTileHeight * MahjongTileSize.hand.width / MahjongTileSize.hand.height
            #expect(tileW * 14 + 8 <= layout.hand.width + 0.5, "\(size): 손 열네 장이 안 든다")
            // iOS 18 이 도는 가장 작은 폰(SE 2·3 — 667×375)에서도 손패 폭 30pt 이상.
            if size.width >= 667 { #expect(tileW >= 30, "\(size): 손패가 너무 작다(누르기 어렵다): \(tileW)") }
        }
    }

    @Test("펠트 배치는 맥과 같은 값이다(가운데 판 · 강 칸 · 손 띠) · 강 27장(이론 최대)도 칸 안")
    func feltGeometryMatchesMac() {
        #expect(GamesMahjongFeltLayout.center == CGRect(x: 361, y: 188, width: 162, height: 162))
        #expect(GamesMahjongFeltLayout.riverLane(.bottom) == CGRect(x: 361, y: 354, width: 483, height: 144))
        #expect(GamesMahjongFeltLayout.riverLane(.left) == CGRect(x: 165, y: 188, width: 192, height: 310))
        #expect(GamesMahjongFeltLayout.handStripRect(.top) == CGRect(x: 40, y: 4, width: 804, height: 32))
        let discards = (0..<GamesMahjongFeltLayout.riverWorstCount).map { _ in MahjongDiscard(tile: MahjongTiles.parse("1m")![0]) }
        for compass in MahjongCompass.allCases {
            let lane = GamesMahjongFeltLayout.riverLane(compass)
            for tile in GamesMahjongFeltGeometry.river(discards, compass: compass) {
                #expect(lane.insetBy(dx: -0.5, dy: -0.5).contains(tile.rect), "\(compass): 강 패가 칸 밖 \(tile.rect)")
            }
        }
    }

    @Test("보조: 폰은 '두 번 눌러 버리기'를 켠 채로 처음 한 번 심는다 · 사용자가 끈 값은 다시 켜지 않는다")
    @MainActor
    func phoneAidsSeed() throws {
        let suite = "v1018-mahjong-aids-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MahjongStore()
        store.aidsDefaults = defaults
        #expect(!store.aids.twoClickDiscard, "전제: 맥 기본은 꺼짐")
        GamesMahjongPhoneAids.seedIfNeeded(store, defaults: defaults)
        #expect(store.aids.twoClickDiscard)
        store.aids.twoClickDiscard = false
        GamesMahjongPhoneAids.seedIfNeeded(store, defaults: defaults)
        #expect(!store.aids.twoClickDiscard, "끈 값을 다시 켰다")
    }

    @Test("더블론 넘김: 화료자 둘이면 쉬는 시간 11초 안에서 차례로(맥 D48 과 같은 식)")
    func resultPaging() {
        let next = Date(timeIntervalSince1970: 1_000)
        #expect(GamesMahjongResultPaging.restSeconds(winners: 2) == 11)
        #expect(GamesMahjongResultPaging.index(winners: 1, nextHand: next, now: next) == 0)
        #expect(GamesMahjongResultPaging.index(winners: 2, nextHand: next, now: next.addingTimeInterval(-10.5)) == 0)
        #expect(GamesMahjongResultPaging.index(winners: 2, nextHand: next, now: next.addingTimeInterval(-2)) == 1)
    }

    @Test("배선: 앱 모델(시계 · 호스트 · 장부 · 보조 · 순위 · 초인종 · 미션 · reset) · 러너 · 게임 탭(여덟째 입구 막기 · 배지 · 카드 · 화면 · 가로 · 화면 꺼짐) — 주석을 걷고 본다")
    @MainActor
    func wiring() throws {
        func code(_ path: String) throws -> String { try IntegrationContractTests.code(path).filter { !$0.isWhitespace } }
        let app = try code("Sources/CheckMobileKit/App/MobileAppModel.swift")
        for needle in ["letmahjong=MahjongStore(clock:{clock.now()})", "mahjong.attach(host:host)", "mahjong.deviceLedger.defaults=env.storage.defaults",
                       "mahjong.aidsDefaults=env.storage.defaults", "GamesMahjongPhoneAids.seedIfNeeded(mahjong,defaults:env.storage.defaults)",
                       "mahjong.rankingEnabled=true", "realtime.mahjong=mahjong",
                       "mahjong.onMatchFinished={[weakme]inme?.refreshAchievementsAfterGameResult(game:\"mahjong\")}", "mahjong.reset()"] {
            #expect(app.contains(needle), "앱 모델 배선이 없다: \(needle)")
        }
        let runner = try code("Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift")
        #expect(runner.contains("case.mahjongSignal:mahjong?.handleSignal()") && runner.contains("mahjong?.realtimeDidJoin()"))
        let games = try code("Sources/CheckMobileKit/Games/GamesStore.swift")
        #expect(games.components(separatedBy: "returnhasLiveMahjongSeat?.mahjong:nil").count - 1 == 7, "일곱 입구 중 마작을 안 막는 곳이 있다")
        #expect(games.contains("+context.mahjong.visibleInvites.count"), "탭 배지가 마작 초대를 안 센다")
        #expect(games.contains("context.mahjong.presentWindow={[weakself]inself?.presentMahjongScreen()}"))
        #expect(games.contains("ifmahjongWantsLandscape{return.landscape}"), "마작 판이 가로로 안 돈다")
        #expect(games.contains("ifisMahjongScreenVisible,context.mahjong.phase==.playing{returntrue}"), "판 중 화면 꺼짐 방지가 마작을 모른다")
        #expect(games.contains("syncMahjongHiddenPeers()context.mahjong.refreshLobbyIfStale()"), "허브가 마작 초대를 안 당긴다")
        #expect(GamesBusyGame.mahjong.text == .mahjong && ChessPhoneText.busyTitle(.mahjong) == "아잉 마작을 하는 중이에요")
        let tab = try code("Sources/CheckMobileKit/Games/GamesTab.swift")
        #expect(tab.contains("case.mahjong:GamesMahjongScreen(store:store)") && tab.contains("mahjongCard.padding(.top,12)"))
        #expect(MeText.dailyMissionCaption(game: "mahjong", detail: "맥에서 할 수 있어요").isEmpty)
        let table = try code("Sources/CheckMobileKit/Games/GamesMahjongTable.swift")
        #expect(table.contains(".hidesTabBar(for:.mahjongMatch)"), "판 화면이 탭 막대를 안 숨긴다")
        // 단추는 결정에 있는 것만 — 판 화면이 스스로 판정해 단추를 켜지 않는다(맥 SPEC §4 머리).
        #expect(table.contains("switchstore.myDecision{"), "동작 열이 결정을 안 읽는다")
    }

    @Test("한 사람 한 판: 마작 방에 앉거나 판을 두면 일곱 입구가 막히고, 다른 판이 흐르면 마작 입구가 그 이름으로 막힌다 · 가로는 판일 때만")
    @MainActor
    func entryBlocks() async throws {
        let harness = GamesHarness(label: "v1018-mahjong-entry")
        let games = harness.model.games
        let mahjong = harness.model.mahjong
        #expect(games.mahjongEntryBlock == nil && !games.hasLiveMahjongSeat)
        var payload = MahjongStatePayload()
        payload.match = MahjongStateMatch(id: "00000000-0000-0000-0000-0000000000c1", status: "forming")
        mahjong.match = payload
        #expect(games.hasLiveMahjongSeat, "방에 앉은 것을 자리로 안 본다(서버 joined 도 busy)")
        #expect(games.gomokuEntryBlock == .mahjong && games.chessEntryBlock == .mahjong && games.tetrisEntryBlock == .mahjong)
        #expect(games.rummyEntryBlock == .mahjong && games.reversiEntryBlock == .mahjong && games.crossyDuelEntryBlock == .mahjong
                && games.alkkagiEntryBlock == .mahjong)
        #expect(games.mahjongEntryBlock == nil, "자기 방으로 자기 입구를 막는다")
        #expect(games.rummyInterfaceOrientation == .portrait, "화면이 안 보이는데 가로다")
        mahjong.match?.match?.status = "cancelled"
        #expect(!games.hasLiveMahjongSeat && games.gomokuEntryBlock == nil, "닫힌 방이 입구를 막는다")
        mahjong.match = nil
        await harness.tearDown()
    }
}

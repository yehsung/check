import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 마작 **화면** 렌더(SPEC §5 · §6.3 U 줄 V03xxMahjongPanelRenderTests) — 로비 · 방(4석·[시작]) · 내 차례(손·동작 열·시계) ·
// 울기 프롬프트 있음/없음 · 리치 무장 흐림 · `wait` "기다리는 중" · 남의 차례 · 자리 비움 · 국 결과(화료·유국) · 판 결과 ·
// 규칙·역·점수표 · 연습 시작 · 연습 탁자 + 방 띠 · 배율 0.82.
//
// 전부 ImageRenderer(scale 2)로 `CheckRenderSettle` 이 굳힌 뒤 잰다. PNG 는 `MAHJONG_RENDER_DIR` 을 줄 때만 그 폴더에 남긴다(사람이 본다).
// ★ "노란 상자 0" 을 감지기로 쓰지 않는다. **패는 밝은 크림 덩어리**로 잰다 — 펠트·칸·덮개는 중간 톤이고 패 몸체만 극단 밝기라
//   '손 칸의 큰 크림 덩어리 수 = 그려진 패 수'다(흐린 패 — 못 버리는 패 — 는 크림이 아니다).
// ★ 상태는 스토어 문(`applyState` · `applyLobby`)과 `package internal(set)` 칸으로 심는다. S2 서버 픽스처가 아직 없어
//   §3.6 모양의 **손 픽스처**(JSON → 와이어 디코드)를 쓴다 — 픽스처가 오면 원문으로 바꾼다. 스토어에 host 를 물린 장면(방장)은
//   스텁 서비스라 네트워크가 한 건도 안 나간다. 시각은 `store.clock` 으로 고정한다.

@MainActor
@Suite("아잉 마작 화면 렌더", .serialized)
struct V03xxMahjongPanelRenderTests {
    // MARK: ① 로비

    @Test(.gomokuDefaultsCleanup)
    func lobbyDrawsPeopleRoomAndJoinables() throws {
        // 없으면: 로비가 크롬(카드 테두리·제목)만 그리고 사람·초대·공개 방이 비어도 초록이다.
        let filled = try mjLobbyStore()
        #expect(filled.visibleUsers.count == 4 && filled.visibleInvites.count == 1 && filled.publicRooms.count == 1)
        #expect(filled.record?.games == 12)
        let full = try mjBitmap(mjPanel(filled))
        let bare = try mjBitmap(mjPanel(MahjongStore(clock: { mjNow })))
        mjSave(full, "lobby")
        #expect(full.pixelsWide == 2480 && full.pixelsHigh == 1400)
        let left = CGRect(x: 20, y: 72, width: 440, height: 608)
        let joinRow = CGRect(x: 480, y: 504, width: 740, height: 176)
        #expect(mjInk(full, left) > mjInk(bare, left) + 4_000, "사람 목록이 안 그려졌다")
        #expect(mjInk(full, joinRow) > 8_000, "받은 초대·공개 방 카드가 안 그려졌다")
        // 전적 캡슐 문구(값) — 10판 이상이면 평균 등수.
        #expect(MahjongText.record(avg: 2.25, games: 12) == "평균 2.25등 · 12판")
        #expect(MahjongText.record(avg: 2.0, games: 7) == "7판 · 10판부터 순위")
        let ranking = try mjBitmap(mjPanel(filled, tab: .ranking))
        mjSave(ranking, "lobby-ranking")
        #expect(mjMaxDiff(ranking, full, left) > 60, "순위 탭이 사람 탭과 같게 그려졌다")
    }

    // MARK: ② 방

    @Test(.gomokuDefaultsCleanup)
    func roomOfFourShowsStartForHost() throws {
        // 없으면: 넷이 모였는데 방장에게 [시작]이 안 서거나, 셋일 때도 [시작]이 켜져도 초록이다(카드 ③).
        let four = try mjHostedStore("room-four")
        #expect(four.applyState(try mjDecode(mjRoom(joined: 4))) == .applied)
        #expect(four.phase == .room && four.isHost && four.canStart)
        let three = try mjHostedStore("room-three")
        three.applyState(try mjDecode(mjRoom(joined: 3)))
        #expect(three.isHost && !three.canStart)
        let fourBitmap = try mjBitmap(mjPanel(four))
        let threeBitmap = try mjBitmap(mjPanel(three))
        mjSave(fourBitmap, "room-four")
        mjSave(threeBitmap, "room-three")
        let buttons = CGRect(x: 494, y: 520, width: 712, height: 100)
        #expect(mjMaxDiff(fourBitmap, threeBitmap, buttons) > 60, "넷과 셋의 [시작] 줄이 같다")
    }

    // MARK: ③ 내 차례

    @Test
    func myTurnDrawsEveryHandTileAndMyClock() throws {
        // 없으면: 손패가 빠지거나(잉크 덩어리 수 ≠ my_hand + my_drawn) 내 시계 링이 안 서도 초록이다.
        let store = try mjTableStore(mjActive())
        let bitmap = try mjBitmap(mjPanel(store, hover: 2))
        mjSave(bitmap, "my-turn")
        let tiles = mjCreamBlobs(bitmap, rect: mjHandProbe, minHeight: 100)
        #expect(tiles == 14, "손 잉크 덩어리 \(tiles) — my_hand 13 + my_drawn 1 이어야")
        // 결정이 없는 같은 판(기준선) — 내 링·ACTIONS 가 사라진다.
        let idle = try mjBitmap(mjPanel(try mjTableStore(mjActive { $0["my_decision"] = NSNull() })))
        #expect(mjMaxDiff(bitmap, idle, mjBody(MahjongMatchLayout.mySeat).insetBy(dx: 4, dy: 4)) > 60, "내 시계 링이 안 그려졌다")
        #expect(mjInk(bitmap, mjBody(MahjongMatchLayout.actions)) > 1_000 && mjInk(idle, mjBody(MahjongMatchLayout.actions)) < 50)
    }

    @Test
    func riichiArmedDimsAllButTheDeclarableTiles() throws {
        // 없으면: 리치 무장 뒤에도 모든 패가 밝아(로컬 판정이 몰래 쓰이거나 무장을 무시) 아무 패나 눌러도 초록이다.
        let store = try mjTableStore(mjActive())
        store.armRiichi()
        #expect(store.riichiArmed)
        let bitmap = try mjBitmap(mjPanel(store))
        mjSave(bitmap, "riichi-armed")
        #expect(mjCreamBlobs(bitmap, rect: mjHandProbe, minHeight: 100) == 2, "리치 선언패 둘만 밝아야 한다")
    }

    // MARK: ④ 울기 프롬프트

    @Test
    func callPromptDrawsActionsOnlyWhenOffered() throws {
        // 없으면: 울 수 없는 사람에게도 ACTIONS 가 그려지거나(정보 누출) 울 수 있는데 비어도 초록이다.
        let offered = try mjBitmap(mjPanel(try mjTableStore(mjCall())))
        let quiet = try mjBitmap(mjPanel(try mjTableStore(mjCall { $0["my_decision"] = NSNull() })))
        mjSave(offered, "call-prompt")
        mjSave(quiet, "call-none")
        let actions = mjBody(MahjongMatchLayout.actions)
        #expect(mjInk(offered, actions) > 1_000, "울기 프롬프트 ACTIONS 가 비었다")
        #expect(mjInk(quiet, actions) < 50, "선택지가 없는데 ACTIONS 에 잉크가 있다")
        // 같은 판에서 한 칸만 바꿨다 — ACTIONS 밖(탁자)은 같아야 기준선이다.
        #expect(mjMaxDiff(offered, quiet, mjBody(MahjongMatchLayout.felt).insetBy(dx: 4, dy: 4)) <= 8)
    }

    @Test
    func waitingShowsOnlyAfterThePauseEnds() throws {
        // 없으면: 울기 창이 열리자마자 "기다리는 중…"을 띄워 '누가 울 수 있다'가 새거나(CC-11), 오래 기다려도 아무 말이 없어 초록이다.
        let wakeMs = mjNowMs + 1_000
        let early = try mjTableStore(mjCall(wakeMs: wakeMs) { $0["my_decision"] = NSNull() })
        early.clock = { Date(timeIntervalSince1970: (wakeMs - 500) / 1_000) }
        let late = try mjTableStore(mjCall(wakeMs: wakeMs) { $0["my_decision"] = NSNull() })
        late.clock = { Date(timeIntervalSince1970: (wakeMs + 2_000) / 1_000) }
        let before = try mjBitmap(mjPanel(early))
        let after = try mjBitmap(mjPanel(late))
        mjSave(after, "wait-2s")
        let band = mjWaitingBand
        // 밝은 글자 잉크만(가운데 판 바탕은 중간 톤).
        func bright(_ bitmap: NSBitmapImageRep) -> Int { mjCount(bitmap, band) { r, g, b in max(r, g, b) >= 180 } }
        print("[기다리는 중] 멈춤 끝 −0.5초 잉크 \(bright(before)) · +2초 \(bright(after))")
        #expect(bright(before) == 0, "멈춤 끝 전에 '기다리는 중' 이 떴다")
        #expect(bright(after) > 80, "멈춤 끝 + 2초인데 '기다리는 중' 이 없다")
    }

    // MARK: ⑤ 남의 차례 · 자리 비움

    @Test
    func othersTurnHasNoRingOrNumberOnTheirCard() throws {
        // 없으면: 남의 자리 카드에 남은 초·링을 그려(남의 예비를 모르니 거짓 숫자 — CC-25) 초록이다.
        let theirs = try mjBitmap(mjPanel(try mjTableStore(mjActive(turnSeat: 1) { $0["my_decision"] = NSNull() })))
        let elsewhere = try mjBitmap(mjPanel(try mjTableStore(mjActive(turnSeat: 2) { $0["my_decision"] = NSNull() })))
        mjSave(theirs, "their-turn")
        let interior = mjBody(MahjongMatchLayout.rightSeat).insetBy(dx: 6, dy: 6)
        let diff = mjMaxDiff(theirs, elsewhere, interior)
        print("[남의 차례] 오른쪽 카드 안쪽 차이 \(diff)")
        #expect(diff <= 8, "남의 차례인 자리 카드 안에 무언가(링·숫자)가 더 그려졌다")
        // 기준선: 빛줄은 가운데 판에서 갈린다(차례 표시 자체는 있다).
        let board = CGRect(x: 520, y: 242, width: 200, height: 200)
        #expect(mjMaxDiff(theirs, elsewhere, board) > 60)
    }

    @Test
    func awaySeatShowsComeBackInActions() throws {
        // 없으면: 자리 비움인데 ACTIONS 에 [돌아왔어요]가 없어(사람 눈이 있는 자리) 돌아올 길이 손패 누르기뿐이어도 초록이다.
        let away = try mjTableStore(mjActive { state in
            state["my_decision"] = NSNull()
            state["my_away"] = ["reason": "leave", "since_ms": mjNowMs - 20_000, "back_ready_ms": mjNowMs - 1_000]
            var seats = state["seats"] as! [[String: Any]]
            seats[0]["away"] = true
            state["seats"] = seats
        })
        let bitmap = try mjBitmap(mjPanel(away))
        mjSave(bitmap, "away")
        let actions = mjBody(MahjongMatchLayout.actions)
        #expect(mjCount(bitmap, actions) { r, g, b in r > 220 && g > 150 && g < 210 && b < 120 } > 2_000,
                "자리 비움 [돌아왔어요](주황)가 ACTIONS 에 없다")
    }

    // MARK: ⑥ 국 결과 · 판 결과

    @Test
    func handResultCards() throws {
        // 없으면: 국 결과 카드가 비거나(화료 손·역·점수 이동) 유국이 화료 꼴로 그려져도 초록이다.
        let win = try mjBitmap(mjPanel(try mjTableStore(mjHandEnd(win: true))))
        let draw = try mjBitmap(mjPanel(try mjTableStore(mjHandEnd(win: false))))
        let plain = try mjBitmap(mjPanel(try mjTableStore(mjActive { $0["my_decision"] = NSNull() })))
        mjSave(win, "hand-result-win")
        mjSave(draw, "hand-result-draw")
        let card = mjBody(CGRect(x: MahjongMatchLayout.felt.midX - 300, y: MahjongMatchLayout.felt.midY - 200, width: 600, height: 400))
        #expect(mjMaxDiff(win, plain, card) > 60 && mjMaxDiff(draw, plain, card) > 60)
        #expect(mjMaxDiff(win, draw, card) > 60, "화료와 유국이 같은 카드다")
        // 화료 손(40×54) 14장이 크림 덩어리로 선다.
        let handRow = mjBody(CGRect(x: MahjongMatchLayout.felt.midX - 282, y: MahjongMatchLayout.felt.midY - 200 + 52,
                                    width: 564, height: 58))
        #expect(mjCreamBlobs(win, rect: handRow, minHeight: 80) == 14, "화료 손 패 수가 틀리다")
    }

    @Test
    func matchResultCard() throws {
        // 없으면: 판 결과가 등수·루비 줄 없이 빈 카드여도 초록이다.
        let store = try mjTableStore(mjFinished())
        #expect(store.phase == .finished)
        let bitmap = try mjBitmap(mjPanel(store))
        mjSave(bitmap, "match-result")
        let card = mjBody(CGRect(x: MahjongMatchLayout.felt.midX - 320, y: MahjongMatchLayout.felt.midY - 220, width: 640, height: 440))
        #expect(mjInk(bitmap, card) > 20_000)
        #expect(MahjongText.split(stake: 5) == "1위 +10 · 2위 본전 · 3·4위 −5")
    }

    // MARK: ⑦ 규칙 · 연습

    @Test
    func rulesAndPracticeSheets() throws {
        // 없으면: 덮개 셋(규칙·역·점수표)과 연습 시작 시트가 빈 카드여도 초록이다.
        let store = try mjLobbyStore()
        let lobby = try mjBitmap(mjPanel(store))
        let center = CGRect(x: 300, y: 150, width: 640, height: 400)
        for (tab, name) in [(MahjongRulesTab.rules, "rules"), (.yaku, "rules-yaku"), (.scores, "rules-scores")] {
            let bitmap = try mjBitmap(mjPanel(store, overlay: .rules(tab)))
            mjSave(bitmap, name)
            #expect(mjMaxDiff(bitmap, lobby, center) > 60, "\(name) 가 안 그려졌다")
        }
        let practice = try mjBitmap(mjPanel(store, overlay: .practiceStart))
        mjSave(practice, "practice-start")
        #expect(mjMaxDiff(practice, lobby, center) > 60)
        // 규칙 문구에 다른 서비스 이름이 없다(상표 — 값으로).
        let text = MahjongRulesText.rules.map { $0.title + $0.detail }.joined() + MahjongRulesText.footer
        #expect(!text.contains("작" + "혼") && !text.contains("천" + "봉"))
    }

    @Test
    func practiceTableWithRoomBand() throws {
        // 없으면: 방에서 넷째를 기다리며 연습하는 동안 방 띠가 안 서(방이 찼는지 모른다 — CC-02) 초록이다.
        let store = MahjongStore(clock: { mjNow })
        store.match = try mjDecode(mjRoom(joined: 3))
        let practicePayload = try mjDecode(mjActive(matchID: "ai-practice-1"))
        store.practice = MahjongPracticeSession(matchID: "ai-practice-1", format: .tonpuu, timed: false, humanSeat: 0,
                                                generation: 1, payload: practicePayload)
        store.showsPractice = true
        #expect(store.isPractice && store.roomBand?.joined == 3)
        let bitmap = try mjBitmap(mjPanel(store))
        mjSave(bitmap, "practice-room-band")
        let bandRect = mjBody(CGRect(x: MahjongMatchLayout.felt.midX - 260, y: MahjongMatchLayout.felt.minY + 8, width: 520, height: 40))
        let noBand = MahjongStore(clock: { mjNow })
        noBand.practice = store.practice
        noBand.showsPractice = true
        let plain = try mjBitmap(mjPanel(noBand))
        #expect(mjMaxDiff(bitmap, plain, bandRect) > 60, "방 띠가 안 그려졌다")
        #expect(mjCreamBlobs(bitmap, rect: mjHandProbe, minHeight: 100) == 14, "연습판도 table 한 길로 손을 그린다")
    }

    // MARK: ⑦-2 처음이에요(U2)

    @Test
    func firstTimeGuidePagesAndTheRulesReopenButton() throws {
        // 없으면: '처음이에요' 네 장이 빈 카드거나 모두 같은 장으로 그려지거나(장 넘김이 안 됨), 예시 손이 안 서거나,
        // [규칙] 창에 [처음이에요 다시 보기]가 없어도 초록이다.
        let store = try mjLobbyStore()
        let lobby = try mjBitmap(mjPanel(store))
        let launch = MahjongPracticeLaunch(format: .tonpuu, timed: false)
        let size = MahjongFirstTimeGuideSheet.size
        let card = CGRect(x: (MahjongWindowLayout.contentSize.width - size.width) / 2,
                          y: (MahjongWindowLayout.contentSize.height - size.height) / 2, width: size.width, height: size.height)
        var pages: [NSBitmapImageRep] = []
        for page in 0..<4 {
            let bitmap = try mjBitmap(mjPanel(store, overlay: .firstTime(page: page, launch: page == 3 ? launch : nil)))
            mjSave(bitmap, "first-time-\(page + 1)")
            #expect(mjMaxDiff(bitmap, lobby, card) > 60, "\(page + 1)장이 안 그려졌다")
            pages.append(bitmap)
        }
        for a in 0..<4 { for b in (a + 1)..<4 { #expect(mjMaxDiff(pages[a], pages[b], card) > 60, "\(a + 1)장과 \(b + 1)장이 같다") } }
        // 첫 장 예시 손(123m456p789s11122z = 14장, 34×46)이 크림 덩어리로 선다.
        #expect(mjCreamBlobs(pages[0], rect: card, minHeight: 80) == 14, "예시 손 패 수가 틀리다")
        // [규칙] 탭에만 [처음이에요 다시 보기](오른쪽 아래) — 역 탭과 그 자리가 다르다.
        let rules = try mjBitmap(mjPanel(store, overlay: .rules(.rules)))
        let yaku = try mjBitmap(mjPanel(store, overlay: .rules(.yaku)))
        let sheet = MahjongWindowLayout.rulesSize
        let origin = CGPoint(x: (MahjongWindowLayout.contentSize.width - sheet.width) / 2,
                             y: (MahjongWindowLayout.contentSize.height - sheet.height) / 2)
        let reopen = CGRect(x: origin.x + sheet.width - 20 - 170, y: origin.y + sheet.height - 20 - 28, width: 170, height: 28)
        #expect(mjInk(rules, reopen) > 300 && mjMaxDiff(rules, yaku, reopen) > 60, "[처음이에요 다시 보기]가 없다")
    }

    // MARK: ⑦-3 반응 덮개(U2)

    @Test
    func reactionBubbleStandsAtTheSenderSeatAndTheButtonOnlyInRubyMatches() throws {
        // 없으면: 받은 반응이 안 그려지거나 보낸 사람 자리(상가 = 왼쪽 카드 옆)가 아닌 곳에 서거나,
        // [반응] 단추가 루비 판에 없거나 연습판(스토어가 안 보낸다)에 있어도 초록이다.
        let store = try mjTableStore(mjActive { state in
            state["reactions"] = [["seat_no": 3, "key": "joy", "at_ms": mjNowMs - 400, "user_id": mjPeople[3].id]]
        })
        let feed = MahjongReactionFeed()
        feed.ingest(try #require(store.table), now: mjNow, serverOffset: store.serverClockOffset)
        #expect(feed.bubbles.map(\.seatNo) == [3])
        // 화면이 스스로 먹인다(새 공급기 — `onChange(initial:)`). 기준선은 반응 없는 같은 판.
        let with = try mjBitmap(mjPanel(store, feed: MahjongReactionFeed()))
        let without = try mjBitmap(mjPanel(try mjTableStore(mjActive()), feed: MahjongReactionFeed()))
        mjSave(with, "reaction")
        let side = RummyReactionBubbleView.height
        let left = mjBody(MahjongMatchLayout.leftSeat)
        let bubble = CGRect(x: left.maxX + 6, y: left.midY - side / 2, width: side, height: side)
        #expect(mjMaxDiff(with, without, bubble) > 60, "상가 자리 옆에 말풍선이 없다")
        let right = mjBody(MahjongMatchLayout.rightSeat)
        let elsewhere = CGRect(x: right.minX - 6 - side, y: right.midY - side / 2, width: side, height: side)
        #expect(mjMaxDiff(with, without, elsewhere) <= 8, "말풍선이 하가 쪽에도 섰다")
        // [반응]: 루비 판 CL 줄 끝에만.
        let practice = MahjongStore(clock: { mjNow })
        practice.practice = MahjongPracticeSession(matchID: "ai-practice-1", format: .tonpuu, timed: false, humanSeat: 0,
                                                   generation: 1, payload: try mjDecode(mjActive(matchID: "ai-practice-1")))
        practice.showsPractice = true
        let practiceBitmap = try mjBitmap(mjPanel(practice))
        let chrome = mjBody(MahjongMatchLayout.chromeLeft)
        let button = CGRect(x: chrome.maxX - MahjongMatchLayout.reactionButtonWidth + 4, y: chrome.minY + 10,
                            width: MahjongMatchLayout.reactionButtonWidth - 8, height: chrome.height - 20)
        #expect(mjMaxDiff(without, practiceBitmap, button) > 60, "[반응] 단추가 루비 판에만 있지 않다")
    }

    // MARK: ⑦-3b 지금 될 수 있는 역(U2)

    @Test
    func yakuSheetDotsTheYakuMyTenpaiHandWouldBring() throws {
        // 없으면: 판에서 연 역 목록에 '지금 될 수 있는 역' 점이 없거나, 텐파이가 아닌 손에도 점·안내 줄이 그려져도 초록이다.
        // 내 손 123m456p789s 東東南南(친 · 동장) — 대기 東·南 → 장풍·자풍(東) · 멘젠쯔모.
        let tenpai = try mjTableStore(mjActive(turnSeat: 3))
        #expect(MahjongPossibleYaku.of(try #require(tenpai.table)) == [.bakaze, .jikaze, .menzenTsumo])
        let notTenpai = try mjTableStore(mjActive())   // 쯔모한 적5만을 쥔 14장 — 화료 꼴 아님
        #expect(MahjongPossibleYaku.of(try #require(notTenpai.table)).isEmpty)
        let lobby = try mjBitmap(mjPanel(try mjLobbyStore(), overlay: .rules(.yaku)))
        let dotted = try mjBitmap(mjPanel(tenpai, overlay: .rules(.yaku)))
        let plain = try mjBitmap(mjPanel(notTenpai, overlay: .rules(.yaku)))
        mjSave(dotted, "rules-yaku-possible")
        let sheet = MahjongWindowLayout.rulesSize
        let inner = CGRect(x: (MahjongWindowLayout.contentSize.width - sheet.width) / 2 + 20,
                           y: (MahjongWindowLayout.contentSize.height - sheet.height) / 2 + 60, width: sheet.width - 40,
                           height: sheet.height - 120)
        #expect(mjMaxDiff(plain, lobby, inner) <= 8, "텐파이가 아닌 손에 점이 찍혔다")
        #expect(mjMaxDiff(dotted, lobby, inner) > 60, "점이 없다")
    }

    // MARK: ⑦-5 작은 고침(U2) — 잠금 아이콘 · '넉넉히' 링 · 울기 안내 · 연습 상대 · [치] 패

    @Test
    func untimedPracticeHidesMyClockAndBotsCarryAPracticeTag() throws {
        // 없으면: '넉넉히' 연습판(결정 시계 칸 0)에 내 링이 '예비 0'으로 서거나, 봇 자리 카드에 '연습 상대' 꼬리표가 없어도 초록이다.
        let untimed = try mjPracticeStore(timed: false, payload: mjActive(matchID: "ai-practice-1"))
        let timed = try mjPracticeStore(timed: true, payload: mjActive(matchID: "ai-practice-1"))
        let idle = try mjPracticeStore(timed: false, payload: mjActive(matchID: "ai-practice-1") { $0["my_decision"] = NSNull() })
        let untimedBitmap = try mjBitmap(mjPanel(untimed))
        let timedBitmap = try mjBitmap(mjPanel(timed))
        mjSave(untimedBitmap, "practice-untimed")
        let ring = mjBody(MahjongMatchLayout.mySeat).insetBy(dx: 4, dy: 4)
        #expect(mjMaxDiff(timedBitmap, untimedBitmap, ring) > 60, "기준선: '실전처럼'에는 링이 선다")
        #expect(mjMaxDiff(try mjBitmap(mjPanel(idle)), untimedBitmap, ring) <= 8, "'넉넉히'인데 내 링이 섰다")
        // 연습 상대 — 루비 판의 같은 자리 카드와 다르다(내 카드는 같다).
        let ruby = try mjBitmap(mjPanel(try mjTableStore(mjActive())))
        for rect in [MahjongMatchLayout.leftSeat, MahjongMatchLayout.rightSeat, MahjongMatchLayout.topSeat] {
            #expect(mjMaxDiff(timedBitmap, ruby, mjBody(rect).insetBy(dx: 4, dy: 4)) > 60, "봇 카드에 '연습 상대'가 없다")
        }
        #expect(mjMaxDiff(timedBitmap, ruby, ring) <= 8, "내 카드에도 꼬리표가 붙었다")
        #expect(MahjongText.practiceBotTag == "연습 상대")
    }

    @Test
    func idleCallHintSitsAboveThePassButtonOnce() throws {
        // 없으면: '넉넉히' 울기 안내(5초 뒤)가 화면 어디에도 없거나, 상태 줄과 ACTIONS 에 두 번 쓰여도 초록이다.
        let payload = mjCall()
        let hinted = try mjPracticeStore(timed: false, payload: payload)
        hinted.notice = MahjongNoticeText.practiceIdleCallHint
        let quiet = try mjPracticeStore(timed: false, payload: payload)
        let with = try mjBitmap(mjPanel(hinted))
        let without = try mjBitmap(mjPanel(quiet))
        mjSave(with, "practice-call-hint")
        let actions = mjBody(MahjongMatchLayout.actions)
        let top = CGRect(x: actions.minX, y: actions.minY, width: actions.width, height: 14)
        #expect(mjMaxDiff(with, without, top) > 60, "ACTIONS 위에 울기 안내가 없다")
        let status = mjBody(CGRect(x: MahjongMatchLayout.hand.minX, y: MahjongMatchLayout.hand.minY, width: MahjongMatchLayout.hand.width,
                                   height: MahjongMatchLayout.statusLineHeight))
        #expect(mjMaxDiff(with, without, status) <= 8, "상태 줄에도 같은 안내가 또 쓰였다")
    }

    @Test
    func chiButtonCarriesMyTwoTilesAndLockIsASymbol() throws {
        // 없으면: [치] 단추가 글자뿐이라 어떤 두 장으로 우는지 모르거나(§5.4), 사람 줄 잠금이 이모지(🔒 — 글꼴마다 다른 그림)여도 초록이다.
        let bitmap = try mjBitmap(mjPanel(try mjTableStore(mjCall())))
        mjSave(bitmap, "call-chi-tiles")
        let actions = mjBody(MahjongMatchLayout.actions)
        #expect(mjCreamBlobs(bitmap, rect: actions, minHeight: 30) == 2, "[치] 단추에 내 패 두 장이 없다")
        // 기준선: 퐁만 되는 프롬프트엔 패 그림이 없다.
        let pon = try mjBitmap(mjPanel(try mjTableStore(mjCall { state in
            var decision = state["my_decision"] as! [String: Any]
            decision["chi"] = [] as [Any]
            decision["pon"] = [[mjID(3, 0), mjID(3, 1)]]
            state["my_decision"] = decision
        })))
        #expect(mjCreamBlobs(pon, rect: actions, minHeight: 30) == 0)
        #expect(MahjongText.lockSymbol == "lock.fill" && NSImage(systemSymbolName: MahjongText.lockSymbol, accessibilityDescription: nil) != nil)
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/check")
        for name in try FileManager.default.contentsOfDirectory(atPath: sources.path) where name.hasPrefix("Mahjong") {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            #expect(!text.contains("\u{1F512}"), "\(name) 에 잠금 이모지가 남았다")
        }
    }

    // MARK: ⑦-4 움직임(U2)

    @Test
    func discardSlidesInMidFrameAndStopsUnderReduceMotion() throws {
        // 없으면: 스토어가 움직임을 두어도 화면이 버린 패를 끝 자리에만 그리거나(움직임 없음), 동작 줄이기에도 미끄러지거나,
        // 끝난 움직임이 어긋난 채 남아도 초록이다.
        let store = try mjTableStore(mjActive())
        let matchID = try #require(store.table?.match?.id)
        let plain = try mjBitmap(mjPanel(store))
        // 상가(왼쪽, 자리 3)가 방금 버린 패 — 0.05초 지난 프레임(0.15초 중).
        store.motion = MahjongMotion(matchID: matchID, handIndex: 2, seq: 39, kind: .discard,
                                     from: .init(compass: .left, area: .hand), to: .init(compass: .left, area: .river),
                                     startedAt: mjNow.addingTimeInterval(-0.05))
        let moving = try mjBitmap(mjPanel(store))
        mjSave(moving, "motion-discard-mid")
        let reduced = try mjBitmap(mjPanel(store).environment(\.mahjongReduceMotion, true))
        let seat3 = try #require(store.table?.seats?.first { $0.seatNo == 3 })
        let last = try #require(MahjongTableGeometry.river(seat3.discards ?? [], compass: .left).last)
        let felt = mjBody(MahjongMatchLayout.felt)
        let block = MahjongMatchLayout.blockOrigin
        let size = MahjongTileArt.imageSize(last.size, rotation: last.rotation)
        let slot = CGRect(x: felt.minX + block.x + last.origin.x - MahjongMotionPlan.travel, y: felt.minY + block.y + last.origin.y,
                          width: size.width + MahjongMotionPlan.travel, height: size.height)
        #expect(mjMaxDiff(moving, plain, slot) > 60, "버린 패가 움직이지 않았다")
        #expect(mjMaxDiff(reduced, plain, slot) <= 8, "동작 줄이기에도 움직였다")
        // 끝난 움직임(1초 전)은 끝 그림 그대로.
        store.motion = MahjongMotion(matchID: matchID, handIndex: 2, seq: 39, kind: .discard,
                                     from: .init(compass: .left, area: .hand), to: .init(compass: .left, area: .river),
                                     startedAt: mjNow.addingTimeInterval(-1))
        #expect(mjMaxDiff(try mjBitmap(mjPanel(store)), plain, slot) <= 8, "끝난 움직임이 남았다")
    }

    // MARK: ⑧ 배율 0.82

    @Test
    func scaledDownWindowKeepsHandAndActionsInside() throws {
        // 없으면: 작은 화면 배율에서 손패·ACTIONS(맨 아래·오른쪽)가 창 밖으로 잘려도 초록이다(CC-14).
        let store = try mjTableStore(mjActive())
        let box = MahjongWindowScaleBox()
        box.scale = 0.82
        let bitmap = try mjBitmap(MahjongScaledRoot(box: box) { MahjongPanel(store: store, clipsOverflowInsteadOfScroll: true) })
        mjSave(bitmap, "scaled-082")
        #expect(abs(CGFloat(bitmap.pixelsWide) - 1240 * 0.82 * 2) <= 2 && abs(CGFloat(bitmap.pixelsHigh) - 700 * 0.82 * 2) <= 2)
        let hand = mjHandProbe
        let scaledHand = CGRect(x: hand.minX * 0.82, y: hand.minY * 0.82, width: hand.width * 0.82, height: hand.height * 0.82)
        #expect(mjCreamBlobs(bitmap, rect: scaledHand, minHeight: 80) == 14, "줄인 창에서 손패가 잘렸다")
        let actions = mjBody(MahjongMatchLayout.actions)
        let scaledActions = CGRect(x: actions.minX * 0.82, y: actions.minY * 0.82, width: actions.width * 0.82,
                                   height: actions.height * 0.82)
        #expect(scaledActions.maxX <= 1240 * 0.82 && mjInk(bitmap, scaledActions) > 500, "줄인 창에서 ACTIONS 가 잘렸다")
    }
}

// MARK: - 픽스처(§3.6 모양 손 픽스처 — S2 원문이 오면 바꾼다)

private let mjNowMs: Double = 1_793_660_908_000
private let mjNow = Date(timeIntervalSince1970: mjNowMs / 1_000)
private let mjMe = "aaaaaaaa-0000-4000-8000-000000000001"
private let mjPeople: [(id: String, name: String, character: String)] = [
    (mjMe, "영식", "shiba"), ("aaaaaaaa-0000-4000-8000-000000000002", "민수", "fox"),
    ("aaaaaaaa-0000-4000-8000-000000000003", "준호", "squirrel"), ("aaaaaaaa-0000-4000-8000-000000000004", "서연", "cat"),
]

private func mjID(_ kind: Int, _ copy: Int) -> Int { kind * 4 + copy }

/// 내 손 13장(1~3만 · 4~6통 · 7~9삭 · 동동남남) + 쯔모 적5만(id 16).
private let mjHand = [mjID(0, 0), mjID(1, 0), mjID(2, 0), mjID(12, 0), mjID(13, 0), mjID(14, 0), mjID(24, 0), mjID(25, 0),
                      mjID(26, 0), mjID(27, 0), mjID(27, 1), mjID(28, 0), mjID(28, 1)]
private let mjDrawn = 16

private func mjDisc(_ kind: Int, _ copy: Int, tsumogiri: Bool = false, riichi: Bool = false, taken: Bool = false) -> [String: Any] {
    ["tile": mjID(kind, copy), "tsumogiri": tsumogiri, "riichi": riichi, "taken": taken]
}

private func mjSeats(away: Bool = false) -> [[String: Any]] {
    let discards: [[[String: Any]]] = [
        [mjDisc(33, 2), mjDisc(32, 2), mjDisc(0, 2, tsumogiri: true), mjDisc(8, 2), mjDisc(17, 2), mjDisc(30, 2), mjDisc(9, 2)],
        [mjDisc(29, 2), mjDisc(31, 3), mjDisc(18, 2), mjDisc(7, 2), mjDisc(16, 2), mjDisc(3, 2, riichi: true), mjDisc(20, 2, tsumogiri: true),
         mjDisc(11, 2)],
        (0..<13).map { mjDisc([5, 6, 15, 19, 21, 23, 10, 22, 30, 32, 33, 6, 15][$0], 3) },
        [mjDisc(29, 3), mjDisc(31, 2, taken: true), mjDisc(5, 2), mjDisc(19, 2), mjDisc(10, 3), mjDisc(21, 3)],
    ]
    return (0..<4).map { seat in
        var row: [String: Any] = [
            "seat_no": seat, "user": ["user_id": mjPeople[seat].id, "display_name": mjPeople[seat].name,
                                      "character": mjPeople[seat].character],
            "wind": ["E", "S", "W", "N"][seat], "is_dealer": seat == 0, "score": [25_000, 24_000, 26_000, 25_000][seat],
            "hand_count": seat == 1 ? 10 : 13, "melds": [] as [Any], "discards": discards[seat], "riichi": seat == 1,
            "away": seat == 0 && away, "deleted": false,
        ]
        if seat == 1 {
            row["melds"] = [["type": "pon", "tiles": [mjID(31, 0), mjID(31, 1), mjID(31, 3)], "called": mjID(31, 3), "from_seat": 0]]
        }
        return row
    }
}

private func mjTurnDecision() -> [String: Any] {
    [
        "kind": "turn", "seq": 40, "decision_seq": 12, "started_ms": mjNowMs - 1_500, "deadline_ms": mjNowMs + 23_500,
        "bank_ms": 20_000, "discard": mjHand + [mjDrawn], "riichi": [mjID(27, 0), mjID(27, 1)], "tsumo": false,
        "ankan": [] as [Any], "kakan": [] as [Any], "kyuushu": false,
    ]
}

private func mjActive(matchID: String = "11111111-2222-4333-8444-555555555555", turnSeat: Int = 0,
                      edit: ((inout [String: Any]) -> Void)? = nil) -> [String: Any] {
    var state: [String: Any] = [
        "match": [
            "id": matchID, "status": "active", "stake": 5, "format": "tonpuu", "is_public": false, "seq": 40,
            "phase": "turn", "hand_index": 2, "round": 0, "hand_no": 2, "honba": 1, "kyotaku": 1, "dealer_seat": 0,
            "extension": false, "wall_remaining": 48, "dora_indicators": [mjID(23, 1)], "kan_count": 0, "turn_seat": turnSeat,
            "wake_at_ms": mjNowMs + 3_500, "wake_seat": 2, "backup_at_ms": mjNowMs + 8_500, "base_ms": 5_000,
            "bank_full_ms": 20_000, "grace_ms": 1_000, "started_ms": mjNowMs - 600_000,
            "host": ["id": mjMe, "display_name": "영식"],
        ] as [String: Any],
        "members": [] as [Any], "seats": mjSeats(), "my_seat": 0, "my_hand": mjHand, "my_drawn": turnSeat == 0 ? mjDrawn : NSNull(),
        "my_waits": [] as [Any], "my_furiten": [] as [Any], "my_decision": turnSeat == 0 ? mjTurnDecision() : NSNull(),
        "my_away": NSNull(),
        "events": [["seq": 39, "kind": "discard", "seat": 3, "at_ms": mjNowMs - 4_000, "tile": mjID(21, 3), "tsumogiri": false,
                    "riichi": false]],
        "last_hand": NSNull(), "reactions": [] as [Any], "ruby_balance": 115, "server_now_ms": mjNowMs,
    ]
    edit?(&state)
    return state
}

/// 울기 창(phase wait) — 상가(왼쪽, 자리 3)의 4만에 치 [2만·3만].
private func mjCall(wakeMs: Double = mjNowMs - 200, edit: ((inout [String: Any]) -> Void)? = nil) -> [String: Any] {
    mjActive(turnSeat: 3) { state in
        var match = state["match"] as! [String: Any]
        match["phase"] = "wait"
        match["turn_seat"] = NSNull()
        match["wake_at_ms"] = wakeMs
        state["match"] = match
        state["my_drawn"] = NSNull()
        state["my_decision"] = [
            "kind": "call", "window_id": 7, "window_kind": "discard", "tile": mjID(3, 3), "from_seat": 3,
            "started_ms": mjNowMs - 600, "deadline_ms": mjNowMs + 24_400, "bank_ms": 20_000, "ron": false,
            "pon": [] as [Any], "minkan": [] as [Any], "chi": [[mjID(1, 0), mjID(2, 0)]], "answered": NSNull(),
        ] as [String: Any]
        edit?(&state)
    }
}

private func mjHandEnd(win: Bool) -> [String: Any] {
    mjActive { state in
        var match = state["match"] as! [String: Any]
        match["phase"] = "hand_end"
        match["turn_seat"] = NSNull()
        match["next_hand_ms"] = mjNowMs + 4_000
        state["match"] = match
        state["my_decision"] = NSNull()
        state["my_drawn"] = NSNull()
        if win {
            state["last_hand"] = [
                "hand_index": 2, "kind": "win",
                "wins": [[
                    "seat": 0, "from_seat": 2, "hand": mjHand + [mjID(28, 2)], "melds": [] as [Any], "win_tile": mjID(28, 2),
                    "yaku": [["riichi", 1], ["yakuhai_haku", 1], ["menzen_tsumo", 1]], "yakuman": 0, "han": 4, "fu": 40,
                    "limit": "mangan", "dora": 1, "aka": 0, "ura": 0, "ura_indicators": [mjID(12, 3)], "total": 12_000,
                    "pao": NSNull(),
                ] as [String: Any]],
                "tenpai": [] as [Any], "nagashi": [] as [Any], "deltas": [13_300, 0, -12_300, 0],
                "scores_after": [38_300, 24_000, 13_700, 25_000], "bonus_to": NSNull(), "renchan": true,
            ] as [String: Any]
        } else {
            state["last_hand"] = [
                "hand_index": 2, "kind": "exhaustive", "reason": "exhaustive", "wins": [] as [Any],
                "tenpai": [["seat": 0, "hand": mjHand, "melds": [] as [Any]], ["seat": 2, "hand": mjHand, "melds": [] as [Any]]],
                "nagashi": [] as [Any], "deltas": [1_500, -1_500, 1_500, -1_500], "scores_after": [26_500, 22_500, 27_500, 23_500],
                "bonus_to": NSNull(), "renchan": true,
            ] as [String: Any]
        }
    }
}

private func mjFinished() -> [String: Any] {
    mjActive { state in
        var match = state["match"] as! [String: Any]
        match["status"] = "finished"
        match["phase"] = "finished"
        match["end_reason"] = "max_round"
        match["turn_seat"] = NSNull()
        state["match"] = match
        state["my_decision"] = NSNull()
        state["my_drawn"] = NSNull()
        var seats = state["seats"] as! [[String: Any]]
        let ranks = [2, 4, 1, 3], finals = [28_300, 9_700, 41_200, 20_800], payouts = [5, 0, 15, 0]
        for i in 0..<4 {
            seats[i]["final_rank"] = ranks[i]
            seats[i]["final_score"] = finals[i]
            seats[i]["payout"] = payouts[i]
        }
        state["seats"] = seats
    }
}

/// forming 방 — 방장은 나, joined 수만큼 앉고 나머지는 초대 중.
private func mjRoom(joined: Int) -> [String: Any] {
    [
        "match": [
            "id": "99999999-2222-4333-8444-555555555555", "status": "forming", "stake": 5, "format": "hanchan", "is_public": true,
            "seq": 3, "phase": "room", "room_expires_ms": mjNowMs + 432_000, "host": ["id": mjMe, "display_name": "영식"],
        ] as [String: Any],
        "members": (0..<4).map { i -> [String: Any] in
            ["user": ["id": mjPeople[i].id, "display_name": mjPeople[i].name, "character": mjPeople[i].character],
             "state": i < joined ? "joined" : "invited", "is_host": i == 0]
        },
        "seats": [] as [Any], "my_seat": NSNull(), "server_now_ms": mjNowMs,
    ]
}

private func mjDecode(_ object: [String: Any]) throws -> MahjongStatePayload {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(MahjongStatePayload.self, from: JSONSerialization.data(withJSONObject: object))
}

@MainActor
private func mjTableStore(_ state: [String: Any]) throws -> MahjongStore {
    let store = MahjongStore(clock: { mjNow })
    let outcome = store.applyState(try mjDecode(state))
    #expect(outcome == .applied)
    return store
}

/// 연습판 스토어(사람 자리 0 · 판 = 주어진 state).
@MainActor
private func mjPracticeStore(timed: Bool, payload: [String: Any]) throws -> MahjongStore {
    let store = MahjongStore(clock: { mjNow })
    store.practice = MahjongPracticeSession(matchID: "ai-practice-1", format: .tonpuu, timed: timed, humanSeat: 0, generation: 1,
                                            payload: try mjDecode(payload))
    store.showsPractice = true
    #expect(store.isPractice)
    return store
}

@MainActor
private func mjLobbyStore() throws -> MahjongStore {
    let store = MahjongStore(clock: { mjNow })
    func room(_ id: String, host: Int, stake: Int, format: String, joined: Int) -> [String: Any] {
        ["id": id, "host": ["id": mjPeople[host].id, "display_name": mjPeople[host].name, "character": mjPeople[host].character],
         "stake": stake, "format": format, "is_public": host == 2, "expires_at_ms": mjNowMs + 420_000, "max_seats": 4,
         "seats": (0..<joined).map { i in ["user": ["id": mjPeople[(host + i) % 4].id,
                                                    "display_name": mjPeople[(host + i) % 4].name], "state": "joined"] }]
    }
    let lobby: [String: Any] = [
        "status": "ok", "server_now_ms": mjNowMs, "stakes": [3, 5, 10], "formats": ["tonpuu", "hanchan"],
        "me": ["ruby_balance": 120, "record": ["games": 12, "firsts": 4, "seconds": 3, "thirds": 3, "fourths": 2, "avg_rank": 2.25]],
        "invites": [room("77777777-0000-4000-8000-000000000001", host: 1, stake: 5, format: "tonpuu", joined: 2)],
        "public_rooms": [room("77777777-0000-4000-8000-000000000002", host: 2, stake: 10, format: "hanchan", joined: 3)],
        "users": (1..<4).map { i -> [String: Any] in
            ["id": mjPeople[i].id, "display_name": mjPeople[i].name, "character": mjPeople[i].character,
             "is_working": i != 3, "in_match": i == 2, "capable": true, "focus_mode": false]
        } + [["id": "aaaaaaaa-0000-4000-8000-000000000005", "display_name": "하늘", "is_working": false, "in_match": false,
              "capable": false, "focus_mode": false]],
    ]
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    store.applyLobby(try decoder.decode(MahjongLobbyResponse.self, from: JSONSerialization.data(withJSONObject: lobby)))
    let ranking: [String: Any] = [
        "status": "ok", "me": ["rank": 3, "games": 12, "firsts": 4, "avg_rank": 2.25],
        "rows": [["rank": 1, "user_id": mjPeople[1].id, "display_name": mjPeople[1].name, "games": 31, "firsts": 12, "avg_rank": 1.94],
                 ["rank": 2, "user_id": mjPeople[2].id, "display_name": mjPeople[2].name, "games": 18, "firsts": 6, "avg_rank": 2.11],
                 ["rank": 3, "user_id": mjMe, "display_name": "영식", "games": 12, "firsts": 4, "avg_rank": 2.25]],
    ]
    store.ranking = try decoder.decode(MahjongRankingResponse.self, from: JSONSerialization.data(withJSONObject: ranking))
    return store
}

@MainActor
private enum MJRenderRetention {
    static var owners: [WorkTimerStore] = []
}

/// 방장 판정에 세션이 필요한 장면 — 스텁 서비스(네트워크 0)에 물린 스토어.
@MainActor
private func mjHostedStore(_ label: String) throws -> MahjongStore {
    let host = "v03xx-mj-render-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host) { _, _, _ in nil }
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let owner = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: GomokuTestDefaults.make("v03xx-mahjong-render"), workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: mjMe)
    MJRenderRetention.owners.append(owner)
    let store = MahjongStore(clock: { mjNow })
    store.attach(host: owner)
    return store
}

@MainActor
private func mjPanel(_ store: MahjongStore, overlay: MahjongOverlay? = nil, hover: Int? = nil,
                     tab: MahjongLobbyTab? = nil, feed: MahjongReactionFeed? = nil) -> MahjongPanel {
    MahjongPanel(store: store, me: { ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba") },
                 clipsOverflowInsteadOfScroll: true, previewOverlay: overlay, previewHoverIndex: hover, previewLobbyTab: tab,
                 guideDefaults: mjRenderDefaults, reactionFeed: feed ?? MahjongReactionFeed(), previewNow: mjNow)
}

/// 렌더 시험의 '처음이에요' 스위트(표준 스위트에 쓰지 않는다).
@MainActor
private let mjRenderDefaults = GomokuTestDefaults.make("v03xx-mahjong-render-guide")

// MARK: - 좌표(창 pt) · 픽셀 도우미

/// 판 본문 사각형 → 창 좌표.
private func mjBody(_ rect: CGRect) -> CGRect {
    rect.offsetBy(dx: MahjongMatchLayout.bodyOrigin.x, dy: MahjongMatchLayout.bodyOrigin.y)
}

/// 손패가 서는 띠(상태 줄 아래 — 호버 8pt 들림 포함).
private var mjHandProbe: CGRect {
    let hand = mjBody(MahjongMatchLayout.hand)
    return CGRect(x: hand.minX, y: hand.minY + MahjongMatchLayout.handTileTop - MahjongMatchLayout.hoverLift,
                  width: hand.width, height: MahjongMatchLayout.hand.height - MahjongMatchLayout.handTileTop + MahjongMatchLayout.hoverLift)
}

/// 가운데 판의 "기다리는 중…" 줄(도라 줄 아래 · 바람 글자 위).
private var mjWaitingBand: CGRect {
    let felt = mjBody(MahjongMatchLayout.felt)
    let center = MahjongMatchLayout.center
    let origin = CGPoint(x: felt.minX + MahjongMatchLayout.blockOrigin.x + center.minX, y: felt.minY + center.minY)
    return CGRect(x: origin.x + 50, y: origin.y + 150, width: 100, height: 22)
}

private func mjCount(_ bitmap: NSBitmapImageRep, _ rect: CGRect, where predicate: (Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var hits = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if predicate(Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) { hits += 1 }
        }
    }
    return hits
}

/// 잉크 — 유채색(채널 폭 ≥ 40)이거나 밝은 글자(최대 ≥ 150).
private func mjInk(_ bitmap: NSBitmapImageRep, _ rect: CGRect) -> Int {
    mjCount(bitmap, rect) { r, g, b in
        let high = max(r, max(g, b)), low = min(r, min(g, b))
        return (high - low) >= 40 || high >= 150
    }
}

/// 두 비트맵의 사각형 안 채널 최대 차.
private func mjMaxDiff(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, _ rect: CGRect) -> Int {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData, lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh
    else { return 255 }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(lhs.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(lhs.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 255 }
    var worst = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            for c in 0..<min(3, spp) { worst = max(worst, abs(Int(a[o + c]) - Int(b[o + c]))) }
        }
    }
    return worst
}

/// 밝은 크림(패 몸체) 덩어리 수 — 크기 400px 이상이고 세로 폭이 `minHeight` px 이상인 연결 성분.
private func mjCreamBlobs(_ bitmap: NSBitmapImageRep, rect: CGRect, minHeight: Int) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    let w = x1 - x0 + 1, h = y1 - y0 + 1
    var mask = [Bool](repeating: false, count: w * h)
    for y in 0..<h {
        for x in 0..<w {
            let o = (y + y0) * bpr + (x + x0) * spp
            let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
            mask[y * w + x] = r >= 222 && g >= 216 && b >= 232
        }
    }
    var seen = [Bool](repeating: false, count: w * h)
    var count = 0
    for start in 0..<(w * h) where mask[start] && !seen[start] {
        var stack = [start]
        seen[start] = true
        var size = 0, minY = Int.max, maxY = Int.min
        while let p = stack.popLast() {
            size += 1
            let px = p % w, py = p / w
            minY = min(minY, py); maxY = max(maxY, py)
            for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)] where nx >= 0 && ny >= 0 && nx < w && ny < h {
                let n = ny * w + nx
                if mask[n] && !seen[n] { seen[n] = true; stack.append(n) }
            }
        }
        if size >= 400, maxY - minY + 1 >= minHeight { count += 1 }
    }
    return count
}

private enum MJRenderError: Error { case failed }

@MainActor
private func mjBitmap(_ view: some View) throws -> NSBitmapImageRep {
    guard let bitmap = CheckRenderSettle.bitmap(view.fixedSize(), scale: 2) else { throw MJRenderError.failed }
    return bitmap
}

/// 사람이 볼 PNG — `MAHJONG_RENDER_DIR` 을 줄 때만 그 폴더에 쓴다(주지 않으면 아무 데도 안 쓴다 — 임시 폴더에 쌓이지 않게).
private func mjSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    guard let dir = ProcessInfo.processInfo.environment["MAHJONG_RENDER_DIR"], !dir.isEmpty,
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    let folder = URL(fileURLWithPath: dir, isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? png.write(to: folder.appendingPathComponent("\(name).png"))
}

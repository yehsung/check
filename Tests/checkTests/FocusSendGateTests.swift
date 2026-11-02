import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 대표 요청 5·6(2026-11-03, 원문):
//   5. "집중 모드인 사람들은 채팅 보내거나 찌를때 알 수 있는거 말고 미리 알 수 있게 해줘. 콕/메세지 창 에서부터 집중 모드인 사람들은
//      표시가 되게끔 하고 메세지나 찌르기 비활성화 되게."
//   6. "집중모드중인 사람들은 남들 찌르거나 메세지 못보내게 해줘. (자기는 못받으면서 남들한텐 할 수 있는게 안맞음)"
//
// 이 파일이 재는 것(맥 클라 몫 — 서버가 명부에 focus_mode 칸을 싣는 것은 다른 갈래다):
//  ① 디코드: 칸 있음(true/false) · 없음(옛 서버) · null — 모르면 '집중 아님'(옛 서버에서 전원이 잠기면 안 된다)
//  ①-2 서버 실출력(하네스 픽스처 Fixtures/directory-rpc): 서버 초안 8칸에서는 켠 사람만 집중 · 지금 운영 7칸에서는 아무도 아님
//      — 요청 5(상대 집중 미리 표시)는 서버 초안이 운영에 올라가기 전엔 꺼져 있다(2026-11-03 검토 P1, 대표 결재 대기).
//  ② 행: '집중' 칩 · 찌르기 버튼 잠금(상대 집중 · 내 집중 · 둘 다 아님 — 기준선이 셋 다 다르다)
//  ③ 스토어 짝 게이트: 찌르기 · 울트라 · 메시지 · 이모티콘 · [보내기] 문(요청 0건 vs 1건)
//  ④ 서버 target_focused 뒤 명부 재조회 · 대화 화면에 있는 동안의 명부 갱신(30초 틱 · 팝오버 다시 열기)
//  ⑤ 대화 화면: 머리 '집중 중' · 입력칸 위 사유 줄 · 높이 그대로
//
// 네트워크는 `MessageReadStubProtocol`(호스트별 스크립트)이다. 시계는 얼린다(`makeMessageReadStore`).

private typealias Fx = MessageReadFixture

private let fsFocused = Fx.peerA      // 명부가 집중이라 말하는 사람
private let fsPlain = Fx.peerB        // 명부가 집중 아님이라 말하는 사람
private let fsAbsent = "00000000-0000-0000-0000-0000000374d4"   // 칸이 없는 행(옛 서버 모양)
private let fsNull = "00000000-0000-0000-0000-0000000374e5"     // 칸이 null 인 행

// MARK: - 픽스처

private enum FsFx {
    /// 명부 한 행. `focus` 가 nil 이면 **칸 자체가 없다**(옛 서버 7칸), NSNull 이면 null, Bool 이면 그 값.
    static func row(_ id: String, name: String, working: Bool = true, focus: Any?) -> [String: Any] {
        var row: [String: Any] = [
            "user_id": id, "display_name": name, "avatar_url": NSNull(), "is_working": working,
            "message_capable": true, "center": NSNull(), "status_message": NSNull()
        ]
        if let focus { row["focus_mode"] = focus }
        return row
    }

    /// 기본 명부: 집중 1 · 집중 아님 1 · 칸 없음 1 · null 1.
    static func directory(focusedPeerIsFocused: Bool = true) -> MessageReadStubProtocol.Reply {
        MessageReadStubProtocol.Reply(body: Fx.json([
            row(fsFocused, name: "집중이", focus: focusedPeerIsFocused),
            row(fsPlain, name: "보통이", focus: false),
            row(fsAbsent, name: "옛서버", focus: nil),
            row(fsNull, name: "널이", focus: NSNull())
        ]))
    }

    static func status(_ status: String) -> MessageReadStubProtocol.Reply {
        MessageReadStubProtocol.Reply(body: Fx.json(["status": status]))
    }
}

/// 명부 · 찌르기 · 울트라 · 메시지 응답을 스크립트한 로그인 스토어. 근무 중(찌르기 선게이트 통과)으로 세운다.
/// `sendStatus` 는 세 보내기 RPC 의 공통 응답이다(기본 target_on_phone — 디렉터리를 안 건드리는 조용한 거절).
@MainActor
private func fsStore(
    _ label: String,
    sendStatus: String = "target_on_phone",
    directory: @escaping @Sendable (Int) -> MessageReadStubProtocol.Reply = { _ in FsFx.directory() },
    function: String = #function
) -> (store: WorkTimerStore, host: String) {
    let made = makeMessageReadStore(label, handler: { call, index in
        switch call.rpc {
        case "app_user_directory": return directory(index)
        case "poke_user", "ultra_poke_user", "send_message": return FsFx.status(sendStatus)
        default: return nil
        }
    }, function: function)
    made.store.startedAt = Fx.now
    return made
}

private func fsCalls(_ host: String, rpc: String, to peer: String) -> Int {
    MessageReadStubProtocol.calls(host: host, rpc: rpc).filter { ($0.json["p_to"] as? String) == peer }.count
}

@MainActor
private func fsLoadDirectory(_ store: WorkTimerStore) async {
    await store.performLoadPokeDirectory()
    #expect(store.pokeDirectoryLoaded, "명부를 못 받았다(전제 붕괴)")
}

// MARK: - ① 디코드

@MainActor
@Suite struct FocusSendGateDecodeTests {
    @Test func 명부_칸이_있으면_읽고_없거나_null_이면_집중_아님으로_읽는다() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase   // 서비스와 같은 규약(SupabaseWorkService)
        let data = Data(Fx.json([
            FsFx.row("a", name: "가", focus: true),
            FsFx.row("b", name: "나", focus: false),
            FsFx.row("c", name: "다", focus: nil),
            FsFx.row("d", name: "라", focus: NSNull())
        ]).utf8)
        let rows = try decoder.decode([PokeDirectoryRow].self, from: data)
        // 커스텀 디코더의 함정(키를 더하고 init(from:) 에 줄을 안 더하면 영원히 nil)을 값으로 갈라 본다 — true 가 읽혀야 한다.
        #expect(rows.map(\.focusMode) == [true, false, nil, nil])
        let entries = rows.toPokeDirectoryEntries()
        #expect(entries.map(\.isFocused) == [true, false, false, false], "모름(nil)을 집중으로 읽으면 옛 서버에서 전원이 잠긴다")
        // 멤버와이즈 기본값(폰 · 시험 호출부가 칸을 안 넘기는 자리)도 집중 아님이다.
        #expect(!PokeDirectoryEntry(userID: "x", name: "x", avatarURL: nil, isWorking: true).isFocused)
        #expect(PokeDirectoryRow(userId: "x", displayName: "x", avatarUrl: nil, isWorking: true).focusMode == nil)
    }

    @Test(.gomokuDefaultsCleanup)
    func 스토어가_받은_명부에서_집중을_사람별로_안다() async {
        let (store, _) = fsStore("decode")
        await fsLoadDirectory(store)
        #expect(store.isPeerFocused(fsFocused))
        #expect(!store.isPeerFocused(fsPlain))
        #expect(!store.isPeerFocused(fsAbsent), "칸이 없는 행(옛 서버)을 집중으로 읽었다")
        #expect(!store.isPeerFocused(fsNull))
        #expect(!store.isPeerFocused("명부에-없는-사람"))
    }
}

// MARK: - ①-2 서버 실출력 픽스처(하네스) — 스텁이 실어 준다는 가정이 아니라 서버가 내는 바이트

/// 하네스에서 app_user_directory() 를 **실제로 부른 출력**(Fixtures/directory-rpc · 생성기 `_generate.sh.txt` · `_manifest.json`).
/// 두 장은 같은 장면이다 — 예은(B)이 자기 행을 켰고 나머지는 끈 채, 호출자는 abto(A):
///   · draft_8col   — 서버 초안 20261108120000(맨 끝 focus_mode)을 올린 서버. **운영에는 아직 없다(대표 결재 대기).**
///   · current_7col — 지금 운영 정본(20261014121000 §3, 7칸). B 가 켰는데도 칸이 없다.
/// 위 ① 의 행은 시험이 손으로 만든 사전이다 — 서버 초안의 칸 이름·자리·타입이 그것과 어긋나도 ① 은 초록이다. 여기가 그 틈을 막는다.
private let fsServerFixtureFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/directory-rpc", isDirectory: true)
/// 하네스 씨앗 B(예은) — 장면에서 집중을 켠 사람.
private let fsServerFocusedPeer = "3e240c02-8972-478e-a674-014f498a641b"

private func fsServerFixture(_ name: String) throws -> (body: String, rows: [[String: Any]]) {
    let body = try String(contentsOf: fsServerFixtureFolder.appendingPathComponent("\(name).json"), encoding: .utf8)
    let rows = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [[String: Any]], "\(name): 배열이 아니다")
    return (body, rows)
}

@MainActor
@Suite struct FocusSendGateServerFixtureTests {
    @Test(.gomokuDefaultsCleanup)
    func 서버_초안_8칸_실출력에서는_켠_사람만_집중으로_읽고_그_사람만_잠근다() async throws {
        let (body, rows) = try fsServerFixture("app_user_directory__draft_8col")
        var raw: [String: Bool] = [:]
        for row in rows {
            let id = try #require(row["user_id"] as? String)
            raw[id] = try #require(row["focus_mode"] as? Bool, "\(id): 8칸인데 focus_mode 가 불리언이 아니다")
        }
        // 장면 전제(비교 기준선이 달라야 한다): 켠 사람 하나 · 끈 사람 여럿. 전부 같은 값이면 이 시험은 아무것도 못 가른다.
        #expect(raw[fsServerFocusedPeer] == true)
        #expect(raw.values.filter { !$0 }.count >= 2)

        let (store, _) = fsStore("server-8col", directory: { _ in MessageReadStubProtocol.Reply(body: body) })
        await fsLoadDirectory(store)
        #expect(store.pokeDirectory.count == rows.count, "실출력 행이 디코드에서 사라졌다")
        for (id, focused) in raw {
            // 키 이름·자리 하나만 어긋나도 옵셔널이 조용히 nil → '집중 아님'으로 접혀 B 의 줄이 빨개진다(손으로 만든 사전은 못 보는 결함).
            #expect(store.isPeerFocused(id) == focused, "\(id): 서버 \(focused) → 클라 \(store.isPeerFocused(id))")
            #expect(store.focusSendBlock(to: id) == (focused ? .peer : nil))
        }
    }

    @Test(.gomokuDefaultsCleanup)
    func 지금_운영_7칸_실출력에서는_켠_사람도_집중_아님이다() async throws {
        // 검토 P1(2026-11-03): 운영 명부에는 focus_mode 칸이 없다 — 새 맥만 내보내면 요청 5 의 '집중' 칩·대화 머리 '집중 중'·
        // 상대 집중 잠금은 0 이고, 요청 6(내 집중이면 못 보냄)만 동작한다. 클라가 메울 수 없다(팀 밖 사람의 집중은 RLS 로 안 보인다) —
        // 서버 초안의 운영 적용이 먼저다. 이 시험은 그 사실과 '모름 = 집중 아님'(전원이 잠기지 않는다)을 서버가 실제로 내는 바이트로 못 박는다.
        let (body, rows) = try fsServerFixture("app_user_directory__current_7col")
        let (_, draftRows) = try fsServerFixture("app_user_directory__draft_8col")
        #expect(rows.allSatisfy { $0["focus_mode"] == nil }, "7칸 픽스처에 focus_mode 가 있다 — 장면이 바뀌었다")
        // 두 장은 같은 장면이다: 같은 사람들 · 칸 집합은 초안이 맨 끝에 focus_mode 하나만 더한 것.
        #expect(Set(rows.compactMap { $0["user_id"] as? String }) == Set(draftRows.compactMap { $0["user_id"] as? String }))
        #expect(Set(rows.flatMap(\.keys)).union(["focus_mode"]) == Set(draftRows.flatMap(\.keys)))

        let (store, _) = fsStore("server-7col", directory: { _ in MessageReadStubProtocol.Reply(body: body) })
        await fsLoadDirectory(store)
        #expect(store.pokeDirectory.count == rows.count, "옛 서버 명부가 디코드에서 죽었다")
        // 초안 서버에서는 집중으로 읽히는 바로 그 사람(위 시험)이 여기서는 아니다 — 모름을 집중으로 읽으면 전원이 잠긴다.
        #expect(!store.isPeerFocused(fsServerFocusedPeer))
        #expect(store.pokeDirectory.allSatisfy { !$0.isFocused })
        #expect(store.focusSendBlock(to: fsServerFocusedPeer) == nil)
    }
}

// MARK: - ② 규칙 · 행

@MainActor
@Suite struct FocusSendGateRuleTests {
    @Test func 내_집중이_상대_집중보다_앞이고_둘_다_아니면_막지_않는다() {
        #expect(FocusSendBlock.of(myFocus: false, peerFocused: false) == nil)
        #expect(FocusSendBlock.of(myFocus: false, peerFocused: true) == .peer)
        #expect(FocusSendBlock.of(myFocus: true, peerFocused: false) == .myself)
        #expect(FocusSendBlock.of(myFocus: true, peerFocused: true) == .myself)
        // 문장은 스토어 상수에서 온다 — 상대 집중은 서버 거절 문구와 **같은 문장**이다(미리 막았을 때와 보낸 뒤 거절됐을 때 같은 말).
        #expect(FocusSendBlock.peer.pokeText == WorkTimerStore.targetFocusedNotice)
        #expect(FocusSendBlock.peer.messageText == WorkTimerStore.messageTargetFocusedNotice)
        #expect(FocusSendBlock.myself.pokeText == WorkTimerStore.myFocusBlocksSendingNotice)
        #expect(FocusSendBlock.myself.messageText == WorkTimerStore.myFocusBlocksSendingNotice)
        #expect(WorkTimerStore.myFocusBlocksSendingNotice.contains("찌르기") && WorkTimerStore.myFocusBlocksSendingNotice.contains("메시지"))
    }

    @Test func 행의_찌르기_잠금_사유는_내_근무_집중_자리비움_순이다() {
        let working = PokeDirectoryEntry(userID: "w", name: "가", avatarURL: nil, isWorking: true)
        var focused = working
        focused.isFocused = true
        var focusedAway = focused
        focusedAway.isWorking = false
        let away = PokeDirectoryEntry(userID: "a", name: "나", avatarURL: nil, isWorking: false)

        // 기준선: 셋 다 아니면 누를 수 있다.
        #expect(PokeDirectoryRowView.pokeBlockedReason(canPoke: true, isMyselfFocused: false, entry: working) == nil)
        // 상대 집중.
        #expect(PokeDirectoryRowView.pokeBlockedReason(canPoke: true, isMyselfFocused: false, entry: focused) == WorkTimerStore.targetFocusedNotice)
        // 내 집중(상대는 멀쩡하다).
        #expect(PokeDirectoryRowView.pokeBlockedReason(canPoke: true, isMyselfFocused: true, entry: working) == WorkTimerStore.myFocusBlocksSendingNotice)
        // 칩이 '집중'인 사람에게 "자리비움…"이라 말하지 않는다.
        #expect(PokeDirectoryRowView.pokeBlockedReason(canPoke: true, isMyselfFocused: false, entry: focusedAway) == WorkTimerStore.targetFocusedNotice)
        #expect(PokeDirectoryRowView.pokeBlockedReason(canPoke: true, isMyselfFocused: false, entry: away) == "자리비움 상태에는 찌를 수 없어요")
        // 내 비근무가 맨 앞이다(스토어 sendPoke 의 가드 순서와 같다).
        #expect(PokeDirectoryRowView.pokeBlockedReason(canPoke: false, isMyselfFocused: true, entry: focused) == "내가 근무 중일 때만 콕 찌를 수 있어요")
    }

    @Test func 집중_칩은_근무중_자리비움보다_좁아_이름_몫을_깎지_않는다() {
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        let dotAndGap: CGFloat = 6 + 4
        let focusChip = dotAndGap + width(PokeDirectoryRowView.focusChipText)
        #expect(PokeDirectoryRowView.focusChipText == "집중", "큐브 로비 칩과 같은 낱말이어야 한다(RummyPanelLobby)")
        #expect(focusChip <= dotAndGap + width("근무중"), "집중 칩(\(focusChip)pt)이 근무중 칩보다 넓다 — 이름 몫 81.05pt 가 깎인다")
        #expect(focusChip <= width("자리비움"), "집중 칩(\(focusChip)pt)이 자리비움 칩보다 넓다")
    }
}

// MARK: - ② 행 렌더(상대 집중 · 내 집중 · 둘 다 아님)

private func fsAccentCount(_ bitmap: NSBitmapImageRep) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    var count = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let offset = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel
            let r = Int(data[offset]), g = Int(data[offset + 1]), b = Int(data[offset + 2])
            if b >= 190, b > r + 80, g > r + 40, g < b { count += 1 }   // CheckMenuRenderTests.accentPixelCount 와 같은 판정
        }
    }
    return count
}

/// 한 색 근처 픽셀 수(채널마다 ±30). 글자는 안티에일리어싱으로 번지므로 정확한 색이 아니라 **잉크의 양**을 비교한다.
private func fsInkCount(_ bitmap: NSBitmapImageRep, r tr: Int, g tg: Int, b tb: Int) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    var count = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let offset = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel
            let r = Int(data[offset]), g = Int(data[offset + 1]), b = Int(data[offset + 2])
            if abs(r - tr) <= 30, abs(g - tg) <= 30, abs(b - tb) <= 30 { count += 1 }
        }
    }
    return count
}

/// aiToken(보라 · 184,140,255) 잉크 — '집중' 칩.
private func fsFocusInkCount(_ bitmap: NSBitmapImageRep) -> Int { fsInkCount(bitmap, r: 184, g: 140, b: 255) }

/// pending(주황 · 255,184,84) 잉크 — 입력칸 위 사유 줄(전송 성공 줄은 초록이다).
private func fsWarningInkCount(_ bitmap: NSBitmapImageRep) -> Int { fsInkCount(bitmap, r: 255, g: 184, b: 84) }

@MainActor
private func fsRowBitmap(entry: PokeDirectoryEntry, myselfFocused: Bool) throws -> NSBitmapImageRep {
    let view = PokeDirectoryRowView(
        entry: entry, cooldownRemaining: { 0 }, canPoke: true, isMyselfFocused: myselfFocused,
        ultraBalance: 3, onPoke: {}, onUltra: {}
    )
    .frame(width: 292, height: 48)
    .background(CheckTheme.panel)
    return try #require(CheckRenderSettle.bitmap(view.fixedSize(), scale: 2))
}

@MainActor
@Suite(.serialized) struct FocusSendGateRowRenderTests {
    @Test func 상대_집중과_내_집중은_찌르기_버튼을_흐리고_칩은_상대_집중만_그린다() throws {
        let plain = PokeDirectoryEntry(userID: "u1", name: "영식", avatarURL: nil, isWorking: true)
        var focused = plain
        focused.isFocused = true

        let live = try fsRowBitmap(entry: plain, myselfFocused: false)
        let peerFocused = try fsRowBitmap(entry: focused, myselfFocused: false)
        let meFocused = try fsRowBitmap(entry: plain, myselfFocused: true)

        let liveAccent = fsAccentCount(live)
        // 활성 찌르기 버튼(accent 원 30pt ≈ 2,800px)이 사라진다 — 말풍선 버튼(accent 글자)은 셋 다 그대로라 0 은 아니다.
        #expect(liveAccent > fsAccentCount(peerFocused) + 1_000, "상대가 집중인데 찌르기 버튼이 살아 있다: \(liveAccent) vs \(fsAccentCount(peerFocused))")
        #expect(liveAccent > fsAccentCount(meFocused) + 1_000, "내가 집중인데 찌르기 버튼이 살아 있다: \(liveAccent) vs \(fsAccentCount(meFocused))")
        #expect(fsAccentCount(meFocused) > 0, "말풍선 버튼까지 죽었다 — 대화(지난 대화 읽기)는 열려야 한다")

        // '집중' 칩은 상대가 집중일 때만 — 내 집중은 행마다 칩을 그리지 않는다(안내줄이 말한다).
        let liveInk = fsFocusInkCount(live)
        #expect(fsFocusInkCount(peerFocused) > liveInk + 40, "상대가 집중인데 '집중' 칩이 안 그려졌다")
        #expect(abs(fsFocusInkCount(meFocused) - liveInk) < 40, "내 집중이 상대 행에 '집중' 칩을 그렸다")
    }
}

// MARK: - ③ 스토어 짝 게이트 — 찌르기 · 울트라

@MainActor
@Suite struct FocusSendGatePokeStoreTests {
    @Test(.gomokuDefaultsCleanup)
    func 상대가_집중이면_찌르기와_울트라는_요청을_내지_않는다() async {
        let (store, host) = fsStore("poke-peer")
        await fsLoadDirectory(store)
        store.applyUltraBalance(3)

        store.sendPoke(to: fsFocused)
        // 동기 판정이다 — 요청 없이 그 자리에서 안내가 선다(게이트가 없으면 여기서 nil).
        #expect(store.pokeNotice == WorkTimerStore.targetFocusedNotice)
        store.pokeNotice = nil
        store.sendUltraPoke(to: fsFocused)
        #expect(store.pokeNotice == WorkTimerStore.targetFocusedNotice)
        #expect(store.ultraBalance == 3, "요청도 안 나갔는데 화면의 울트라를 깎았다")

        // 기준선: 같은 스토어 · 집중 아닌 사람은 나간다(게이트가 '항상 막기'가 아니다).
        store.pokeNotice = nil
        store.sendPoke(to: fsPlain)
        await messageReadWait { store.pokeNotice == WorkTimerStore.targetOnPhoneNotice }
        store.pokeNotice = nil
        store.sendUltraPoke(to: fsPlain)
        await messageReadWait { store.pokeNotice == WorkTimerStore.targetOnPhoneNotice }
        #expect(fsCalls(host, rpc: "poke_user", to: fsPlain) == 1)
        #expect(fsCalls(host, rpc: "ultra_poke_user", to: fsPlain) == 1)
        #expect(fsCalls(host, rpc: "poke_user", to: fsFocused) == 0, "집중인 사람에게 찌르기 요청이 나갔다")
        #expect(fsCalls(host, rpc: "ultra_poke_user", to: fsFocused) == 0, "집중인 사람에게 울트라 요청이 나갔다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 내가_집중이면_누구에게도_찌르기와_울트라를_못_보낸다() async {
        let (store, host) = fsStore("poke-me")
        await fsLoadDirectory(store)
        store.focusMode = true

        store.sendPoke(to: fsPlain)
        #expect(store.pokeNotice == WorkTimerStore.myFocusBlocksSendingNotice)
        store.pokeNotice = nil
        store.sendUltraPoke(to: fsPlain)
        #expect(store.pokeNotice == WorkTimerStore.myFocusBlocksSendingNotice)

        // 기준선: 집중을 끄면 같은 사람에게 나간다.
        store.focusMode = false
        store.pokeNotice = nil
        store.sendPoke(to: fsPlain)
        await messageReadWait { store.pokeNotice == WorkTimerStore.targetOnPhoneNotice }
        #expect(fsCalls(host, rpc: "poke_user", to: fsPlain) == 1, "집중 중에 나간 요청이 섞였거나 기준선이 안 나갔다")
        #expect(fsCalls(host, rpc: "ultra_poke_user", to: fsPlain) == 0, "집중 중에 울트라 요청이 나갔다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 옛_서버_명부에서는_아무도_잠기지_않는다() async {
        // 서버가 아직 focus_mode 칸을 안 보낸다(지금 운영 7칸) — 모름을 집중으로 읽으면 전원이 잠긴다.
        let (store, host) = fsStore("poke-legacy", directory: { _ in
            MessageReadStubProtocol.Reply(body: Fx.json([FsFx.row(fsAbsent, name: "옛서버", focus: nil)]))
        })
        await fsLoadDirectory(store)
        #expect(store.focusSendBlock(to: fsAbsent) == nil)
        store.sendPoke(to: fsAbsent)
        await messageReadWait { store.pokeNotice == WorkTimerStore.targetOnPhoneNotice }
        #expect(fsCalls(host, rpc: "poke_user", to: fsAbsent) == 1)
    }
}

// MARK: - ③ 스토어 짝 게이트 — 메시지 · 이모티콘 · [보내기] 문

@MainActor
@Suite struct FocusSendGateMessageStoreTests {
    @Test(.gomokuDefaultsCleanup)
    func 상대가_집중이면_보내기_Enter_이모티콘이_잠기고_요청이_없다() async {
        let (store, host) = fsStore("msg-peer", sendStatus: "ok")
        await fsLoadDirectory(store)
        store.openMessagePanel(peer: fsFocused)
        store.messageDraft = "안녕하세요"

        #expect(store.selectedMessagePeerIsFocused)
        #expect(store.messageFocusBlock == .peer)
        #expect(!store.canSendMessageNow, "[보내기]·Enter 가 열려 있다")
        #expect(!store.canSendStickerNow, "이모티콘이 열려 있다")
        let composer = MessageComposerView(store: store)
        #expect(composer.sendHelp == WorkTimerStore.messageTargetFocusedNotice)
        #expect(composer.stickerHelp == WorkTimerStore.messageTargetFocusedNotice)
        #expect(!composer.stickerCanToggle)

        // 세 문(버튼 문 · 이모티콘 · 스토어 본체)을 다 두드려도 요청은 0건이다.
        composer.send()
        #expect(!store.sendSticker(.allCases[0]))
        #expect(store.messageNotice == WorkTimerStore.messageTargetFocusedNotice, "이모티콘 실패가 '보내는 중'으로 접혔다")
        store.messageNotice = nil
        store.sendMessage(to: fsFocused, body: "직접")
        #expect(store.messageNotice == WorkTimerStore.messageTargetFocusedNotice)
        #expect(!store.isSendingMessage)
        #expect(store.messageDraft == "안녕하세요", "못 보냈는데 초안이 지워졌다")

        // 기준선: 같은 스토어에서 집중 아닌 사람과의 대화는 나간다.
        store.openMessagePanel(peer: fsPlain)
        store.messageDraft = "안녕하세요"
        #expect(store.canSendMessageNow && store.canSendStickerNow)
        #expect(MessageComposerView(store: store).sendHelp == MessageDraftEditor.sendHelp)
        MessageComposerView(store: store).send()
        await messageReadWait { fsCalls(host, rpc: "send_message", to: fsPlain) >= 1 && !store.isSendingMessage }
        #expect(fsCalls(host, rpc: "send_message", to: fsPlain) == 1)
        #expect(fsCalls(host, rpc: "send_message", to: fsFocused) == 0, "집중인 사람에게 메시지 요청이 나갔다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 내가_집중이면_열린_대화의_답장도_못_보낸다() async {
        let (store, host) = fsStore("msg-me", sendStatus: "ok")
        await fsLoadDirectory(store)
        store.openMessagePanel(peer: fsPlain)
        store.messageDraft = "답장"
        #expect(store.canSendMessageNow, "기준선: 집중 전에는 보낼 수 있어야 한다")

        store.focusMode = true
        #expect(store.messageFocusBlock == .myself)
        #expect(!store.canSendMessageNow && !store.canSendStickerNow)
        let composer = MessageComposerView(store: store)
        #expect(composer.sendHelp == WorkTimerStore.myFocusBlocksSendingNotice)
        composer.send()
        store.sendMessage(to: fsPlain, body: "답장")
        #expect(store.messageNotice == WorkTimerStore.myFocusBlocksSendingNotice)
        #expect(!store.sendSticker(.allCases[0]))

        // 기준선: 집중을 끄면 같은 문으로 나간다.
        store.focusMode = false
        store.messageNotice = nil
        composer.send()
        await messageReadWait { fsCalls(host, rpc: "send_message", to: fsPlain) >= 1 && !store.isSendingMessage }
        #expect(fsCalls(host, rpc: "send_message", to: fsPlain) == 1, "집중 중에 나간 요청이 섞였거나 기준선이 안 나갔다")
    }
}

// MARK: - ④ 낡은 명부 — target_focused 뒤 재조회 · 대화 화면 갱신

@MainActor
@Suite struct FocusSendGateDirectoryRefreshTests {
    @Test(.gomokuDefaultsCleanup)
    func 찌르기_울트라_메시지가_target_focused_를_받으면_명부를_다시_받는다() async {
        // 첫 명부는 그 사람을 집중 아님으로 안다(대화 중에 상대가 켠 경우) → 서버가 거절 → 두 번째 명부부터 집중.
        let (store, host) = fsStore("refetch", sendStatus: "target_focused", directory: { index in
            FsFx.directory(focusedPeerIsFocused: index > 0)
        })
        await fsLoadDirectory(store)
        #expect(!store.isPeerFocused(fsFocused), "전제: 첫 명부는 집중 아님")
        let before = MessageReadStubProtocol.count(host: host, rpc: "app_user_directory")

        store.sendPoke(to: fsFocused)
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "app_user_directory") >= before + 1 }
        #expect(store.pokeNotice == WorkTimerStore.targetFocusedNotice, "서버 문구가 바뀌었다 — 문구는 그대로 둔다")
        #expect(MessageReadStubProtocol.count(host: host, rpc: "app_user_directory") == before + 1)
        await messageReadWait { store.isPeerFocused(fsFocused) }
        #expect(store.isPeerFocused(fsFocused), "다시 받은 명부가 반영되지 않았다")

        // 울트라 · 메시지도 같은 처리다(명부가 다시 '모름'인 사람으로 — 집중 아님 행).
        store.sendUltraPoke(to: fsPlain)
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "app_user_directory") >= before + 2 }
        #expect(MessageReadStubProtocol.count(host: host, rpc: "app_user_directory") == before + 2)
        store.openMessagePanel(peer: fsPlain)
        store.sendMessage(to: fsPlain, body: "안녕")
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "app_user_directory") >= before + 3 }
        #expect(store.messageNotice == WorkTimerStore.messageTargetFocusedNotice)
        #expect(MessageReadStubProtocol.count(host: host, rpc: "app_user_directory") == before + 3)
    }

    @Test(.gomokuDefaultsCleanup)
    func 집중이_아닌_거절은_명부를_다시_받지_않는다() async {
        // 기준선(같은 스크립트 · 다른 status): target_on_phone 은 명부가 낡은 게 아니다 — 재조회 0건.
        let (store, host) = fsStore("no-refetch", sendStatus: "target_on_phone")
        await fsLoadDirectory(store)
        let before = MessageReadStubProtocol.count(host: host, rpc: "app_user_directory")
        store.sendPoke(to: fsPlain)
        await messageReadWait { store.pokeNotice == WorkTimerStore.targetOnPhoneNotice }
        await messageReadWait(0.3) { false }
        #expect(MessageReadStubProtocol.count(host: host, rpc: "app_user_directory") == before)
    }

    @Test(.gomokuDefaultsCleanup)
    func 대화_화면에_있는_동안에도_30초_틱이_명부를_갱신한다() async {
        let (store, host) = fsStore("conversation-tick", directory: { index in
            FsFx.directory(focusedPeerIsFocused: index > 0)
        })
        await fsLoadDirectory(store)
        store.openMessagePanel(peer: fsFocused)
        store.messageDraft = "안녕"
        #expect(store.isMessagePanelVisible && !store.isPokePanelVisible, "전제: 대화 화면이 떠 있고 콕 목록은 내려갔다")
        #expect(store.canSendMessageNow, "전제: 처음엔 집중 아님")
        let before = MessageReadStubProtocol.count(host: host, rpc: "app_user_directory")

        // 기준선: 팝오버가 닫혀 있으면 틱이 명부를 두드리지 않는다(v0.2.38 Q7 — 닫힌 팝오버 규약 그대로).
        store.isMenuPresented = false
        await store.refreshPokeDirectoryIfVisible()
        #expect(MessageReadStubProtocol.count(host: host, rpc: "app_user_directory") == before)

        // 열린 팝오버 + 대화 화면 → 틱 한 번에 한 건. 상대가 대화 중에 켠 집중이 화면 잠금까지 따라온다.
        store.isMenuPresented = true
        await store.refreshPokeDirectoryIfVisible()
        #expect(MessageReadStubProtocol.count(host: host, rpc: "app_user_directory") == before + 1, "대화 화면에 있는 동안 명부가 갱신되지 않는다")
        #expect(store.selectedMessagePeerIsFocused)
        #expect(!store.canSendMessageNow)
    }

    @Test(.gomokuDefaultsCleanup)
    func 대화_화면에서_팝오버를_다시_열면_명부를_한_번_받는다() async {
        let (store, host) = fsStore("conversation-reopen")
        store.openMessagePanel(peer: fsPlain)
        store.isMenuPresented = false
        let before = MessageReadStubProtocol.count(host: host, rpc: "app_user_directory")
        store.setMenuPresented(true)
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "app_user_directory") >= before + 1 }
        await messageReadWait(0.2) { false }
        #expect(MessageReadStubProtocol.count(host: host, rpc: "app_user_directory") == before + 1)
    }
}

// MARK: - ⑤ 대화 화면 렌더 — 머리 '집중 중' · 사유 줄 · 높이

private let fsPopoverCap = 700.0

@MainActor
private func fsMessagePanelStore(peerFocused: Bool, myFocus: Bool, label: String, function: String = #function) -> WorkTimerStore {
    let (store, _) = makeMessageReadStore(label, function: function)
    store.isMenuPresented = true
    store.displayNow = Fx.now
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    store.messageHistory = [
        MessageHistoryEntry(id: "a1", peerUserID: "u1", peerName: "영식", peerAvatarURL: nil, body: "점심 드셨어요?",
                            createdAt: Fx.now.addingTimeInterval(-300), isMine: false),
        MessageHistoryEntry(id: "a2", peerUserID: "u1", peerName: "영식", peerAvatarURL: nil, body: "네 곧 올릴게요",
                            createdAt: Fx.now.addingTimeInterval(-200), isMine: true),
    ]
    store.messageHistoryLoaded = true
    var entry = PokeDirectoryEntry(userID: "u1", name: "영식", avatarURL: nil, isWorking: true)
    entry.isFocused = peerFocused
    store.pokeDirectory = [entry]
    store.pokeDirectoryLoaded = true
    store.openMessagePanel(peer: "u1")
    store.messageDraft = "답장 초안"
    store.focusMode = myFocus
    // 사유 줄이 없을 때도 같은 자리에 한 줄이 서게 한다(전송 결과) — 높이 비교의 기준선이 '줄 하나'여야 머리가 자랐는지를 가른다.
    store.messageNotice = WorkTimerStore.messageSentNotice
    return store
}

@MainActor
private func fsMessageBitmap(_ store: WorkTimerStore, worstChrome: Bool = false) throws -> NSBitmapImageRep {
    let view = CheckMenuView(
        store: store,
        previewClipsOverflowList: true,
        previewGoalEditing: worstChrome,
        previewUpdateBanner: worstChrome,
        previewUpdateNotes: worstChrome ? ["긴 패치노트 한 줄", "두 줄", "세 줄", "네 줄 — 폭을 넘는 아주 긴 문구가 여기 들어간다"] : [],
        previewPlainTextEditors: true
    )
    return try #require(CheckRenderSettle.bitmap(view, scale: 2))
}

@MainActor
@Suite(.serialized) struct FocusSendGateMessagePanelRenderTests {
    @Test(.gomokuDefaultsCleanup)
    func 상대_집중은_머리에_칩을_그리고_패널_높이는_그대로다() throws {
        let plain = try fsMessageBitmap(fsMessagePanelStore(peerFocused: false, myFocus: false, label: "panel-plain"))
        let peer = try fsMessageBitmap(fsMessagePanelStore(peerFocused: true, myFocus: false, label: "panel-peer"))
        let mine = try fsMessageBitmap(fsMessagePanelStore(peerFocused: false, myFocus: true, label: "panel-mine"))
        // 머리 칩·사유 줄이 패널을 키우지 않는다(사유 줄은 전송 결과 줄의 자리를 쓴다).
        #expect(peer.pixelsHigh == plain.pixelsHigh, "상대 집중 표시가 대화 패널을 \(peer.pixelsHigh - plain.pixelsHigh)px 키웠다")
        #expect(mine.pixelsHigh == plain.pixelsHigh, "내 집중 사유 줄이 대화 패널을 \(mine.pixelsHigh - plain.pixelsHigh)px 키웠다")
        // 머리의 '집중 중' 칩(aiToken)은 상대 집중일 때만 그려진다.
        #expect(fsFocusInkCount(peer) > fsFocusInkCount(plain) + 40, "상대가 집중인데 대화 머리에 '집중 중'이 안 그려졌다")
        #expect(abs(fsFocusInkCount(mine) - fsFocusInkCount(plain)) < 40, "내 집중이 상대 머리에 '집중 중'을 그렸다")
        // 입력칸 위 줄이 사유(주황)로 바뀐다 — 기준선은 같은 자리의 "보냈어요"(초록)다.
        #expect(fsWarningInkCount(peer) > fsWarningInkCount(plain) + 40, "상대가 집중인데 입력칸 위에 사유가 안 섰다")
        #expect(fsWarningInkCount(mine) > fsWarningInkCount(plain) + 40, "내가 집중인데 입력칸 위에 사유가 안 섰다")
        // [보내기]가 흐려진다(accent 채움 100% → 35%).
        #expect(fsAccentCount(plain) > fsAccentCount(peer), "상대가 집중인데 [보내기]가 그대로다")
        #expect(fsAccentCount(plain) > fsAccentCount(mine), "내가 집중인데 [보내기]가 그대로다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 가장_키_큰_크롬에서도_집중_대화는_700pt_안이다() throws {
        let worst = try fsMessageBitmap(fsMessagePanelStore(peerFocused: true, myFocus: true, label: "panel-worst"), worstChrome: true)
        let height = Double(worst.pixelsHigh) / 2
        #expect(height <= fsPopoverCap, "집중 대화(최악 크롬)가 \(height)pt — 700pt 상한을 넘었다")
    }

    @Test func 사유_문장은_입력칸_위_한_줄에_든다() {
        // 작성기 고정 크롬(102pt)은 안내 한 줄만 센다 — 두 줄로 접히면 그만큼 푸터가 밀린다. caption2(10pt) · 292pt.
        let font = NSFont.systemFont(ofSize: 10)
        for text in [WorkTimerStore.myFocusBlocksSendingNotice, WorkTimerStore.messageTargetFocusedNotice, WorkTimerStore.targetFocusedNotice] {
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            #expect(width <= 292 - 20, "'\(text)'(\(width)pt)가 한 줄을 넘는다")
        }
        #expect(MessagePeerFocusChip.text == "집중 중")
    }
}

// MARK: - ⑥ 내 집중 따라잡기 — 같은 계정의 다른 맥이 끈 집중(2026-11-03 검토 P2)
//
// 요청 6 게이트는 이 맥의 focusMode 하나를 본다. 서버값은 로그인 때 한 번만 읽었으므로, 맥 A 에서 끄면 맥 B 는 재시작 전까지
// 켜짐을 쥐고 아무에게도 못 보냈다(예전엔 표시만 틀렸다). B 가 콕/대화 화면을 보는 동안 · 팝오버를 여는 순간 한 행 GET 으로 맞춘다.
// 기준선은 셋이다: 서버도 켜짐(그대로 잠김) · 서버가 모름(행 없음 — 그대로 잠김) · 이 맥이 꺼짐(GET 0건).

/// 프로필 GET 의 응답. nil 이면 **행이 없다**(`[]`), 그 밖에는 `focus_mode` 하나짜리 행.
@MainActor
private func fsSyncStore(
    _ label: String, serverFocus: Bool?, function: String = #function
) -> (store: WorkTimerStore, host: String) {
    let made = makeMessageReadStore(label, handler: { call, _ in
        switch call.rpc {
        case "app_user_directory": return FsFx.directory()
        case "/rest/v1/profiles":
            guard let serverFocus else { return MessageReadStubProtocol.Reply(body: "[]") }
            return MessageReadStubProtocol.Reply(body: Fx.json([["focus_mode": serverFocus]]))
        default: return nil
        }
    }, function: function)
    made.store.startedAt = Fx.now
    // 로그인 때 받은 서버값이 켜짐 + 이 맥에 단계 기록 없음 = 2단(계속) — 다른 맥에서 켠 집중을 이 맥이 아는 모양이다.
    made.store.applyServerFocusMode(true, intentSerialAtRequest: made.store.focusIntentSerial)
    return made
}

/// 내 집중만 묻는 GET(select=focus_mode) 의 수. 로그인 설정 GET(token_usage_* 를 함께 묻는다)은 세지 않는다.
private func fsMyFocusFetches(_ host: String) -> Int {
    MessageReadStubProtocol.calls(host: host, rpc: "/rest/v1/profiles").filter {
        let query = ($0.url.query ?? "").removingPercentEncoding ?? ""
        return query.contains("select=focus_mode") && !query.contains("token_usage")
    }.count
}

@MainActor
@Suite struct FocusSendGateMyFocusSyncTests {
    @Test(.gomokuDefaultsCleanup)
    func 다른_맥에서_끈_집중을_대화_화면의_틱이_따라잡아_보내기가_풀린다() async {
        let (store, host) = fsSyncStore("sync-off", serverFocus: false)
        store.isMenuPresented = true
        store.openMessagePanel(peer: fsPlain)
        store.messageDraft = "안녕"
        #expect(store.focusMode && !store.canSendMessageNow, "전제: 이 맥은 집중이라 알고 보내기가 잠겼다")

        await store.refreshPokeDirectoryIfVisible()
        #expect(fsMyFocusFetches(host) == 1, "콕/대화 화면 틱이 내 집중을 묻지 않았다")
        #expect(!store.focusMode, "서버가 꺼짐이라는데 이 맥이 켜짐을 쥐고 있다")
        #expect(store.canSendMessageNow, "다른 맥에서 끈 집중이 이 맥의 보내기를 계속 막는다")
        #expect(store.focusSendBlock(to: fsPlain) == nil)
    }

    @Test(.gomokuDefaultsCleanup)
    func 서버도_켜짐이면_그대로_잠겨_있다() async {
        // 기준선 ①: 같은 스크립트 · 서버값만 다르다.
        let (store, host) = fsSyncStore("sync-still-on", serverFocus: true)
        store.isMenuPresented = true
        store.openMessagePanel(peer: fsPlain)
        store.messageDraft = "안녕"
        await store.refreshPokeDirectoryIfVisible()
        #expect(fsMyFocusFetches(host) == 1)
        #expect(store.focusMode)
        #expect(!store.canSendMessageNow)
    }

    @Test(.gomokuDefaultsCleanup)
    func 서버가_모르면_켜짐을_풀지_않는다() async {
        // 기준선 ②: 행이 안 오면(RLS·일시 장애) 모름이다 — 꺼짐으로 접으면 장애 한 번에 집중이 조용히 풀린다.
        let (store, host) = fsSyncStore("sync-unknown", serverFocus: nil)
        store.isMenuPresented = true
        store.openMessagePanel(peer: fsPlain)
        store.messageDraft = "안녕"
        await store.refreshPokeDirectoryIfVisible()
        #expect(fsMyFocusFetches(host) == 1)
        #expect(store.focusMode, "행이 없다는 이유로 집중이 풀렸다")
        #expect(!store.canSendMessageNow)
    }

    @Test(.gomokuDefaultsCleanup)
    func 이_맥이_집중이_아니면_묻지_않는다() async {
        // 기준선 ③: 꺼진 맥은 요청 0건(틱 · 팝오버 다시 열기 둘 다).
        let (store, host) = fsSyncStore("sync-not-focused", serverFocus: true)
        store.applyServerFocusMode(false, intentSerialAtRequest: store.focusIntentSerial)
        #expect(!store.focusMode, "전제: 이 맥은 꺼짐")
        store.isMenuPresented = true
        store.openMessagePanel(peer: fsPlain)
        await store.refreshPokeDirectoryIfVisible()
        store.isMenuPresented = false
        store.setMenuPresented(true)
        await messageReadWait(0.3) { false }
        #expect(fsMyFocusFetches(host) == 0)
        #expect(!store.focusMode)
    }

    @Test(.gomokuDefaultsCleanup)
    func 팝오버를_다시_열면_홈_화면에서도_한_번_따라잡는다() async {
        let (store, host) = fsSyncStore("sync-reopen", serverFocus: false)
        #expect(!store.isPokePanelVisible && !store.isMessagePanelVisible, "전제: 콕/대화 화면이 아니다")
        store.isMenuPresented = false
        store.setMenuPresented(true)
        await messageReadWait { !store.focusMode }
        #expect(!store.focusMode, "팝오버를 다시 열어도 다른 맥에서 끈 집중을 모른다")
        #expect(fsMyFocusFetches(host) == 1)
    }
}

// MARK: - ⑦ 화면 배선 — 짝 게이트의 뷰 쪽 자리(2026-11-03 검토 P2)
//
// 행 시험(②)은 PokeDirectoryRowView 를 직접 만들어 isMyselfFocused 를 손으로 넘긴다. 그래서 부르는 자리를 지워도
// 기본값(false) 덕에 컴파일되고 초록이다 — 결과는 '내가 집중인데 찌르기 버튼이 살아 보이고 누르면 스토어만 조용히 막는' 화면이다.
// 이모티콘 칸의 사유 툴팁도 같다. 부르는 자리 글자를 주석을 걷고 잰다.

private func fsStripComments(_ source: String) -> String {
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
        } else {
            if c == "\"" { inString = true }
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out
}

@Suite struct FocusSendGateWiringTests {
    @Test func 콕_패널이_스토어의_내_집중을_행의_찌르기_버튼까지_넘긴다() throws {
        let menu = fsStripComments(try CheckCoreSourceLayout.joinedSplitSource("CheckMenuView.swift"))
        let flat = menu.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\n", with: "")
        #expect(flat.contains("isFocusMode:store.focusMode,"), "PokePanel 에 store.focusMode 가 안 내려간다")
        #expect(flat.contains("isMyselfFocused:isFocusMode,"), "PokePanel 이 행에 내 집중을 안 넘긴다 — 기본값 false 로 버튼이 살아 보인다")
    }

    @Test func 이모티콘_칸이_집중_사유를_툴팁으로_받는다() throws {
        let message = fsStripComments(try CheckCoreSourceLayout.joinedSplitSource("CheckMessageView.swift"))
        let flat = message.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\n", with: "")
        #expect(flat.contains("blockedHelp:store.messageFocusBlock?.messageText"), "이모티콘 칸이 집중 사유를 모른다 — '보내는 중'으로 접힌다")
    }
}

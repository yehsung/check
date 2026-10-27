import AppKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.62 — **키를 잃으면 멈춘다**(끝내지 않는다).
//
// 제보(0.3.61 · build 114 · 실사용자): "테트리스 일시정지하고 다른 창을 클릭하면 아예 끝나버려요."
// 원인은 `CheckMiniGameWindowController.windowDidResignKey` 가 **정지 중인지 묻지 않고** 무조건
// `miniGameInterruptToken` 을 올려 판을 끝낸 것이다. 그 자리의 원래 근거는 "안 보이는 창에서 60Hz 루프가
// 계속 돌면 안 된다(유휴 0% 불변)" 였는데, **정지 중에는 루프가 이미 완전히 멈춰 있다** —
// `TimelineView(.animation(paused: !game.isPlaying || host.isPaused))`(MiniGameTetris:94 · MiniGameFlappy:184).
// 즉 정지해 둔 판을 끝낼 이유가 애초에 없었다.
//
// 새 계약(사용자 확정 2026-10-21):
//   · 판이 도는 중에 키를 잃으면 → 끝내지 말고 **자동 일시정지**
//   · 이미 정지 중이면 → 그대로(아무 일도 없다 — 특히 정지 감시를 다시 걸지 않는다)
//   · 재개 카운트다운(`.resuming`) 중이면 → 카운트다운을 취소하고 다시 `.paused`
//   · 돌아오면 사용자가 [이어하기] 를 누른다. **자동 재개는 없다**
//   · 5분 정지 상한(`PauseState.pauseLimitSeconds`)은 그대로 살아 있다 — 순위 공정성의 보루다
//   · 창을 **닫는** 것은 지금도 판을 끝낸다(`windowWillClose`)
//
// 적대 심사가 그 수리에서 찾은 뒷구멍 둘을 아래 (e)(f) 가 막는다.
//   · (e) **남의 창에서 누른 ESC 가 정지해 둔 판을 재개한다.** "키 없는 창에 살아 있는 정지된 판" 이라는
//     상태가 이 수리로 **새로 생겼고**, ESC 모니터의 관대한 게이트(창 가시성 + `yieldsToOtherWindow`)는
//     그것을 가릴 수 없다 — 팝오버·할 일 보드는 identifier 가 없어 '모르는 창'으로 놓아 주기 때문이다.
//     그래서 팝오버를 닫으려고 누른 ESC 가 게임 창으로 가서 3-2-1 뒤 판을 풀었고(조작키는 전부 막혀 한 수도
//     못 두고 탑아웃 → 그 점수로 확정), 그 ESC 는 삼켜져 팝오버도 안 닫혔다. 고친 방향은 **ESC 에만**
//     짝 게이트(`strokeBelongsToGame`)를 다는 것이다 — 스페이스의 관대함은 그대로 둔다(창을 막 연 순간
//     스페이스가 죽는 2026-09-09 사고가 그 관대함의 이유다). 판정은 **순수 함수**(`PauseState.escaped`)로
//     떼어 둔다 — 뷰 클로저 안에 있던 동안은 헤드리스에서 못 불러 그물이 소스의 모양밖에 못 쟀고, 그 그물은
//     게이트 극성 반전도 `gameWindow: nil` 도 통째로 통과시켰다(= 결함이 초록인 채로 되살아난다).
//   · (f) **정지 상한이 테트리스에만 걸렸다.** `armPauseWatchdog` 의 `guard store.miniGameKind == .tetris` 는
//     "두 기존 게임은 한 판이 짧아 이 여유를 쓸 일이 없다"는 전제 위에 있었는데 자동 정지가 그 전제를
//     무너뜨렸다 — 플래피가 무기한 정지로 남고, 0.3.61 이 포커스 상실 때 해 주던 '그 점수로 확정'이 거기서
//     사라진다. 다만 가드를 **통째로 걷으면** 범위가 한 칸 넓어져 타이밍 바의 수동 정지까지 잘리는데,
//     거기서는 `interrupt()` 가 `invalidate()` 뿐이라 접어도 기록이 안 남는다 — 상한이 '점수를 건진다'가
//     아니라 '판을 없앤다'로 뒤집힌다. 그래서 범위는 이름이 아니라 **"접으면 기록이 남는가"** 로 가른다
//     (`PauseState.quittingKeepsTheScore`).
//
// 재는 방법은 둘로 갈린다. 전이 자체는 **순수 값**(`PauseState.resigningKey(isPlaying:)`)이라 결과를 직접 재고,
// 그 값을 화면에 배선한 자리(`.onChange`)는 SwiftUI 뷰의 @State 라 헤드리스에서 못 두드리므로 **소스 계약**으로
// 잰다(이 저장소가 `V0338TetrisMacTests` 의 '출구' 검사에서 쓰는 그 방법이다 — 블록을 중괄호 짝으로 잘라
// "그 블록 **안**에 있는가"를 본다. 파일 어딘가에 있으면 통과하는 느슨한 검사가 아니다).

private typealias Pause = CheckMiniGameWindowView.PauseState

// MARK: - 헬퍼

@MainActor
private func mgprStore(_ label: String = "", function: String = #function) -> WorkTimerStore {
    WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "anon"],
                   defaults: CheckTestScratch.defaults(label, function: function))
}

private func mgprRawSource(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("\(CheckCoreSourceLayout.directory(for: name))/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

private func mgprSource(_ name: String) throws -> String {
    mgprStripped(try mgprRawSource(name))
}

/// 주석을 걷어낸다. 안 걷으면 "설명을 지워야만 초록이 되는" 테스트가 된다(이 저장소의 기록된 함정).
private func mgprStripped(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                guard let end = rest.range(of: "*/") else { rest = ""; break }
                rest = rest[end.upperBound...]
                inBlock = false
                continue
            }
            if let open = rest.range(of: "/*") {
                kept += rest[..<open.lowerBound]
                rest = rest[open.upperBound...]
                inBlock = true
                continue
            }
            if let line2 = rest.range(of: "//") {
                kept += rest[..<line2.lowerBound]
                rest = ""
                continue
            }
            kept += rest
            rest = ""
        }
        output += kept + "\n"
    }
    return output
}

private enum MGPRError: Error { case region(String) }

/// 닻 뒤의 `{ … }` 블록을 중괄호 짝으로 잘라 돌려준다.
private func mgprRegion(after anchor: String, in source: String) throws -> String {
    guard let anchorRange = source.range(of: anchor) else { throw MGPRError.region("닻 없음: \(anchor)") }
    var index = anchorRange.upperBound
    while index < source.endIndex, source[index] != "{" { index = source.index(after: index) }
    guard index < source.endIndex else { throw MGPRError.region("블록 없음: \(anchor)") }
    var depth = 0
    let start = index
    while index < source.endIndex {
        if source[index] == "{" { depth += 1 }
        if source[index] == "}" {
            depth -= 1
            if depth == 0 { return String(source[start...index]) }
        }
        index = source.index(after: index)
    }
    throw MGPRError.region("블록이 안 닫힘: \(anchor)")
}

/// 두 닻 사이. 인자 하나(예: `install` 의 `onEscape:` 가지)만 떼어내는 데 쓴다.
private func mgprBetween(_ source: String, _ open: String, _ close: String) -> String? {
    guard let a = source.range(of: open),
          let b = source.range(of: close, range: a.upperBound..<source.endIndex) else { return nil }
    return String(source[a.upperBound..<b.lowerBound])
}

/// 선언 바로 위에 붙은 `///` 줄 묶음 = **그 선언의 계약 원문**. 여기만은 주석을 **안 걷은** 원문에서 읽는다 —
/// 재는 대상이 주석 자체이기 때문이다. 대신 "설명을 지우면 초록"이 되지 않게, 쓰는 쪽에서 *거짓 문구가 없다*와
/// *바로잡은 사실이 있다*를 **짝으로** 단언한다(이 저장소가 기록해 둔 함정의 반대편 구멍이다).
private func mgprDocComment(above anchor: String, inRaw source: String) throws -> String {
    guard let anchorRange = source.range(of: anchor) else { throw MGPRError.region("닻 없음: \(anchor)") }
    var lines = String(source[..<anchorRange.lowerBound])
        .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if !lines.isEmpty { lines.removeLast() }   // 선언 줄의 앞부분(들여쓰기)
    var block: [String] = []
    while let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("///") {
        block.insert(last, at: 0)
        lines.removeLast()
    }
    guard !block.isEmpty else { throw MGPRError.region("문서 주석 없음: \(anchor)") }
    return block.joined(separator: "\n")
}

/// 문서 주석 안의 **첫 괄호 묶음** = 그 계약이 나열한 '올리는 자리' 목록.
private func mgprFirstParenthetical(_ doc: String) throws -> String {
    guard let open = doc.firstIndex(of: "("),
          let close = doc[open...].firstIndex(of: ")") else { throw MGPRError.region("괄호 목록 없음") }
    return String(doc[doc.index(after: open)..<close])
}

// MARK: - (a) 판이 도는 중 키 상실 → 얼어붙고 판은 살아 있다

@Test("(a) 판이 도는 중 키를 잃으면 .paused 로 얼고, 판은 끝나지 않는다")
func resigningKeyWhileRunningFreezesTheRoundWithoutEndingIt() throws {
    // 전이의 결과를 직접 잰다 — "불렸다"가 아니라 "어디로 갔다".
    #expect(Pause.none.resigningKey(isPlaying: true) == .paused,
            "키를 잃었는데 안 얼었다 — 안 보이는 창에서 60Hz 루프가 돈다")
    // 얼었다 = 게임에 넘기는 `host.isPaused` 가 참 = TimelineView 가 멈춘다(유휴 0% 가 지켜지는 실제 경로).
    let frozen = try #require(Pause.none.resigningKey(isPlaying: true))
    #expect(frozen.isFrozen, "얼지 않은 상태로 갔다 — 판이 뒤에서 계속 돈다")
    #expect(frozen.showsCard, "정지 카드가 안 뜬다 — 돌아와서 [이어하기] 를 누를 길이 없다")
    #expect(frozen.countdown == nil, "키를 잃자마자 카운트다운이 시작됐다 — 안 보는 사이에 판이 풀린다")
}

// MARK: - (b) 이미 정지 중 키 상실 → 아무 일도 없다(정지 예산 시계가 리셋되지 않는다)

@Test("(b) 이미 정지 중 키 상실은 nil — 다시 얼리면 5분 상한이 영영 안 찬다")
func resigningKeyWhileAlreadyPausedChangesNothing() {
    #expect(Pause.paused.resigningKey(isPlaying: true) == nil,
            "이미 정지 중인데 또 전이한다 — 수신처가 정지 감시를 새로 걸어 1초 수면이 처음부터 간다")

    // ★ 이것이 (b) 의 **결과**다: 키를 잃었다 되찾기를 되풀이해도 전이가 한 번도 안 일어난다.
    //   한 번이라도 일어나면 `armPauseWatchdog()` 이 다시 걸리고, 그 감시는 1초를 **자고 나서** 누적을 올리므로
    //   1초 안에 반복되는 이탈은 `pausedSecondsUsed` 를 영영 0 으로 묶는다 → 5분 상한이 통째로 무력해진다
    //   (상한은 "안 돌아오면 그 점수로 확정"을 집행하는 순위 공정성의 보루다).
    var transitions = 0
    for _ in 0..<50 where Pause.paused.resigningKey(isPlaying: true) != nil { transitions += 1 }
    #expect(transitions == 0, "정지 중 키 상실이 \(transitions) 번 전이했다 — 상한 시계가 그만큼 리셋된다")

    // 전제 확인: 상한 자체는 살아 있다(끄거나 늘리지 않았다).
    #expect(Pause.pauseLimitSeconds == 5 * 60, "정지 상한이 바뀌었다 — 순위 공정성의 보루다")
}

// MARK: - (c) 카운트다운 중 키 상실 → 다시 .paused

@Test("(c) 재개 카운트다운 중 키를 잃으면 카운트다운을 취소하고 다시 언다")
func resigningKeyDuringTheResumeCountdownRefreezes() {
    // 3-2-1 어느 지점에서든 같다. 안 그러면 안 보이는 창에서 카운트다운이 흘러 판이 저절로 풀린다.
    for remaining in 1...Pause.countdownStart {
        #expect(Pause.resuming(remaining).resigningKey(isPlaying: true) == .paused,
                "카운트다운(\(remaining)) 중 키 상실이 .paused 로 안 간다 — 안 보는 사이에 판이 풀린다")
    }
    // ★ `toggled(isPlaying:)` 를 재사용하면 **반대 방향 사고**가 난다: 정지해 둔 판이 키를 잃는 순간 풀린다.
    //   이 두 줄이 "따로 둔 이유"를 못 박는다(기준선이 같은 입력이면 그 테스트는 영원히 초록이라는 그 함정 방지).
    #expect(Pause.paused.toggled(isPlaying: true) == .resuming(Pause.countdownStart))
    #expect(Pause.paused.resigningKey(isPlaying: true) != Pause.paused.toggled(isPlaying: true),
            "키 상실이 정지 토글과 같은 전이다 — 멈춰 둔 판이 키를 잃는 순간 풀린다")
}

// MARK: - (d) 판이 안 도는 중 키 상실 → 아무 일도 없다

@Test("(d) 시작 전·결과 화면에서 키를 잃어도 아무 일도 없다(얼리면 클릭이 안 먹는 창이 된다)")
func resigningKeyWhileNotPlayingDoesNothing() {
    #expect(Pause.none.resigningKey(isPlaying: false) == nil,
            "시작 전 화면이 얼었다 — 스크림이 덮여 아무것도 못 누른다")
    // 결과 화면도 같다(판이 스스로 끝나면 `isPlaying` 이 거짓이 된다).
    #expect(Pause.paused.resigningKey(isPlaying: false) == nil)
    #expect(Pause.resuming(2).resigningKey(isPlaying: false) == nil)
}

// MARK: - 창 → 스토어 → 화면 배선

@MainActor
@Test("스토어의 정지 요청 문은 토큰을 올리기만 한다 — 판을 끝내지 않는다")
func requestMiniGamePauseRaisesOnlyThePauseToken() {
    let store = mgprStore()
    store.isMiniGamePanelVisible = true
    let interrupt = store.miniGameInterruptToken
    let pause = store.miniGamePauseRequestToken

    store.requestMiniGamePause()
    #expect(store.miniGamePauseRequestToken == pause + 1, "정지 요청이 신호를 안 보낸다")
    #expect(store.miniGameInterruptToken == interrupt, "정지 요청이 판을 끝냈다 — 제보의 증상 그대로다")
    #expect(store.isMiniGamePanelVisible, "정지 요청이 창을 닫았다")

    store.requestMiniGamePause()
    #expect(store.miniGamePauseRequestToken == pause + 2, "연속 호출마다 새 신호여야 한다")
}

@Test("창 컨트롤러의 키 상실 처리기는 스토어의 정지 문으로만 간다(판 종료 경로를 안 탄다)")
func theResignKeyHandlerGoesThroughTheStorePauseDoor() throws {
    let window = try mgprSource("CheckMiniGameWindow.swift")
    let handler = try mgprRegion(after: "func windowDidResignKey(_ notification: Notification)", in: window)
    #expect(handler.contains("requestMiniGamePause()"), "키 상실이 정지를 요청하지 않는다")
    #expect(!handler.contains("endRound("), "키 상실이 아직 판을 끝낸다 — 제보가 그대로 재현된다")
    #expect(!handler.contains("miniGameInterruptToken"), "키 상실이 판 종료 토큰을 직접 올린다")
    // 창 **닫힘**은 지금도 판을 끝낸다(바꾸지 않기로 한 자리다 — 닫음은 분명한 의사표시다).
    let closing = try mgprRegion(after: "func windowWillClose(_ notification: Notification)", in: window)
    #expect(closing.contains("endRound(closing: true)"), "창을 닫아도 판이 안 끝난다 — 안 보이는 창에서 루프가 남는다")
    // 남의 창 알림 가드는 두 자리에 그대로 있어야 한다.
    #expect(handler.contains("=== windowStorage"), "남의 창 알림 가드가 없다 — 어떤 창을 클릭해도 우리 판이 멈춘다")
}

@Test("화면 수신처: 순수 값이 정하고, nil 이면 정지 감시를 다시 걸지 않는다")
func thePanelHandlerWiresThePureTransitionAndGuardsTheWatchdog() throws {
    let panel = try mgprSource("MiniGamePanel.swift")
    let block = try mgprRegion(after: ".onChange(of: store.miniGamePauseRequestToken)", in: panel)

    // 할지 말지를 화면이 또 판단하면 규칙이 두 벌이 된다 — 순수 값 하나가 정한다.
    #expect(block.contains("guard let next = pauseState.resigningKey(isPlaying: isPlaying) else { return }"),
            "수신처가 순수 전이를 안 쓴다 — 조건이 두 곳으로 갈린다")

    // ★ 순서는 `togglePause` 와 같아야 한다: 카운트다운 거두기 → 눌림 해제 → 상태 → 감시.
    let order = ["cancelResume()", "MiniGameKeyLatch.releaseAll(&input)", "pauseState = next", "armPauseWatchdog()"]
    var cursor = block.startIndex
    for step in order {
        let found = block.range(of: step, range: cursor..<block.endIndex)
        #expect(found != nil, "수신처에 \(step) 가 없거나 순서가 뒤집혔다")
        guard let found else { return }
        cursor = found.upperBound
    }

    // ★★ nil 가드가 `armPauseWatchdog()` **앞**에 있어야 (b) 가 성립한다. 뒤에 두면 이미 정지 중인 판도
    //    감시를 새로 걸어 1초 수면이 처음부터 가고, 되풀이되는 이탈이 5분 상한을 무력화한다.
    let guardIndex = try #require(block.range(of: "else { return }")).lowerBound
    let armIndex = try #require(block.range(of: "armPauseWatchdog()")).lowerBound
    #expect(guardIndex < armIndex, "가드가 감시 무장 뒤에 있다 — 정지 중 키 상실이 상한 시계를 리셋한다")

    // 판을 끝내는 신호는 이 자리에 없다(있으면 고치려던 바로 그 증상이 돌아온다).
    #expect(!block.contains("miniGameInterruptToken"), "정지 수신처가 판 종료 토큰을 올린다")
    #expect(!block.contains("abortMiniGameRound"), "정지 수신처가 판을 접는다")
    // 정지 예산을 되돌리지 않는다(되돌리면 회당 상한이 되어 벽시계를 무한히 늘릴 수 있다).
    #expect(!block.contains("pausedSecondsUsed"), "정지 수신처가 정지 예산을 건드린다")
    // 자동 재개 금지 — 돌아온 순간에 사람이 화면을 보고 있다는 보장이 없다.
    #expect(!block.contains("beginResume()"), "키를 잃은 판을 자동으로 재개한다")
    // 눌린 채 얼어붙는 출구이기도 하다(← 를 누른 채 다른 창을 클릭하는 그 경로).
    #expect(block.contains("MiniGameKeyLatch.releaseAll(&input)"), "얼어붙을 때 눌림을 안 비운다")
}

// MARK: - (e) 남의 창에서 온 ESC 는 정지해 둔 판을 안 건드린다

/// 화면에 올리되 보이지 않게(알파 0 · 화면 밖) — `strokeBelongsToGame` 이 `isVisible` 을 요구한다.
/// 클릭을 안 먹게 `ignoresMouseEvents` 를 켠다(알파 0 패널이 사용자 클릭을 훔친 사고가 이 저장소에 있다).
@MainActor
private func mgprWindow(identifier: String? = nil) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 200, height: 80),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    if let identifier { window.identifier = NSUserInterfaceItemIdentifier(identifier) }
    window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
    window.orderFrontRegardless()
    return window
}

/// ESC 판정은 이제 **순수 함수**다(`PauseState.escaped`) — 그래서 여기서 재는 것은 "그 함수를 쓰는가"가 아니라
/// **"무엇을 돌려주는가"** 다. 뷰 클로저에 박혀 있던 동안은 헤드리스에서 못 불러 단언이 전부 소스의
/// 모양(substring·순서)뿐이었고, 그 그물은 게이트 극성 반전도 `gameWindow: nil` 도 통째로 통과시켰다
/// (= 원래 결함 "남의 창 ESC 가 정지한 판을 재개한다"가 초록인 채로 되살아난다).
@MainActor
@Test("(e) 게임 창으로 간 ESC 만 전이한다 — 남의 창·창 없음·판이 안 도는 중은 전부 nil")
func escapedTransitionsOnlyForTheKeystrokeThatReachedTheGameWindow() {
    let game = mgprWindow(identifier: CheckMiniGameWindowController.frameAutosaveName)
    let popover = mgprWindow()           // identifier 없음 = 팝오버·할 일 보드와 같은 '모르는 창'
    defer { [game, popover].forEach { $0.orderOut(nil) } }

    // ── 전제 둘: 옛 게이트는 이 ESC 를 **전부 통과시킨다**(그래서 이 함수가 유일한 방벽이다) ──
    #expect(!MiniGameSpaceKey.yieldsToOtherWindow(popover, gameWindow: game),
            "전제: 스페이스 양보 판정은 이 창을 '모르는 창'으로 놓아 준다")
    #expect(Pause.paused.toggled(isPlaying: true) == .resuming(Pause.countdownStart),
            "전제: 게이트가 없으면 그 ESC 가 정지해 둔 판을 재개한다 — 이것이 막아야 하는 결과다")

    let states: [Pause] = [.none, .paused, .resuming(Pause.countdownStart), .resuming(1)]

    // ① 게임 창 ESC → **다음 상태**. 규칙은 `toggled` 한 벌이어야 한다(복제하면 언젠가 갈린다).
    for state in states {
        #expect(state.escaped(eventWindow: game, gameWindow: game, isPlaying: true)
                == state.toggled(isPlaying: true),
                "게임 창 ESC 가 \(state) 에서 토글 규칙과 다른 데로 갔다")
    }
    #expect(Pause.none.escaped(eventWindow: game, gameWindow: game, isPlaying: true) == .paused,
            "게임 창 ESC 가 판을 못 멈춘다 — 정지가 통째로 죽는다")
    #expect(Pause.paused.escaped(eventWindow: game, gameWindow: game, isPlaying: true)
            == .resuming(Pause.countdownStart),
            "게임 창 ESC 가 재개를 못 건다 — 멈춘 판에서 영영 못 빠져나온다")

    // ② 남의 창 · 키가 아직 어느 창에도 안 간 순간 · 게임 창을 모르는 순간 → **nil**.
    //    nil 이라야 수신처가 이벤트를 안 삼키고 그 창 몫으로 흘려보낸다(= 팝오버가 ESC 로 닫힌다).
    for state in states {
        #expect(state.escaped(eventWindow: popover, gameWindow: game, isPlaying: true) == nil,
                "남의 창 ESC 가 \(state) 를 움직였다 — 정지해 둔 판이 안 보는 사이에 풀린다")
        #expect(state.escaped(eventWindow: nil, gameWindow: game, isPlaying: true) == nil,
                "키가 안 간 순간의 ESC 가 \(state) 를 움직였다")
        #expect(state.escaped(eventWindow: game, gameWindow: nil, isPlaying: true) == nil,
                "게임 창을 모르는데 \(state) 를 움직였다 — 소유권을 못 가리면 받지 않는다")
    }

    // ③ 판이 안 도는 중 → nil. 시작 전·결과 화면의 ESC 까지 먹으면 다른 화면의 취소 키를 훔친다.
    for state in states {
        #expect(state.escaped(eventWindow: game, gameWindow: game, isPlaying: false) == nil,
                "판이 안 도는데 \(state) 에서 ESC 를 처리했다")
    }

    // ④ 보이지 않는 창은 게임 창이어도 아니다(소유권 판정이 `isVisible` 을 요구하는 그 자리).
    let hidden = mgprWindow(identifier: CheckMiniGameWindowController.frameAutosaveName)
    hidden.orderOut(nil)
    #expect(Pause.paused.escaped(eventWindow: hidden, gameWindow: hidden, isPlaying: true) == nil,
            "떠 있지도 않은 창의 ESC 를 받았다")
}

@MainActor
@Test("(e) 모니터까지 묶어서: 남의 창 ESC 는 삼켜지지 않고(팝오버가 닫힌다) 판도 그대로다")
func escapeThroughTheMonitorNeitherResumesTheRoundNorGetsSwallowed() {
    let game = mgprWindow(identifier: CheckMiniGameWindowController.frameAutosaveName)
    let popover = mgprWindow()
    defer { [game, popover].forEach { $0.orderOut(nil) } }

    // 화면의 ESC 수신처와 **같은 조립**: 순수 판정(제품 코드) → 적용. 조립이 실제로 그 모양인지는
    // 아래 소스 계약(`thePanelWiresEscapeThroughThePureGate`)이 **보조로** 잰다.
    final class Box { var state = Pause.paused }
    let box = Box()
    MiniGameSpaceKey.remove()
    MiniGameSpaceKey.install(shouldConsume: { true }, action: {},
                             onEscape: { eventWindow in
                                 guard let next = box.state.escaped(eventWindow: eventWindow,
                                                                    gameWindow: game,
                                                                    isPlaying: true)
                                 else { return false }
                                 box.state = next
                                 return true
                             })
    defer { MiniGameSpaceKey.remove() }

    #expect(MiniGameSpaceKey.fireEscapeForTesting(popover) == false,
            "남의 창 ESC 를 삼킨다 — ESC 로는 팝오버를 영영 못 닫는다")
    #expect(box.state == .paused,
            "남의 창 ESC 가 정지해 둔 판을 재개했다 — 안 보는 사이에 조각이 쌓여 탑아웃되고 그 점수로 확정된다")
    #expect(MiniGameSpaceKey.fireEscapeForTesting(nil) == false, "키가 안 간 순간의 ESC 로 판이 재개된다")
    #expect(box.state == .paused)

    // 게임 창에서 온 ESC 는 그대로 먹는다 — 엄격하게 해도 손실이 0 인 자리다(정지·재개는 판이 도는 중에만
    // 뜻이 있고, 그때 게임 창은 사용자가 보고 클릭해 둔 창이다).
    #expect(MiniGameSpaceKey.fireEscapeForTesting(game) == true, "게임 창의 ESC 가 안 먹는다 — 정지·재개가 통째로 죽는다")
    #expect(box.state == .resuming(Pause.countdownStart))
}

@Test("(e) 보조 소스 계약: 배선은 그 순수 함수를 부르는 얇은 줄뿐이고, 게임 창은 컨트롤러에서 온다")
func thePanelWiresEscapeThroughThePureGate() throws {
    let panel = try mgprSource("MiniGamePanel.swift")
    let install = try mgprRegion(after: "private func installSpaceKey()", in: panel)

    // 모니터가 **키가 향한 창을 넘겨야** 화면이 가릴 재료가 있다.
    #expect(panel.contains("if isEscape { return onEscape(target) }"),
            "모니터가 ESC 처리기에 이벤트 창을 안 넘긴다")

    // 화면의 ESC 가지: 판정은 통째로 순수 함수에 있고 여기는 배선뿐이다.
    let escape = try #require(mgprBetween(install, "onEscape: { eventWindow in", "gameWindow: {"),
                              "onEscape 가지를 못 찾았다 — 배선 모양이 바뀌었다")
    #expect(escape.contains("pauseState.escaped(eventWindow: eventWindow,"),
            "ESC 가 순수 게이트를 안 쓴다 — 판정이 다시 클로저 안으로 숨으면 그물이 모양밖에 못 잰다")
    #expect(escape.contains("gameWindow: CheckMiniGameWindowController.shared.currentWindow"),
            "게임 창을 컨트롤러에서 안 가져온다 — nil 을 넘기면 모든 ESC 가 게이트에 걸려 정지·재개가 통째로 죽는다")
    #expect(escape.contains("isPlaying: isPlaying"), "판이 도는지를 안 넘긴다")
    #expect(escape.contains("else { return false }"), "게이트에 걸린 ESC 를 삼킨다 — 남의 창 취소 키를 훔친다")
    #expect(!escape.contains("togglePause()"), "ESC 가 게이트 없는 토글로 되돌아갔다")

    // 순수 함수 쪽: 토글 규칙을 **불러 쓴다**(베껴 적으면 두 벌이 되어 언젠가 갈린다).
    let escaped = try mgprRegion(after: "func escaped(eventWindow:", in: panel)
    #expect(escaped.contains("toggled(isPlaying: isPlaying)"), "ESC 전이가 토글 규칙을 복제했다")
    #expect(escaped.contains("strokeBelongsToGame"), "소유권 판정이 방향키와 다른 자를 쓴다")

    // ★ 스페이스의 관대한 게이트는 **그대로 둔다** — 창을 막 연 순간 스페이스가 죽는 2026-09-09 사고가
    //   그 관대함의 이유다. 여기가 엄격해지면 "업데이트하고 처음 열어 플레이할 때 스페이스가 안 됐다"가 돌아온다.
    let action = try #require(mgprBetween(install, "action: {", "onEscape:"), "action 가지를 못 찾았다")
    #expect(!action.contains("strokeBelongsToGame"), "스페이스에 엄격한 게이트가 붙었다 — 창을 막 연 순간이 죽는다")
    #expect(panel.contains("guard !yieldsToOtherWindow(target, gameWindow: gameWindow()) else { return false }"),
            "스페이스의 양보 판정이 바뀌었다")

    // 버튼과 ESC 가 **같은 적용 함수**를 밟는다(순서가 두 벌이 되면 한쪽만 고쳐진 채 남는다).
    let toggle = try mgprRegion(after: "private func togglePause() -> Bool", in: panel)
    #expect(toggle.contains("applyPause(next)"), "[일시정지] 버튼이 ESC 와 다른 길로 간다")
}

// MARK: - (f) 정지 상한의 범위 — 접었을 때 **기록이 남는 게임**에만

/// 범위 판정도 순수 함수다(`PauseState.quittingKeepsTheScore`). 그 함수가 참이라고 말하는 것을 **엔진에서
/// 직접 재서** 대조한다 — 이름을 나열해 박은 표가 아니라 "접으면 기록이 남는가"라는 사실의 사본이어야 하기
/// 때문이다. 둘이 갈리면 여기가 빨개진다.
@Test("(f) 상한 범위 = 접었을 때 기록이 남는 게임. 엔진에서 재서 대조한다(이름표가 아니라 사실이다)")
func thePauseLimitAppliesExactlyToGamesWhoseInterruptKeepsAScore() {
    // 전제: 게임은 넷이다(다섯째가 생기면 이 단언이 그 사람을 여기로 데려온다). v0.3.67 에 넷째(길건너)가 와서 실제로
    // 이 단언이 발화했고, 아래 길건너 갈래를 엔진에서 재서 채웠다.
    #expect(MiniGameKind.allCases.count == 4, "게임 수가 바뀌었다 — 상한 범위를 다시 보라")

    // ── 테트리스: `interrupt()` 가 `.result` 로 **결과를 확정**한다. 잎 뷰는 `.result` 로 들어간 그 전이에서
    //    `host.onFinished(점수)` 를 부르므로(아래 소스 계약), 접으면 기록이 남는다.
    var tetris = TetrisGame(seed: 7)
    tetris.action()
    #expect(tetris.phase == .running, "전제: 테트리스가 안 돌고 있다")
    tetris.interrupt()
    #expect(tetris.phase == .result, "테트리스 interrupt 가 결과를 확정하지 않는다 — 상한이 점수를 못 건진다")

    // ── 플래피: 같다.
    var flappy = FlappyGame(seed: 7)
    flappy.flap()
    #expect(flappy.phase == .running, "전제: 플래피가 안 돌고 있다")
    flappy.interrupt()
    #expect(flappy.phase == .result, "플래피 interrupt 가 결과를 확정하지 않는다")

    // ── 타이밍 바: 끊는 길이 `invalidate()` 뿐이라 **판이 통째로 사라진다**(`.ready` 로 되돌아가고 점수가 없다).
    //    여기에 상한을 걸면 상한이 '점수를 건진다'가 아니라 '판을 없앤다'로 뒤집힌다 — 0.3.61 에 없던 손해다.
    var timing = TimingBarGame(seed: 7)
    timing.tap()
    timing.step(dt: 0.2)
    timing.tap()
    #expect(timing.total >= 0 && timing.round > 0, "전제: 타이밍 바가 한 라운드도 안 돌았다")
    timing.invalidate()
    #expect(timing.phase == .ready, "타이밍 바 invalidate 가 판을 안 비운다 — 아래 전제가 깨졌다")
    #expect(timing.total == 0, "타이밍 바를 끊었는데 점수가 남았다 — 그렇다면 상한을 걸어야 한다")

    // ── 길건너 아잉이(v0.3.67): `interrupt()` 가 그 점수(간 가장 앞 줄)로 결과를 확정한다 — 플래피와 같다.
    var crossy = CrossyGame(seed: 7)
    crossy.action()
    #expect(crossy.phase == .running, "전제: 길건너가 안 돌고 있다")
    crossy.interrupt()
    #expect(crossy.phase == .result, "길건너 interrupt 가 결과를 확정하지 않는다")

    // ── 범위는 위 사실의 사본이다.
    #expect(Pause.quittingKeepsTheScore(.crossy), "길건너가 상한 밖이다 — 자동 정지 뒤 무기한 정지로 토큰이 TTL 을 넘긴다")
    #expect(Pause.quittingKeepsTheScore(.tetris), "테트리스가 상한 밖으로 나갔다 — 무기한 정지가 돌아온다")
    #expect(Pause.quittingKeepsTheScore(.flappy),
            "플래피가 상한 밖이다 — 자동 정지가 생긴 뒤로 무기한 정지로 남아 토큰이 TTL 을 넘긴다")
    #expect(!Pause.quittingKeepsTheScore(.timingBar),
            "타이밍 바에 상한이 걸렸다 — 수동 정지 5분에 판이 기록 없이 사라진다(0.3.61 에 없던 손해다)")
}

@Test("(f) 보조 소스 계약: 상한은 그 순수 판정으로만 범위를 가르고, 자동·수동 정지가 같은 문으로 들어간다")
func thePauseWatchdogAsksThePureScopeQuestion() throws {
    let panel = try mgprSource("MiniGamePanel.swift")
    let watchdog = try mgprRegion(after: "private func armPauseWatchdog()", in: panel)

    #expect(watchdog.contains("guard PauseState.quittingKeepsTheScore(store.miniGameKind) else { return }"),
            "상한이 범위를 안 가른다 — 걷으면 타이밍 바의 수동 정지까지 5분에 기록 없이 잘린다")
    #expect(watchdog.contains("while pausedSecondsUsed < PauseState.pauseLimitSeconds"), "상한 시계가 없다")
    #expect(watchdog.contains("quitRound()"), "상한이 판을 접지 않는다")

    // 자동 정지 수신처는 종류를 **묻지 않는다** — 범위 판정은 한 자리(`armPauseWatchdog`)에만 있어야
    // 수동 정지와 갈리지 않는다.
    let resign = try mgprRegion(after: ".onChange(of: store.miniGamePauseRequestToken)", in: panel)
    #expect(resign.contains("armPauseWatchdog()"), "자동 정지가 상한을 안 건다")
    #expect(!resign.contains("miniGameKind"), "자동 정지가 범위를 따로 판단한다 — 규칙이 두 벌이 된다")

    // 접는 경로는 [그만두기]와 **같다**(`abortMiniGameRound`) — 0.3.61 이 포커스 상실 때 하던 것과 정확히 같다.
    let quit = try mgprRegion(after: "private func quitRound()", in: panel)
    #expect(quit.contains("store.abortMiniGameRound()"), "상한이 접는 경로가 [그만두기]와 다르다")

    // 범위 판정의 **근거**가 되는 잎 뷰 사실: 테트리스·플래피만 `.result` 전이에서 기록하고,
    // 타이밍 바의 interrupt 에는 `onFinished` 가 아예 없다. 이 셋 중 하나라도 바뀌면 범위를 다시 보라.
    // ★ 셋 다 **쪼갠 파일**이다(잎 뷰 + 코어 엔진). `joinedSplitSource` 로 이어 읽는다 — 반쪽만 읽으면
    //   아래 부정 단언이 다른 조각의 사실을 못 보고 조용히 통과한다(`splitSourcesAreNeverReadByHalfInSourceContracts`).
    let leaves = [
        ("테트리스", mgprStripped(try CheckCoreSourceLayout.joinedSplitSource("MiniGameTetris.swift"))),
        ("플래피", mgprStripped(try CheckCoreSourceLayout.joinedSplitSource("MiniGameFlappy.swift"))),
    ]
    for (leaf, source) in leaves {
        #expect(source.contains("if new == .result, old != .result { host.onFinished("),
                "\(leaf) 가 더는 interrupt 로 기록하지 않는다 — 상한 범위의 근거가 무너졌다")
    }
    let timing = try mgprRegion(
        after: "private func interrupt()",
        in: mgprStripped(try CheckCoreSourceLayout.joinedSplitSource("MiniGameTimingBar.swift"))
    )
    #expect(!timing.contains("onFinished"),
            "타이밍 바가 이제 끊을 때 기록한다 — 그렇다면 상한을 걸어야 한다(범위를 다시 보라)")
}

// MARK: - 계약 원문 — 잎 뷰가 읽는 **호스트 계약**이라 틀리면 다음 사람이 반대로 읽는다
//
// 여기만은 주석을 **안 걷은** 원문을 본다(재는 대상이 주석이다). 대신 "설명을 지우면 초록"이 되지 않게
// *거짓 문구가 없다* 와 *바로잡은 사실이 있다* 를 짝으로 단언한다.

@Test("interruptToken 계약 셋이 더는 '포커스 상실' 을 판 종료 신호로 적지 않는다")
func theInterruptContractsNoLongerListFocusLossAsAnEndingSignal() throws {
    // 전제: 포커스 상실은 정지 문으로 간다. 이 사실이 되돌아가면 아래 주석들이 다시 참이 되어 이 시험도 틀린다.
    let window = try mgprSource("CheckMiniGameWindow.swift")
    let handler = try mgprRegion(after: "func windowDidResignKey(_ notification: Notification)", in: window)
    #expect(handler.contains("requestMiniGamePause()") && !handler.contains("miniGameInterruptToken"),
            "전제가 깨졌다: 포커스 상실이 다시 판을 끝낸다")

    // 엔진 둘은 **쪼갠 파일의 조각**이라 떼기 전 이름으로 이어 읽는다(MiniGameEngine ⊂ MiniGame ·
    // FlappyGame ⊂ MiniGameFlappy). 테트리스 엔진만 쪼개지지 않은 파일이라 그대로 읽는다.
    let sites = [("미니게임 호스트", try CheckCoreSourceLayout.joinedSplitSource("MiniGame.swift"),
                  "package var interruptToken: Int"),
                 ("테트리스 엔진", try mgprRawSource("TetrisGame.swift"),
                  "package mutating func interrupt()"),
                 ("플래피 엔진", try CheckCoreSourceLayout.joinedSplitSource("MiniGameFlappy.swift"),
                  "package mutating func interrupt()")]
    for (file, raw, anchor) in sites {
        let doc = try mgprDocComment(above: anchor, inRaw: raw)
        let triggers = try mgprFirstParenthetical(doc)
        #expect(!triggers.contains("포커스 상실"),
                "\(file) 의 \(anchor) 가 아직 포커스 상실을 '올리는 자리'로 나열한다: \(triggers)")
        // 지워서 초록이 되지 않게 — 바뀐 사실을 **적었는가**.
        #expect(doc.contains("포커스 상실"),
                "\(file) 가 포커스 상실을 통째로 지웠다 — 0.3.61 을 기억하는 사람이 반대로 읽는다")
        #expect(doc.contains("멈춘다") || doc.contains("멈추므로"),
                "\(file) 가 '끝내지 않고 멈춘다' 를 안 적었다")
    }

    // 스토어 쪽: 둘째 신호가 생겼으니 '유일하게' 가 거짓이다.
    let storeDoc = try mgprDocComment(above: "var miniGameInterruptToken = 0",
                                      inRaw: try mgprRawSource("WorkTimerStore.swift"))
    #expect(!storeDoc.contains("유일하게 관찰 가능한 신호"),
            "interruptToken 이 아직 '게임을 멈추는 유일하게 관찰 가능한 신호' 라고 적혀 있다 — 바로 아래 둘째가 있다")
    #expect(storeDoc.contains("miniGamePauseRequestToken"),
            "둘째 신호를 이름으로 안 가리킨다 — 다음 사람이 어느 토큰을 올릴지 못 고른다")
}

@Test("정지 상한 주석이 막아 주지 못하는 것(앱 종료)을 막아 준다고 적지 않는다")
func thePauseLimitCommentDoesNotClaimItSurvivesAppQuit() throws {
    let raw = try mgprRawSource("MiniGamePanel.swift")

    // 전제: 상한을 집행하는 것은 1초씩 자는 Task 다 — 프로세스가 죽으면 같이 죽는다.
    let watchdog = try mgprRegion(after: "private func armPauseWatchdog()", in: mgprStripped(raw))
    #expect(watchdog.contains("Task { @MainActor in") && watchdog.contains("Task.sleep(for: .seconds(1))"),
            "전제가 바뀌었다: 상한이 더는 1초씩 자는 Task 가 아니다")

    for anchor in ["private func armPauseWatchdog()", "static let pauseLimitSeconds = 5 * 60"] {
        let doc = try mgprDocComment(above: anchor, inRaw: raw)
        #expect(!doc.contains("앱을 끄면 점수가 통째로 사라지고"),
                "\(anchor) 가 아직 '앱을 끄면 점수가 사라지는 것' 을 상한의 근거로 든다 — 상한은 그걸 못 막는다")
        #expect(!doc.contains("앱을 그냥 끄면 점수가 사라진다"),
                "\(anchor) 가 아직 앱 종료 손실을 상한이 막아 주는 것처럼 적는다")
        // 지워서 초록이 되지 않게 — 사실을 **적었는가**.
        #expect(doc.contains("앱이 켜진 채") || doc.contains("앱이 켜져 있는 동안"),
                "\(anchor) 가 '상한이 사는 경우는 앱이 켜진 채 5분이 지난 경우뿐' 이라는 사실을 안 적었다")
    }
}

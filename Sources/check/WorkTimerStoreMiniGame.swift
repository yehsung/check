import Foundation
import OSLog
import CheckCore

// MARK: - 미니게임 허브 (v0.2.46) — 패널 상태 · 최고기록 · 오늘 순위 · 공개 설정
//
// 게임 규칙은 여기 없다(MiniGameTimingBar / MiniGameFlappy 의 값 타입). 스토어는 패널 열고 닫기, 판이 끝난 점수의
// 로컬 최고 갱신과 업로드, 오늘(KST) 순위와 어제 1등 조회, 공개 토글만 맡는다. 순위 조회는 **열림·재오픈·제출 성공·
// 종류 전환 때만** 한다 — 30초 refresh 루프에 얹지 않는다(38명 × 30초에 곱해지는 요청은 무료 플랜의 몫이 아니다).
//
// 제출 인편(v0.3.39 — "점수를 못 올렸어요"를 없앤다)
//
// 끝난 판의 점수는 **어떤 경우에도 그 자리에서 사라지지 않는다.** 2026-09-27 진단에서 맥 제출 경로가 점수를 버리는
// 갈래가 다섯이었다: ① 판이 끝난 순간 토큰이 없으면 return ② 제출의 네트워크 실패 ③ 세션 세대 밀림(조용히) ④ `too_fast`
// 거절(그런데 서버가 재는 경과는 자라기만 한다 — 조금 뒤 같은 토큰이면 통과한다) ⑤ `token_used` 를 거절로 그림(실제로는
// **이미 기록됐다**는 뜻이라 거짓 경보). 그리고 ①의 뿌리는 토큰 요청 경합이었다 — 창 열기·판 시작·제출 뒤 셋이 "왕복 중"
// 가드 없이 서로의 진행 중 요청을 무효화해, 짧은 판을 연달아 하면 토큰이 영영 안 왔다.
//
// 이름·구조·주석 논리는 폰 `GamesMiniGameHub` 의 것을 그대로 옮겼다(`roundTokenInFlightKind` · `pendingSubmit` ·
// `isSubmitting` · `terminalSubmitStatuses` / `deadTokenStatuses`). 폰과 다른 점은 셋뿐이고 전부 이유가 있다.
//  · **인편이 칸 하나가 아니라 대기열이다**(`miniGamePendingSubmits`). 폰은 밀려나는 앞 판을 "한 번 더 보내고 버리는"데,
//    그 순서는 새 판의 `start_round` 가 밀려난 인편의 토큰을 죽이는 순서라 아래 불변식을 구조적으로 어긴다. 대기열이면
//    앞 인편이 끝나기 전에는 그 게임의 새 토큰을 받지 않으므로 불변식이 무조건 선다. 토큰을 실은 인편은 게임당 하나뿐이다
//    (서버가 미사용 토큰을 한 행만 두므로 둘일 수 없다) — 나머지는 **토큰을 기다리는 인편**(`token == nil`)이다.
//  · **`defaults` 에 계정별로 영속한다.** 맥 사용자는 앱을 자주 끄고 켠다 — 종료가 점수를 삼키면 안 된다. 30분(서버 TTL)을
//    넘긴 인편은 읽을 때 버린다(토큰이 죽었다).
//  · **`too_fast` 는 terminal 이 아니라 재시도 대상이다.** 서버는 `too_fast` 를 토큰을 소모하기 **전에** 돌려주고 경과는
//    단조증가라 나중 재시도가 통과한다. 폰은 terminal 로 두고 있는데 그게 틀렸다(폰은 다른 세션 몫 — 여기서 건드리지 않는다).
//
// ★ 불변식(이 절에서 제일 중요하다): **그 게임의 인편이 살아 있는 동안 그 게임의 `start_round` 는 나가지 않는다.**
//   서버 `minigame_start_round` 는 `on conflict (user_id, game) where used_at is null do update set id = gen_random_uuid()`
//   라 새 토큰을 받는 순간 아직 안 쓴 옛 토큰이 죽는다 — 순서가 뒤집히면 인편의 점수가 `no_token` 으로 죽는다.
//   그래서 선발급·판 시작은 인편이 있으면 토큰을 받는 대신 인편부터 민다(`prefetchMiniGameRoundToken` · `beginMiniGameRound`).
//
// 인편을 미는 방아쇠는 다섯이다: 깨어남(`handleWake`) · 앱 재활성화(`AppDelegate.applicationDidBecomeActive`) · 창 열기 ·
// 그 게임의 선발급/판 시작 직전 · 실패 뒤 백오프(2초 → 8초 → 30초 반복, TTL 안에서만).

/// 아직 서버가 받았다고 확인해 주지 않은 끝난 판 한 건 — **제출 인편**(폰 `pendingSubmit` 튜플의 맥판, 영속하므로 타입이다).
struct MiniGamePendingSubmit: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: MiniGameKind
    let score: Int
    /// 이 판의 토큰. nil 이면 **토큰을 기다리는 인편**이다 — 판이 끝난 순간 토큰이 없었다(왕복이 늦었거나 못 받았다).
    /// 왕복 중이던 응답이나 새 요청이 채운다(`adoptMiniGameTokenIntoWaitingPending`).
    var token: String?
    /// 그 토큰을 받은 시각(서버 `started_at` 의 로컬 거울). 수명 판정에 쓴다.
    var tokenIssuedAt: Date?
    /// 판이 끝난 시각. 토큰이 없는 인편의 수명은 여기서 센다.
    let recordedAt: Date
    /// 지금까지 실패한 횟수(백오프 단계). 영속한다 — 재시작이 백오프를 0 으로 되돌리지 않게.
    var attempts: Int
    /// 이 시각 전에는 다시 보내지 않는다(백오프). 영속하지 않는다 — 재시작은 그 자체가 재시도 방아쇠다.
    var nextRetryAt: Date? = nil
    /// 모르는 status 를 받았다 — **방아쇠**(깨어남·재활성화·창 열기·판 시작·판 끝)가 올 때까지 붙든다. 타이머도 제출 꼬리의
    /// 밀기도 이 인편을 건드리지 않는다(이해 못 한 거절을 두드리지 않는다). 영속하지 않는다 — 재시작은 방아쇠다.
    var heldUntilTrigger: Bool = false
    /// `no_token` 을 받아 **토큰을 기다리는 인편으로 한 번 되돌렸다.** 영속한다 — 재시작이 이 기회를 새로 주면 안 된다.
    ///
    /// 왜 한 번인가: `no_token` 은 우리가 든 토큰을 서버가 모른다는 뜻이고, 그 원인은 그 사이 `start_round` 가 그 행의 id 를
    /// 갈아 끼운 것이다(2026-09-27 실측: 제출과 `start_round` 가 같은 초에 날아가 `start_round` 가 먼저 닿은 여섯 판).
    /// 불변식이 그 경합을 막지만, 뚫렸을 때 점수를 버리지 않고 **새 토큰을 받아 다시** 올린다 — 서버의 시간 하한은
    /// 그대로 선다(새 토큰의 started_at 부터 다시 재므로 하한만큼 기다려야 통과한다 · 플래피 13점이면 11.63초).
    /// 두 번은 주지 않는다: 계속 `no_token` 이면 원인이 경합이 아니므로 두드려도 같은 답이고, 무한 왕복이 된다.
    var recoveredFromDeadTokenOnce: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, kind, score, token, tokenIssuedAt, recordedAt, attempts, recoveredFromDeadTokenOnce
    }

    /// 이 인편이 죽는 시각. 토큰이 있으면 토큰 발급 시각, 없으면 판이 끝난 시각 — **둘 중 이른 쪽** + TTL. 토큰은 발급
    /// 시각부터 서버 TTL 만큼만 살고, 토큰 없는 인편도 30분이 지나면 다른 날 순위표에 올라갈 수 있어 같은 수명을 준다.
    func deadline(ttl: TimeInterval) -> Date {
        min(recordedAt, tokenIssuedAt ?? recordedAt).addingTimeInterval(ttl)
    }

    func isExpired(at now: Date, ttl: TimeInterval) -> Bool { now >= deadline(ttl: ttl) }
}

/// 진행 중인 판 한 장의 장부(v0.3.67). 허브가 판 시작 · 점수 변화 · 판 끝을 적고, 판을 접는 자리가 읽는다.
struct MiniGameLiveRound: Equatable {
    let kind: MiniGameKind
    /// 지금까지의 점수(잎 뷰가 바뀔 때마다 알린다).
    var score: Int
    /// 이 판의 점수를 이미 올렸다(판 끝 · 접기 중 먼저 온 쪽). 두 번 올리지 않는다.
    var settled: Bool
}

/// 제출 결과 한 줄의 문장들. **사용자 말투 · 짧게.** 인편이 살아 있는 동안은 "못 올렸어요"가 아니다 — 아직 지지 않았다.
enum MiniGameSubmitCopy {
    /// 인편이 살아 있다(네트워크 실패 · `too_fast` · 세대 밀림 · 토큰 대기). 곧 다시 보낸다.
    static let pending = "기록을 올리는 중이에요 — 잠시만요"
    /// 토큰이 죽어 **그 판은 영영 못 올리는** 거절(`no_token`). 다음 판은 새 토큰이라 다시 올라간다(폰 `submitTokenDead` 와 같은 문장).
    static let tokenDead = "이번 판은 순위에 못 올렸어요 — 다음 판부터 다시 올라가요"
    /// 토큰 만료. 사람이 고칠 수 있는 유일한 거절이라("판을 너무 오래 끌었다") 이유를 밝힌다.
    static let tokenExpired = "판이 너무 오래 걸려 기록하지 못했어요"
    /// 그 밖의 명시적 거절(`invalid` · `unauthorized` · `no_profile`). 이유를 밝히지 않는다.
    static let refused = "점수를 못 올렸어요"
    /// 인편이 30분 안에 서버에 닿지 못해 버려졌다.
    static let expired = "점수를 못 올렸어요 — 연결을 확인해 주세요"
}

extension WorkTimerStore {
    /// 미니게임 경로의 진단 로그. 실패가 화면엔 "점수를 못 올렸어요" 한 줄로만 남아서, 그게 토큰
    /// 요청 실패인지·제출 시점 토큰 없음인지·서버 거절인지 갈리지 않았다(2026-09-14 신고 때 `log show`
    /// 로 확인하려 했는데 이 경로에 로그가 한 줄도 없었다).
    /// ⚠️ 거절 **status 이름까지만** 남긴다 — `need_seconds`/`elapsed_seconds` 는 "얼마나 더 기다리면
    ///    통과하는지"라서 로그(사용자가 볼 수 있다)에 남기면 위조 보조 도구가 된다.
    static var miniGameLogger: Logger { Logger(subsystem: "kingcheck", category: "minigame") }

    /// 토큰을 새로 받는 기준(초). 서버 TTL 30분보다 넉넉히 짧게 잡아, 만료된 토큰으로 제출해
    /// 판을 통째로 버리는 일이 없게 한다.
    ///
    /// ⚠️ v0.3.38 부터 **게임별**이다 — 판정은 `MiniGameKind.roundTokenReuseSeconds` 한 곳에서 나온다(테트리스는 12분).
    /// 이 상수는 기존 두 게임의 값(20분)을 가리키는 별명으로 남긴다: 여기를 고쳐도 테트리스는 안 움직인다.
    static let miniGameTokenRefreshSeconds: TimeInterval = MiniGameKind.flappy.roundTokenReuseSeconds

    /// 인편의 수명(초) = 서버 토큰 TTL(`minigame_round_ttl()` 30분). 넘긴 인편은 토큰이 죽었으므로 읽을 때 버린다.
    nonisolated static let miniGamePendingSubmitTTL: TimeInterval = 30 * 60

    /// 서버가 **명시적으로 거절**한 status. 이걸 받으면 그 토큰으로는 영영 못 올리므로 제출 인편을 지운다.
    /// (`token_used` 는 여기 없다 — 그건 **성공**이다. `too_fast` 도 없다 — **재시도 대상**이다. 아래 `performSubmitMiniGameScore` 주석.)
    ///
    /// ⚠️ `unauthorized`·`no_profile` 도 여기다. 둘은 **토큰이 아니라 호출자 쪽 거절**이라
    /// `minigame_submit_score` 가 uid·프로필 검사에서 곧장 돌아오고 30분 TTL 판정까지 가지도 않는다 —
    /// 즉 스스로 `token_expired` 로 바뀌지 않는다. 지우지 않으면 인편이 남아 **앱을 켤 때마다 영원히**
    /// 같은 토큰을 다시 보낸다(그 사이 선발급은 인편 가드에 막혀 그 게임의 새 토큰도 못 받는다).
    /// 다만 `miniGameDeadTokenStatuses` 에는 넣지 않는다 — 문구는 "점수를 못 올렸어요"(`refused`)로 남긴다.
    ///
    /// ★ 이 집합은 `performSubmitMiniGameScore` 에서 **재시도 집합보다 먼저** 본다. 순서를 뒤집으면 여기에 `too_fast` 를
    ///   되돌려 놓아도 동작이 안 바뀌어 등재가 죽은 글자가 된다(폰에서 실측한 함정). 두 집합은 서로소여야 한다 — 테스트가 센다.
    nonisolated static let miniGameTerminalSubmitStatuses: Set<String> =
        ["invalid", "no_token", "token_expired", "unauthorized", "no_profile"]
    /// 시간이 흐르면 **같은 토큰으로 통과하는** 거절. `too_fast` 는 토큰을 소모하기 전에 돌아오고(토큰이 살아 있다) 서버가
    /// 재는 경과는 자라기만 한다 — 그래서 인편을 남기고 **백오프 타이머**를 건다. 얼마나 기다릴지는 서버가 준 숫자로 계산하지
    /// 않는다(고정 간격뿐이다 — 그 숫자를 쓰는 순간 위조 보조 도구다).
    /// 모르는 status 는 여기 없다: 남기되 타이머 없이 방아쇠(깨어남·재활성화·창 열기·판 시작)에서만 다시 보낸다 —
    /// 이해 못 한 거절을 두드리지는 않되 점수를 버리지도 않는다(TTL 이 끝을 낸다).
    nonisolated static let miniGameRetryableSubmitStatuses: Set<String> = ["too_fast"]
    /// 토큰이 죽어 **그 판은 영영 못 올리는** 거절. 문구가 "못 올렸어요"(이유 없음)와 갈린다. terminal 의 부분집합이어야 한다.
    nonisolated static let miniGameDeadTokenStatuses: Set<String> = ["no_token", "token_expired"]

    /// 로컬 최고기록 키. **계정별**이다 — 같은 맥을 다른 계정이 쓰면 남의 최고를 물려받지 않게(로그아웃 리셋 대상이 아닌 이유).
    static func miniGameBestKey(userID: String?, kind: MiniGameKind) -> String {
        "check.minigame.best.\(userID ?? "local").\(kind.rawValue)"
    }

    /// 창이 닫힌 채 인편이 TTL 로 버려졌다는 표식의 영속 키. **계정별**이다(인편 키와 같은 이유).
    /// 창을 닫아 둔 사이에 점수가 죽으면 그 자리에서 말할 화면이 없다 — 다음에 창을 열 때 한 번 말하고 지운다.
    /// 앱을 끄고 켜도 남는다: 인편이 죽는 것은 대개 오프라인으로 오래 있다가 앱을 끈 경우다.
    static func miniGameLostNoticeKey(userID: String) -> String {
        "check.minigame.lostnotice.\(userID)"
    }

    /// 제출 인편의 영속 키. **계정별**이다(최고기록 키와 같은 이유 — 남의 점수를 내 이름으로 올리지 않는다).
    static func miniGamePendingKey(userID: String) -> String {
        "check.minigame.pending.\(userID)"
    }

    // MARK: 창 열고 닫기

    /// 팝오버 오른쪽 레일의 미니게임 버튼(v0.2.48 에 캡션 행에서 이사)의 액션. **별도 창**을 열고(v0.2.46) 오늘 순위를 받는다.
    ///
    /// 다른 패널을 닫지 않는다 — 창은 팝오버와 공존한다(다른 패널을 열어도 게임은 계속된다).
    /// 이미 열려 있어도 `show()` 는 멱등이라 앞으로 가져오기만 한다(최소화해 뒀다면 되살린다).
    ///
    /// **팝오버는 닫는다**(v0.2.49). 사용자 요구 2026-09-10: "미니게임 버튼은 눌렀을 때 미니게임 창
    /// 열리면서 상단 탭바 화면은 닫히게 해줘." 지금까지는 게임 창을 열어도 팝오버가 그 위에 남아
    /// 화면을 가렸다 — 창을 띄우는 `NSApp.activate()` 경로로는 팝오버가 닫히지 않는다는 것을
    /// 실측으로 확인했다(근거 표는 `WindowTopAnchor.dismissMenuPopover` 주석).
    ///
    /// 순서가 **창 먼저, 팝오버 나중**인 이유가 둘이다.
    ///  · 이 메서드는 팝오버 **안의** 버튼이 부른다. 먼저 닫으면 자기를 그린 뷰 계층을 액션 도중에 걷어낸다.
    ///  · 닫는 수단이 상태바 아이템 클릭이라, 창이 먼저 키를 가져간 뒤 눌러야 포커스가 게임 창에 남는다.
    ///
    /// **판은 안 끊긴다.** `miniGameInterruptToken` 을 올리는 곳은 게임 창 자신의 **닫힘**뿐이고(0.3.62 —
    /// 포커스 상실은 이제 이 토큰을 안 올리고 `requestMiniGamePause()` 로 **멈추게만** 한다)
    /// (`CheckMiniGameWindowController`), 팝오버가 닫히며 흐르는 `setMenuPresented(false)` 는 그 토큰을
    /// 건드리지 않는다 — 그 사실은 소스 계약 테스트가 이미 못 박고 있다.
    func openMiniGameWindow() {
        if !isMiniGamePanelVisible { isMiniGamePanelVisible = true }
        // 첫 프레임부터 빈 목록 자리에 "불러오는 중…"이 뜨게 한다(토큰 보드와 같은 규약 — 본문 자리에 동기화 문구 금지).
        if !miniGameBoardLoaded { miniGameBoardLoading = true }
        loadMiniGameBoard()
        // 창을 닫아 둔 사이에 죽은 점수가 있으면 **여기서 한 번 말하고 표식을 지운다**(아래 밀기가 문구를 덮기 전에).
        showMiniGameLostNoticeIfAny()
        // [역대] 를 보던 채로 닫았다가 다시 열면 역대 표도 새로 받는다(오늘 순위의 '열림' 방아쇠와 같은 자리 — 다른 맥에서
        // 세운 기록·남의 새 기록이 들어왔을 수 있다). [오늘] 이면 아무것도 안 나간다(역대는 처음 넘어갈 때 받는다).
        if miniGameBoardScope == .allTime {
            if !miniGameAllTimeLoaded { miniGameAllTimeLoading = true }
            loadMiniGameAllTimeBoard()
        }
        // 인편이 남아 있으면 **먼저 밀어낸다**(모든 게임의 것을). 선발급은 살아 있는 인편을 보면 스스로 비켜서므로
        // 여기서 풀어 두지 않으면 사람이 판을 시작할 때까지 토큰이 없다. 비워지는 순간 제출의 꼬리가 새 토큰을 받아 준다.
        retryMiniGamePendingSubmitIfAny()
        // 토큰을 **여기서** 미리 받는다. 판 시작에 받으면 플래피 즉사처럼 1초 안에 끝나는 판은
        // 왕복이 못 끝나 점수를 통째로 버린다(신고 2026-09-14의 둘째 원인). 일찍 받을수록
        // 서버가 재는 경과가 길어져 **더 관대해진다** — 정직한 플레이를 막을 수 없는 방향이다.
        prefetchMiniGameRoundToken(kind: miniGameKind)
        CheckMiniGameWindowController.shared.show()
        WindowTopAnchor.dismissMenuPopover()
    }

    /// 진입 버튼을 다시 눌렀을 때(열려 있으면 닫고, 아니면 연다). 창을 쓰는 지금도 남겨 두는 이유는 같은 버튼이
    /// 토글로 읽히기 때문이다 — 열린 창을 한 번 더 눌러 닫을 수 있어야 한다.
    func toggleMiniGamePanel() {
        if isMiniGamePanelVisible {
            closeMiniGamePanel()
            return
        }
        openMiniGameWindow()
    }

    /// 미니게임 창을 닫는다(진행 중인 판도 끝낸다 — interruptToken). 사용자가 타이틀바 빨간 점을 눌렀을 때는
    /// 컨트롤러의 `windowWillClose` 가 같은 두 값을 직접 맞춘다(그쪽은 `close()` 를 거치지 않는 경로다).
    /// 이미 닫혀 있으면 아무것도 하지 않는다 — 헛되이 토큰을 올려 잎 뷰를 깨우지 않게.
    func closeMiniGamePanel() {
        guard isMiniGamePanelVisible else { return }
        settleMiniGameLiveRound()
        isMiniGamePanelVisible = false
        miniGameInterruptToken += 1
        CheckMiniGameWindowController.shared.close()
    }

    /// 미니게임 창 머리글의 **1:1 오목** 입구. 오목 창을 띄우고 **이 창은 내린다**(0.3.50 · 2026-10-13 사용자 요청 —
    /// 로비 창이 뜬 뒤에도 미니게임 창이 남아 창 둘이 떠 있는 것이 지저분했다).
    ///
    /// 순서는 **여는 것이 먼저**다 — 대결 창이 키를 가져간 뒤에 이 창을 내린다(`openMiniGameWindow` 가 창 먼저 ·
    /// 팝오버 나중으로 정한 것과 같은 순서다).
    /// 이 문은 판이 도는 중에는 화면에 없다(같은 자리를 [일시정지] 가 쓴다) — 정지해 둔 판이 있었다면 여기서 끝난다
    /// (`closeMiniGamePanel()` 이 interruptToken 을 올린다). 0.3.62 전에는 대결 창이 키를 가져가는 순간
    /// `windowDidResignKey` 가 이미 판을 끝냈으니 결과가 같았지만, 지금 키 상실은 **멈추기만** 한다 —
    /// 그래서 여기서 판이 끝나는 이유는 이제 **창 닫힘** 하나다.
    func openGomokuFromMiniGame() {
        gomoku.openWindow(focusMatchID: nil)
        closeMiniGamePanel()
    }

    /// 미니게임 창 머리글의 **1:1 체스** 입구. 위와 같은 규약이다.
    func openChessFromMiniGame() {
        chess.openWindow(focusMatchID: nil)
        closeMiniGamePanel()
    }

    /// 미니게임 창 머리글의 **1:1 테트리스** 입구(v0.3.60). 위와 같은 규약이다 — 대결 창을 **먼저** 띄우고 이 창은 나중에 내린다.
    func openTetrisDuelFromMiniGame() {
        tetris.openWindow(focusMatchID: nil)
        closeMiniGamePanel()
    }

    /// 미니게임 창 머리글의 **아잉 큐브** 입구(v0.3.69). 위와 같은 규약이다 — 큐브 창을 **먼저** 띄우고 이 창은 나중에 내린다.
    func openRummyFromMiniGame() {
        rummy.openWindow(focusMatchID: nil)
        closeMiniGamePanel()
    }

    /// 진행 중인 판을 **사용자 의사로** 접는다(정지 카드의 [그만두기] — v0.2.48).
    ///
    /// 하는 일은 `miniGameInterruptToken += 1` 하나뿐이다. 그런데도 새 메서드를 낸 이유: 지금까지 이 토큰을
    /// 올리는 길은 창 컨트롤러가 스토어 프로퍼티를 **직접** 만지는 경로(`windowWillClose` · 그때는
    /// `windowDidResignKey` 도) 뿐이었고, 화면에서 부를 이름이 없었다. **창 닫힘과 같은 신호**를
    /// **사용자 의사**로 보내는 문이다(0.3.62 부터 포커스 상실은 이 신호가 아니다 — 멈추기만 한다).
    ///
    /// 판을 어떻게 접을지는 게임이 정한다 — 플래피는 그 순간 점수로 결과 확정, 타이밍 바는 10라운드를 못
    /// 채웠으므로 무효(`MiniGameHost.interruptToken` 주석). 스토어는 그 차이를 모른다.
    /// 창은 그대로 둔다(`isMiniGamePanelVisible` 을 안 내린다) — 그만둔 사람은 대개 다른 게임을 하려는 것이다.
    func abortMiniGameRound() {
        settleMiniGameLiveRound()
        miniGameInterruptToken += 1
    }

    // MARK: 진행 중인 판의 장부 (v0.3.67)
    //
    // 검토 지적(2026-10-27): 정지 카드가 "지금 그만두면 … 기록돼요" 라고 약속하는데, 멈춰 둔 채 **다른 게임 칩**을 누르면 점수가
    // 사라졌다(플래피 · 테트리스도 같다). `selectMiniGame` 이 interruptToken 을 올리고 종류를 바꾸면 그 갱신에서 잎 뷰가 통째로
    // 빠져 자기 `onChange(of: interruptToken)` 를 영영 못 본다 — `interrupt()` 도 `onFinished` 도 안 불린다.
    // 그래서 판을 접는 문(칩 전환 · 창 닫기 · 로그아웃 · [그만두기] · 정지 상한)은 **잎 뷰를 기다리지 않고** 장부의 점수를
    // 그 자리에서 올린다. 잎 뷰가 살아 있어 늦게 `onFinished` 를 부르면 장부가 이미 올렸음을 알고 건너뛴다.
    // 접었을 때 기록이 안 남는 게임(타이밍 바 — `quittingKeepsTheScore`)은 접어도 아무것도 안 올린다(그 판은 무효다).

    /// 판이 시작됐다(허브의 `onPlayingChanged(true)`).
    func beginMiniGameLiveRound(kind: MiniGameKind) {
        miniGameLiveRound = MiniGameLiveRound(kind: kind, score: 0, settled: false)
    }

    /// 진행 중인 판의 점수가 바뀌었다(허브가 잎 뷰의 `onScoreChanged` 를 그대로 넘긴다).
    func noteMiniGameLiveScore(kind: MiniGameKind, score: Int) {
        guard var round = miniGameLiveRound, round.kind == kind, !round.settled else { return }
        round.score = score
        miniGameLiveRound = round
    }

    /// 잎 뷰가 판을 끝냈다(`onFinished`) — 장부가 아직 안 올렸으면 그 점수를 올린다. **허브의 onFinished 는 이 문 하나로 온다.**
    /// 장부가 없으면(시작을 못 본 판 — 시험 · 옛 경로) 예전처럼 그대로 올린다.
    func finishMiniGameLiveRound(kind: MiniGameKind, score: Int) {
        if var round = miniGameLiveRound, round.kind == kind {
            guard !round.settled else { return }
            round.settled = true
            round.score = score
            miniGameLiveRound = round
        }
        recordMiniGameScore(kind: kind, score: score)
    }

    /// 판을 **접는 자리**(칩 전환 · 창 닫기 · 로그아웃 · [그만두기])에서 부른다. 돌던 판이 접어도 기록이 남는 게임이면
    /// 장부의 점수를 지금 올리고, 아니면(타이밍 바) 접기만 한다. 이미 올렸거나 판이 없으면 아무 일도 없다(멱등).
    func settleMiniGameLiveRound() {
        guard var round = miniGameLiveRound, !round.settled else { return }
        round.settled = true
        miniGameLiveRound = round
        guard CheckMiniGameWindowView.PauseState.quittingKeepsTheScore(round.kind) else { return }
        recordMiniGameScore(kind: round.kind, score: round.score)
    }

    /// 판 도중 토큰 갈아 끼우기(v0.3.67 — 길건너처럼 끝이 정해지지 않은 판). 허브의 토큰 감시가 판이 도는 동안 30초마다 부른다.
    ///
    /// 들고 있는 그 게임의 토큰이 `roundTokenMidRunRefreshSeconds` 보다 늙었으면 새로 받는다(서버가 안 쓴 토큰을 갈아 끼우며
    /// TTL 을 새로 센다 — `MiniGameKind.roundTokenMidRunRefreshSeconds` 주석). 아무것도 안 하는 자리:
    ///  · 그 게임이 갈아 끼우지 않는 게임이다(nil) · 아직 젊다 · 이미 왕복 중이다.
    ///  · **그 게임의 인편이 살아 있다** — 불변식(머리 주석): 새 토큰을 받는 순간 인편이 든 옛 토큰이 죽는다. 인편을 먼저 민다.
    /// 들고 있는 토큰이 아예 없으면(판 시작 왕복이 실패했다) 받는다 — 그 판이 끝나기 전에 쥐어야 한다.
    func keepMiniGameRoundTokenFresh(kind: MiniGameKind, now: Date = Date()) {
        guard let limit = kind.roundTokenMidRunRefreshSeconds else { return }
        guard session != nil, miniGamePublic else { return }
        if hasMiniGamePendingSubmit(for: kind) {
            retryMiniGamePendingSubmitIfAny()
            return
        }
        guard miniGameRoundTokenInFlightKind != kind else { return }
        if miniGameRoundToken != nil, miniGameRoundTokenKind == kind, let issued = miniGameRoundTokenAt,
           now.timeIntervalSince(issued) < limit {
            return
        }
        Self.miniGameLogger.notice("round token refreshed mid-run game=\(kind.rawValue, privacy: .public)")
        requestMiniGameRoundToken(kind: kind)
    }

    /// 미니게임 창이 **키를 잃었다** — 진행 중인 판을 일시정지해 달라고 화면에 알린다(0.3.62).
    ///
    /// 왜 창 컨트롤러가 화면에 직접 말하지 않고 스토어를 거치는가: **정지 상태의 유일한 소유자가 허브 뷰**다
    /// (`CheckMiniGameWindowView.PauseState` — 스크림·정지 카드·3-2-1 카운트다운·5분 상한이 전부 그 @State 안에 있다).
    /// 컨트롤러가 쥔 것은 NSWindow 뿐이고 그 안의 SwiftUI @State 를 만질 길이 없다. 그래서 `@Observable` 스토어의
    /// 토큰을 올리고 화면이 `.onChange` 로 받는다 — `miniGameInterruptToken` 과 똑같은 배선이고, 이 저장소가
    /// "창은 스토어를 거쳐 화면에 말한다"로 이미 치러 본 값이다.
    ///
    /// `abortMiniGameRound()` 와 토큰을 **나눠 쓴다**(위 프로퍼티 주석). 멈출지 말지는 **화면이** 정한다 —
    /// 판이 안 도는 중이거나 이미 정지 중이면 아무 일도 없다(`PauseState.resigningKey`). 스토어는 그 조건을
    /// 모른다(진행 여부·정지 상태가 전부 뷰의 @State 안이다).
    func requestMiniGamePause() {
        miniGamePauseRequestToken += 1
    }

    /// 게임 종류 전환. 진행 중인 판을 끝내고(토큰) 그 게임의 오늘 순위를 다시 받는다. 선택은 영속한다.
    func selectMiniGame(_ kind: MiniGameKind) {
        guard kind != miniGameKind else { return }
        // 돌던(또는 멈춰 둔) 판을 **먼저** 접어 올린다 — 잎 뷰는 이 갱신에서 통째로 사라져 자기 `interruptToken` 을 못 본다.
        settleMiniGameLiveRound()
        miniGameKind = kind
        defaults.set(kind.rawValue, forKey: Self.miniGameKindKey)
        miniGameInterruptToken += 1
        // 지난 게임의 토큰은 여기서 버린다. 서버가 게임까지 대조하므로 남겨 둬도 사고는 안 나지만,
        // 남은 값이 "쓸 수 있는 토큰"처럼 보이면 다음 사람이 그렇게 읽는다.
        // 지난 게임의 **인편은 버리지 않는다** — 그 점수는 그 게임의 것이고, 방아쇠가 오면 그대로 나간다.
        miniGameRoundToken = nil
        miniGameRoundTokenKind = nil
        miniGameRoundTokenAt = nil
        miniGameRoundGeneration += 1
        // 세대를 올렸으니 떠 있던 요청의 defer 는 깃발을 못 내린다 — 여기서 내린다(아래 선발급이 새 게임으로 다시 세운다).
        miniGameRoundTokenInFlightKind = nil
        miniGameSubmitNotice = nil
        // 바뀐 게임의 토큰을 미리 받아 둔다 — 첫 판이 짧아도(플래피 즉사) 왕복이 끝나 있다.
        prefetchMiniGameRoundToken(kind: kind)
        // 이전 게임의 행이 잠깐 남아 '이 게임 순위인 척' 보이지 않도록 비우고 로드 전 상태로 되돌린다.
        miniGameBoard = []
        miniGameBoardLoaded = false
        miniGameBoardFailed = false
        miniGameYesterdayWinner = nil
        miniGameBoardLoading = true
        loadMiniGameBoard()
        // 역대 표도 같은 이유로 비운다(앞 게임의 역대 1등이 '이 게임 1등인 척' 보이면 안 된다). [역대] 를 보는 중이면
        // 바뀐 게임의 역대를 곧바로 받고, [오늘] 이면 다음에 [역대] 로 넘어갈 때 받는다(freshKind = nil).
        miniGameAllTimeBoard = []
        miniGameAllTimeLoaded = false
        miniGameAllTimeFailed = false
        miniGameAllTimeUnavailable = false
        miniGameAllTimeFreshKind = nil
        miniGameAllTimeInvalidation &+= 1
        miniGameAllTimeLoading = miniGameBoardScope == .allTime
        if miniGameBoardScope == .allTime { loadMiniGameAllTimeBoard() }
    }

    // MARK: 최고기록 · 제출

    /// 이 계정·이 게임의 로컬 최고기록(전체 기간). 결과 화면의 "최고 N"과 신기록 판정에 쓴다.
    func miniGameBest(_ kind: MiniGameKind) -> Int {
        max(0, defaults.integer(forKey: Self.miniGameBestKey(userID: session?.userID, kind: kind)))
    }

    /// 로컬 최고를 올린다(내려가지 않는다). 순위 응답의 내 행이 로컬보다 클 때(다른 맥에서 세운 기록)도 여기로 온다.
    func raiseMiniGameBest(_ kind: MiniGameKind, to score: Int) {
        guard score > miniGameBest(kind) else { return }
        defaults.set(score, forKey: Self.miniGameBestKey(userID: session?.userID, kind: kind))
    }

    /// 들고 있는 토큰이 이 게임에 **지금 쓸 수 있는가.** TTL(서버 30분)에 닿기 전에 새로 받으려고
    /// 여유를 크게 둔다 — 만료된 토큰으로 제출하면 그 판은 통째로 못 올린다.
    func hasUsableMiniGameToken(for kind: MiniGameKind) -> Bool {
        guard miniGameRoundToken != nil, miniGameRoundTokenKind == kind,
              let issued = miniGameRoundTokenAt else { return false }
        // 나이 기준은 **게임별**이다(테트리스 판은 길어서 12분 — MiniGameKind.roundTokenReuseSeconds 의 검산).
        return Date().timeIntervalSince(issued) < kind.roundTokenReuseSeconds
    }

    /// 토큰을 **미리** 받아 둔다. 게임 창을 열 때·게임을 바꿀 때·제출이 끝난 뒤에 부른다.
    ///
    /// ★ **일찍 받을수록 안전하다.** 서버의 시간 하한은 `started_at` 기준이라 토큰이 오래될수록
    ///   경과가 길어져 **더 관대해진다**(정직한 플레이를 막을 수 없다). 반대로 늦게 받으면 막힌다 —
    ///   플래피 즉사처럼 1초 안에 끝나는 판은 판 시작에 요청해서는 왕복이 못 끝난다.
    /// 이미 쓸 수 있는 토큰을 들고 있으면 **다시 받지 않는다** — 다시 받으면 서버가 `started_at` 을
    ///   now() 로 되돌려(행을 갈아 끼운다) 애써 벌어 둔 여유가 사라진다.
    func prefetchMiniGameRoundToken(kind: MiniGameKind) {
        guard miniGamePublic, session != nil else { return }
        // ★ 그 게임의 **인편이 살아 있으면 받지 않고 인편부터 민다.** 서버는 (사용자, 게임)당 미사용 토큰을 한 행만 두고
        //   새 요청이 오면 갈아 끼운다(`minigame_rounds_one_open`) — 그래서 `requestMiniGameRoundToken` 주석의
        //   "새 요청이 나가는 순간 들고 있던 것은 죽는다"가 **인편이 들고 있는 토큰에도 그대로** 걸린다.
        //   제출이 네트워크로 실패한 직후 여기서 새 토큰을 받으면, 재시도는 `no_token`(terminal)을 받고
        //   인편이 버려진다 — 인편이라는 장치의 유일한 이득이 자기 손으로 무너진다.
        //   막힌 채로 굳지 않는다: 인편이 비워지는 순간 `performSubmitMiniGameScore` 의 꼬리가 여기를 다시 불러 새 토큰을 받는다.
        //   토큰을 기다리는 인편뿐이면 미는 쪽이 알아서 요청을 띄운다(그 토큰은 살아 있는 판이 아니라 인편이 받는다).
        if hasMiniGamePendingSubmit(for: kind) {
            retryMiniGamePendingSubmitIfAny()
            return
        }
        guard !hasUsableMiniGameToken(for: kind) else { return }
        // 왕복 중이면 **또 보내지 않는다.** 또 보내면 서버가 started_at 을 새로 찍어 앞 요청이 벌어 둔 여유를 버리고,
        // 앞 요청의 응답은 세대 가드에 버려진다 — 창 열기·판 시작·제출 뒤 셋이 이 가드 없이 서로를 무효화한 것이
        // 2026-09-27 진단의 뿌리 원인이다(짧은 판을 연달아 하면 토큰이 영영 안 왔다).
        guard miniGameRoundTokenInFlightKind != kind else { return }
        requestMiniGameRoundToken(kind: kind)
    }

    /// 판이 **시작됐다**(게임 잎 뷰의 onPlayingChanged(true)).
    ///
    /// ★ **반드시 시작 시점이어야 한다.** 서버는 토큰 발급 시각부터 제출까지의 경과가 그 점수를 낼 수
    ///   있는 **구조적 최소 시간**보다 긴지 본다(타이밍바는 10라운드 주기 합의 절반, 플래피는
    ///   기둥간격/속도의 누적 합 — 게임 상수에서 나오는 물리량이라 정직한 플레이는 정의상 못 깬다).
    ///   끝날 때 받으면 경과가 0 이라 무조건 거절된다.
    ///
    /// ★ **게임을 막지 않는다.** Task 로 띄우고 응답을 기다리지 않는다 — 네트워크 때문에 60Hz 판이
    ///   버벅이면 안 된다. 토큰이 늦거나 못 오면 그 판의 점수는 **토큰을 기다리는 인편**이 된다(버리지 않는다).
    ///
    /// 선발급이 성공해 쓸 수 있는 토큰을 이미 들고 있으면 **아무것도 하지 않는다**(위 주석의 그 이유).
    /// 선발급이 실패했거나 토큰이 오래됐을 때만 여기서 받는다 — 그 경우에도 게임을 막지 않는다.
    func beginMiniGameRound(kind: MiniGameKind) {
        guard miniGamePublic, session != nil else { return }
        miniGameSubmitNotice = nil
        guard !hasUsableMiniGameToken(for: kind) else { return }
        // ★ 이 게임의 인편이 살아 있으면 토큰을 받는 대신 **인편부터 밀어낸다**(까닭은 `prefetchMiniGameRoundToken` 의 가드).
        //   이번 판이 토큰 없이 시작될 수는 있다 — 그러면 이 판의 점수는 토큰을 기다리는 인편이 되어 앞 인편이 비워진 뒤
        //   토큰을 받는다. 앞 판을 확실히 버리는 것보다 싸다.
        if hasMiniGamePendingSubmit(for: kind) {
            retryMiniGamePendingSubmitIfAny()
            return
        }
        guard miniGameRoundTokenInFlightKind != kind else { return }
        requestMiniGameRoundToken(kind: kind)
    }

    /// 토큰 요청 한 번. **세대를 올리고** 그 세대로 응답을 검증한다. 왕복 중 깃발을 세운다.
    func requestMiniGameRoundToken(kind: MiniGameKind) {
        // 지금 들고 있는 것은 버린다 — 서버가 행을 갈아 끼우므로 새 요청이 나가는 순간 죽는다.
        miniGameRoundToken = nil
        miniGameRoundTokenKind = nil
        miniGameRoundTokenAt = nil
        miniGameRoundGeneration += 1
        miniGameRoundTokenInFlightKind = kind
        let generation = miniGameRoundGeneration
        Task { @MainActor in await performBeginMiniGameRound(kind: kind, roundGeneration: generation) }
    }

    /// 위의 본체. 실패는 **조용히** — 토큰이 없는 것은 판이 끝날 때 인편이 말한다(두 번 말하지 않는다).
    func performBeginMiniGameRound(kind: MiniGameKind, roundGeneration: Int) async {
        // 왕복이 끝났다 — 내 세대가 아직 최신일 때만 깃발을 내린다(내 뒤에 나간 요청의 깃발을 내가 내리면 안 된다).
        defer { if roundGeneration == miniGameRoundGeneration { miniGameRoundTokenInFlightKind = nil } }
        guard session != nil else { return }
        // 깨어남 게이트가 서 있으면 기다린다(Wi-Fi 가 붙기 전의 요청 폭주에 끼지 않는다 — enqueueSync 와 같은 규약).
        await awaitWakeGate()
        let generation = sessionGeneration
        do {
            let response = try await withSessionRetry { activeSession in
                try await service.startMiniGameRound(accessToken: activeSession.accessToken, kind: kind)
            }
            guard generation == sessionGeneration else { return }
            // ★ **늦게 온 응답은 버린다.** 서버는 (user_id, game) 당 미사용 토큰을 한 행만 두고
            //   start_round 가 그 행의 id 를 갈아 끼우므로, 내 뒤에 나간 요청이 있었다면 내 토큰은
            //   이미 죽었다. 세대가 밀렸으면 그걸로 덮지 않는다(실사용 신고 2026-09-14의 원인).
            guard roundGeneration == miniGameRoundGeneration else { return }
            guard let token = response.token, response.status == "ok" else {
                Self.miniGameLogger.notice(
                    "round token refused status=\(response.status, privacy: .public) game=\(kind.rawValue, privacy: .public)")
                deferMiniGamePendingTokenWait(kind: kind)
                return
            }
            // ★ 토큰을 기다리는 인편이 있으면 **그 인편이 먼저 받는다**(살아 있는 판보다 앞). 이 요청은 그 판이 시작될 때
            //   나간 것이라 서버의 started_at 은 그 판보다 앞이다 — 지금 주면 바로 제출할 수 있다. 판이 끝난 뒤에 나간
            //   요청이었다면 서버가 too_fast 를 줄 수 있는데, 경과는 자라기만 하니 백오프 재시도가 통과시킨다.
            //   살아 있는 판은 이 인편이 비워지는 순간 제출의 꼬리가 새 토큰을 받아 준다.
            if adoptMiniGameTokenIntoWaitingPending(kind: kind, token: token) {
                retryMiniGamePendingSubmitIfAny(fromTrigger: false)
                return
            }
            miniGameRoundToken = token
            miniGameRoundTokenKind = kind
            miniGameRoundTokenAt = Date()
        } catch {
            // 취소·오프라인·스키마 부재(서버 배포 전 창) 전부 여기로 온다. 토큰이 없는 채로 두고,
            // 판이 끝나면 recordMiniGameScore 가 인편으로 남긴다. 토큰을 기다리는 인편이 있으면 백오프 뒤 다시 받는다.
            guard roundGeneration == miniGameRoundGeneration else { return }
            Self.miniGameLogger.notice("round token request failed game=\(kind.rawValue, privacy: .public)")
            deferMiniGamePendingTokenWait(kind: kind)
        }
    }

    /// 유효하게 끝난 판의 점수(게임 잎 뷰의 onFinished). 범위 밖(음수·상한 초과)은 버린다 — 서버 check 제약과 같은 값이라
    /// 보내 봐야 400 이다. 로컬 최고를 올리고, 공개가 켜져 있으면 **판마다** 올린다(최고 유지·판 수는 서버 몫).
    ///
    /// 여기서부터 점수는 **인편**이다 — 제출을 시도하기 **전에** 적는다. 지우는 것은 `ok` · `token_used` · terminal 거절뿐이고
    /// 네트워크 실패·세대 밀림·`too_fast` 는 남긴다(다섯 갈래 전부 이 한 줄에서 막힌다).
    func recordMiniGameScore(kind: MiniGameKind, score: Int) {
        guard score >= 0, score <= kind.maxScore else { return }
        raiseMiniGameBest(kind, to: score)
        // 공개를 끈 사람은 순위표에 없고, 그래서 올릴 이유도 없다(끄면 "올라가지도 않아요" — 설정 문구가 약속한 것).
        guard miniGamePublic, session != nil else { return }
        loadMiniGamePendingSubmitsIfNeeded()
        var token: String?
        var issuedAt: Date?
        if let held = miniGameRoundToken, miniGameRoundTokenKind == kind {
            // 한 토큰에 한 점수다. 여기서 비워 두면 같은 토큰이 두 번 나가지 않는다 — 인편이 그 토큰의 유일한 주인이 된다.
            token = held
            issuedAt = miniGameRoundTokenAt ?? Date()
            miniGameRoundToken = nil
            miniGameRoundTokenKind = nil
            miniGameRoundTokenAt = nil
        } else {
            // 토큰이 없다. **버리지 않는다** — 예전에는 여기서 return 해 점수가 사라졌다(2026-09-27 진단의 1번 갈래).
            // 토큰을 기다리는 인편으로 적는다. 왕복 중인 요청이 있으면 그 응답이 이 인편에 온다(판 시작에 나간 요청이라
            // started_at 이 이 판보다 앞이다). 없으면 미는 쪽이 하나 띄운다.
            Self.miniGameLogger.notice(
                "submit waiting for token game=\(kind.rawValue, privacy: .public) score=\(score, privacy: .public)")
            miniGameSubmitNotice = MiniGameSubmitCopy.pending
        }
        miniGamePendingSubmits.append(MiniGamePendingSubmit(
            id: UUID(), kind: kind, score: score, token: token, tokenIssuedAt: issuedAt, recordedAt: Date(), attempts: 0))
        persistMiniGamePendingSubmits()
        retryMiniGamePendingSubmitIfAny()
    }

    // MARK: 제출 인편

    /// 이 게임의 인편이 하나라도 있는가(토큰 유무 무관).
    func hasMiniGamePendingSubmit(for kind: MiniGameKind) -> Bool {
        loadMiniGamePendingSubmitsIfNeeded()
        return miniGamePendingSubmits.contains { $0.kind == kind }
    }

    /// 인편을 민다 — 이름은 폰 `retryPendingSubmitIfAny()` 를 따른다. 방아쇠 다섯(머리 주석)이 전부 여기로 온다.
    ///
    /// 게임마다: 토큰을 실은 인편이 있으면 그것을 보낸다(백오프 중이면 기다린다). 전부 토큰을 기다리는 인편이면 맨 앞 것에
    /// 토큰을 받아 준다 — 왕복이 없을 때만 띄운다(있으면 그 응답이 온다). 같은 게임의 제출이 떠 있으면 건너뛴다
    /// (`miniGameSubmittingKinds` — 같은 토큰을 두 번 동시에 보내지 않는다). 인편이 없으면 no-op 이라 방아쇠마다 비용이 없다.
    ///
    /// - Parameter fromTrigger: 바깥 방아쇠(기본)면 모르는 status 로 붙든 인편(`heldUntilTrigger`)을 푼다. 제출·토큰 응답의
    ///   **꼬리**에서 부를 때는 false — 그 꼬리가 방아쇠로 치면 모르는 status 응답이 곧 다음 제출을 부르는 고리가 된다(두드리기).
    func retryMiniGamePendingSubmitIfAny(fromTrigger: Bool = true) {
        loadMiniGamePendingSubmitsIfNeeded()
        dropExpiredMiniGamePendingSubmits()
        if fromTrigger {
            for index in miniGamePendingSubmits.indices where miniGamePendingSubmits[index].heldUntilTrigger {
                miniGamePendingSubmits[index].heldUntilTrigger = false
            }
        }
        guard miniGamePublic, session != nil, !miniGamePendingSubmits.isEmpty else {
            scheduleMiniGamePendingRetry()
            return
        }
        let now = Date()
        for kind in MiniGameKind.allCases {
            guard !miniGameSubmittingKinds.contains(kind) else { continue }
            var entries = miniGamePendingSubmits.filter { $0.kind == kind }
            guard !entries.isEmpty else { continue }
            // 보험: 들고 있던 토큰이 이 게임 것인데 인편이 토큰을 기다린다면 넘겨준다(정상 흐름에선 recordMiniGameScore 가 이미 실었다).
            if !entries.contains(where: { $0.token != nil }), hasUsableMiniGameToken(for: kind), let held = miniGameRoundToken {
                miniGameRoundToken = nil
                miniGameRoundTokenKind = nil
                miniGameRoundTokenAt = nil
                _ = adoptMiniGameTokenIntoWaitingPending(kind: kind, token: held)
                entries = miniGamePendingSubmits.filter { $0.kind == kind }
            }
            if let ready = entries.first(where: { $0.token != nil }) {
                // 토큰을 실은 인편은 게임당 하나뿐이다(서버가 미사용 토큰을 한 행만 두므로 둘일 수 없다). 붙들렸거나 백오프
                // 중이면 이 게임은 통째로 건너뛴다 — 그 인편의 토큰이 살아 있으니 새 토큰도 청하지 않는다(불변식).
                if ready.heldUntilTrigger { continue }
                if let at = ready.nextRetryAt, at > now { continue }
                Task { @MainActor in await performSubmitMiniGameScore(entry: ready) }
                continue
            }
            // 전부 토큰을 기다리는 인편이다 — 맨 앞 것에 토큰을 받아 준다(응답은 performBeginMiniGameRound 가 인편에 넘긴다).
            guard let head = entries.first else { continue }
            if head.heldUntilTrigger { continue }
            if let at = head.nextRetryAt, at > now { continue }
            guard miniGameRoundTokenInFlightKind != kind else { continue }
            requestMiniGameRoundToken(kind: kind)
        }
        scheduleMiniGamePendingRetry()
    }

    /// 점수 업로드(performLoadTokenBoard 관용구: 세션 가드 → 세대 캡처 → withSessionRetry → 세대 가드). 성공하면 패널이
    /// 보이는 동안 오늘 순위를 다시 받아 방금 판이 바로 반영되게 한다.
    ///
    /// **거절은 화면에 말한다.** 예전에는 실패를 통째로 삼켰는데, 그때는 실패가 "서버가 아직 없다" 정도였다.
    /// 지금은 토큰 방식이라 거절이 곧 "이 판은 순위표에 안 올라간다"이고, 그걸 안 알리면
    /// "잘 놀았는데 순위표에 없다"가 된다 — 재현도 신고도 안 되는 종류다.
    ///
    /// 인편은 **성공과 terminal 거절에서만** 지운다. 네트워크 실패·세대 밀림·재시도 대상 거절은 남긴다.
    func performSubmitMiniGameScore(entry: MiniGamePendingSubmit) async {
        guard session != nil, let token = entry.token else { return }
        let kind = entry.kind
        guard !miniGameSubmittingKinds.contains(kind) else { return }
        miniGameSubmittingKinds.insert(kind)
        defer { miniGameSubmittingKinds.remove(kind) }
        await awaitWakeGate()
        let generation = sessionGeneration
        do {
            let response = try await withSessionRetry { activeSession in
                try await service.submitMiniGameScore(
                    accessToken: activeSession.accessToken, kind: kind, score: entry.score, token: token)
            }
            // 세대가 밀렸으면(계정 전환·재로그인) 이 응답으로 상태를 건드리지 않는다 — **이 가드는 지우지 않는다**(계정 전환 방어).
            // 인편은 **남는다** — 예전에는 여기서 조용히 버렸다(3번 갈래). 깃발만 내리고 인편을 한 번 더 민다: 세대를 올리는
            // 두 자리(signOut · clearPersistedSession)는 세션을 nil 로 만들므로 실사용에선 그 밀기가 no-op 이고, 인편은 디스크에
            // 남아 같은 계정의 다음 로그인에서 살아난다(키가 계정별이라 남의 계정으로는 안 나간다).
            guard generation == sessionGeneration else {
                miniGameSubmittingKinds.remove(kind)
                retryMiniGamePendingSubmitIfAny()
                return
            }
            // 꼬리에서 다음 인편을 밀어야 하므로 깃발은 **여기서** 내린다(defer 는 꼬리 뒤에 돈다 — 그때는 이미 늦다).
            miniGameSubmittingKinds.remove(kind)
            var reloadsBoard = false
            // 서버에 이 판이 남았다(v0.3.64 — 일일 미션이 세는 것은 제출된 판이다). 꼬리에서 도전 미션을 한 번 묻는다.
            var recorded = false
            if response.status == "ok" || response.status == "token_used" {
                recorded = true
                // ★ `token_used` 는 **성공이다.** 서버는 제출이 성공한 순간 그 토큰에 used_at 을 찍고, 이미 쓴 토큰에는
                //   `token_used` 를 돌려준다. 즉 이 응답을 받는 경우는 **응답만 유실된 첫 제출의 재시도**뿐이고,
                //   그때 점수는 이미 올라가 있다. 이걸 거절로 그리면 올라간 점수를 "못 올렸어요"라고 말하는 거짓말이 된다(5번 갈래).
                if response.status == "token_used" {
                    Self.miniGameLogger.notice("submit already recorded (token_used) game=\(kind.rawValue, privacy: .public)")
                }
                // 서버가 확정한 최고를 로컬에도 올린다(다른 맥에서 세운 기록이 섞여 있을 수 있다).
                if let best = response.bestScore { raiseMiniGameBest(kind, to: best) }
                removeMiniGamePendingSubmit(id: entry.id)
                if !hasMiniGamePendingSubmit(for: kind) { miniGameSubmitNotice = nil }
                // 창이 열려 있으면 재조회한다(팝오버는 닫혀 있어도 된다 — 게임은 별도 창이다). **아래 선발급 뒤에** 한다 —
                // 앞에 두면 두 왕복(순위·어제 1등)만큼 다음 판의 토큰이 늦어져 그 사이 시작한 짧은 판이 토큰 없이 끝난다.
                reloadsBoard = isMiniGamePanelVisible && miniGameKind == kind
                // 이 게임의 역대 표는 이제 낡았다(새 개인 최고가 들어갔을 수 있다). [역대] 를 보는 중이면 꼬리에서 바로 다시 받고,
                // 아니면 다음에 [역대] 로 넘어갈 때 받는다 — 보지도 않는 표를 판마다 받지 않는다.
                if miniGameAllTimeFreshKind == kind { miniGameAllTimeFreshKind = nil }
                // 떠 있는 받기가 이 제출 **전**에 떠났을 수 있다 — 그 응답이 늦게 닿아 '최신'을 다시 세우지 못하게 한다.
                miniGameAllTimeInvalidation &+= 1
            } else if Self.miniGameTerminalSubmitStatuses.contains(response.status) {
                // ⚠️ `need_seconds`/`elapsed_seconds` 는 **화면에도 로그에도 쓰지 않는다** — "얼마나 더
                //    기다리면 통과하는지"를 알려 주는 순간 그건 위조 보조 도구다. status 이름이면 진단에 충분하다.
                Self.miniGameLogger.notice(
                    "submit refused status=\(response.status, privacy: .public) game=\(kind.rawValue, privacy: .public)")
                // ★ `no_token` 은 **한 번은 되살린다.** 그 판은 진짜로 있었고 점수도 진짜다 — 죽은 것은 토큰뿐이다.
                //   토큰을 기다리는 인편으로 되돌리면 새 토큰을 받아 다시 올라간다(하한만큼 기다려야 통과하므로 서버 방어는
                //   그대로다). 실측 근거는 `recoveredFromDeadTokenOnce` 주석.
                if response.status == "no_token", !entry.recoveredFromDeadTokenOnce {
                    demoteMiniGamePendingToTokenWait(id: entry.id)
                    miniGameSubmitNotice = MiniGameSubmitCopy.pending
                    retryMiniGamePendingSubmitIfAny()
                    prefetchMiniGameRoundToken(kind: kind)
                    if reloadsBoard { await performLoadMiniGameBoard() }
                    return
                }
                removeMiniGamePendingSubmit(id: entry.id)
                // 토큰 만료만 이유를 밝힌다. 사람이 고칠 수 있는 유일한 거절이고("판을 너무 오래 끌었다"),
                // 위조 보조가 되지 않는다. 토큰이 죽은 거절은 "그 판은 영영 못 올라간다"로 문장을 가른다. 나머지는 이유를 밝히지 않는다.
                miniGameSubmitNotice = response.status == "token_expired"
                    ? MiniGameSubmitCopy.tokenExpired
                    : Self.miniGameDeadTokenStatuses.contains(response.status)
                        ? MiniGameSubmitCopy.tokenDead
                        : MiniGameSubmitCopy.refused
            } else if Self.miniGameRetryableSubmitStatuses.contains(response.status) {
                // `too_fast`: 토큰은 살아 있고(서버가 소모하기 전에 돌려준다) 경과는 자라기만 한다 — 같은 토큰으로 조금 뒤에
                // 다시 보내면 통과한다(4번 갈래). 예전에는 여기서 점수를 버렸다. 얼마나 기다릴지는 고정 백오프뿐이다.
                Self.miniGameLogger.notice(
                    "submit deferred status=\(response.status, privacy: .public) game=\(kind.rawValue, privacy: .public)")
                deferMiniGamePendingRetry(id: entry.id)
                miniGameSubmitNotice = MiniGameSubmitCopy.pending
            } else {
                // 모르는 status(신버전 서버). 이해 못 한 거절을 두드리지는 않되 점수를 버리지도 않는다 — 타이머 없이 남기고,
                // 방아쇠(깨어남·재활성화·창 열기·판 시작)에서만 다시 보낸다. TTL 이 끝을 낸다.
                Self.miniGameLogger.notice(
                    "submit refused (unknown status) status=\(response.status, privacy: .public) game=\(kind.rawValue, privacy: .public)")
                if let index = miniGamePendingSubmits.firstIndex(where: { $0.id == entry.id }) {
                    miniGamePendingSubmits[index].heldUntilTrigger = true
                }
                miniGameSubmitNotice = MiniGameSubmitCopy.pending
            }
            // 다음 인편(토큰을 기다리는 것)에 토큰을 받아 주고, 이 게임의 인편이 다 비었으면 다음 판 토큰을 미리 받아 둔다
            // (방금 쓴 토큰은 죽었다). 인편이 남아 있으면 선발급하지 않는다 — 그게 불변식이다. 이 꼬리는 방아쇠가 아니다(주석 위).
            retryMiniGamePendingSubmitIfAny(fromTrigger: false)
            if !hasMiniGamePendingSubmit(for: kind) { prefetchMiniGameRoundToken(kind: kind) }
            // 일일 미션(v0.3.64) — 판 제출이 성공한 뒤 한 번(새 타이머 없이 이벤트로). 선발급 **뒤**에 둔다(다음 판 토큰이 먼저다).
            // 오늘 이 게임 줄을 이미 채웠으면(받았든 안 받았든) 묻지 않는다 — 하루 첫 판만 나간다(검토 지적 2026-10-22).
            if recorded { refreshAchievementsAfterGameResult(game: kind.rawValue) }
            if reloadsBoard { await performLoadMiniGameBoard() }
            // 역대(v0.3.67) — [역대] 를 보는 중일 때만, 오늘 순위 **뒤에** 받는다(선발급·오늘 순위가 먼저다).
            if reloadsBoard, miniGameBoardScope == .allTime { await performLoadMiniGameAllTimeBoard() }
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else {
                miniGameSubmittingKinds.remove(kind)
                retryMiniGamePendingSubmitIfAny()
                return
            }
            miniGameSubmittingKinds.remove(kind)
            Self.miniGameLogger.notice("submit failed (network) game=\(kind.rawValue, privacy: .public)")
            // 네트워크 실패는 인편을 **남긴다**(2번 갈래) — 백오프 뒤, 그리고 다음 방아쇠에 같은 토큰으로 한 번 더 보낸다.
            deferMiniGamePendingRetry(id: entry.id)
            miniGameSubmitNotice = MiniGameSubmitCopy.pending
            // 인편이 살아 있으면 새 토큰은 안 받는다. 인편이 방금 TTL 로 버려졌을 때만 다음 판의 토큰을 미리 받는다.
            if !hasMiniGamePendingSubmit(for: kind) { prefetchMiniGameRoundToken(kind: kind) }
        }
    }

    /// 창을 닫아 둔 사이에 인편이 TTL 로 죽었다면 한 줄로 말하고 표식을 지운다(한 번만 말한다).
    func showMiniGameLostNoticeIfAny() {
        loadMiniGamePendingSubmitsIfNeeded()
        guard let owner = miniGamePendingSubmitsOwner,
              defaults.bool(forKey: Self.miniGameLostNoticeKey(userID: owner)) else { return }
        defaults.removeObject(forKey: Self.miniGameLostNoticeKey(userID: owner))
        miniGameSubmitNotice = MiniGameSubmitCopy.expired
    }

    /// 죽은 토큰(`no_token`)을 받은 인편을 **토큰을 기다리는 인편으로 되돌린다.** 점수는 그대로 두고 토큰만 버린다.
    /// 백오프는 0 으로 되돌린다 — 새 토큰을 받는 일은 앞의 실패와 다른 일이다. 표식을 세워 두 번은 오지 않는다.
    func demoteMiniGamePendingToTokenWait(id: UUID) {
        guard let index = miniGamePendingSubmits.firstIndex(where: { $0.id == id }) else { return }
        miniGamePendingSubmits[index].token = nil
        miniGamePendingSubmits[index].tokenIssuedAt = nil
        miniGamePendingSubmits[index].attempts = 0
        miniGamePendingSubmits[index].nextRetryAt = nil
        miniGamePendingSubmits[index].heldUntilTrigger = false
        miniGamePendingSubmits[index].recoveredFromDeadTokenOnce = true
        persistMiniGamePendingSubmits()
        Self.miniGameLogger.notice(
            "pending submit recovered from dead token game=\(self.miniGamePendingSubmits[index].kind.rawValue, privacy: .public)")
    }

    /// 토큰을 기다리는 이 게임의 맨 앞 인편에 토큰을 넘긴다. 넘겼으면 true(호출자가 인편을 민다).
    func adoptMiniGameTokenIntoWaitingPending(kind: MiniGameKind, token: String) -> Bool {
        guard let index = miniGamePendingSubmits.firstIndex(where: { $0.kind == kind && $0.token == nil }) else { return false }
        miniGamePendingSubmits[index].token = token
        miniGamePendingSubmits[index].tokenIssuedAt = Date()
        miniGamePendingSubmits[index].nextRetryAt = nil
        persistMiniGamePendingSubmits()
        return true
    }

    /// 실패한 인편의 백오프를 한 단계 올리고 타이머를 다시 잡는다(n번째 실패 → `miniGamePendingRetryDelays[n-1]`, 끝은 반복).
    func deferMiniGamePendingRetry(id: UUID) {
        guard let index = miniGamePendingSubmits.firstIndex(where: { $0.id == id }) else { return }
        miniGamePendingSubmits[index].attempts += 1
        let delays = miniGamePendingRetryDelays
        let step = min(max(miniGamePendingSubmits[index].attempts - 1, 0), max(delays.count - 1, 0))
        let delay = delays.isEmpty ? 30 : delays[step]
        miniGamePendingSubmits[index].nextRetryAt = Date().addingTimeInterval(delay)
        persistMiniGamePendingSubmits()
        scheduleMiniGamePendingRetry()
    }

    /// 토큰 요청이 실패했는데 그 게임에 토큰을 기다리는 인편이 있으면 — 그 인편의 백오프를 올린다(다음 요청은 타이머가 띄운다).
    func deferMiniGamePendingTokenWait(kind: MiniGameKind) {
        guard let head = miniGamePendingSubmits.first(where: { $0.kind == kind && $0.token == nil }) else { return }
        deferMiniGamePendingRetry(id: head.id)
    }

    /// 백오프 타이머 한 개 — 가장 먼저 돌아오는 인편의 시각에 맞춘다. 돌아오면 인편을 민다. 기다릴 것이 없으면 거둔다.
    func scheduleMiniGamePendingRetry() {
        miniGamePendingRetryTask?.cancel()
        miniGamePendingRetryTask = nil
        let now = Date()
        let ttl = Self.miniGamePendingSubmitTTL
        // TTL 을 넘겨서 돌아오는 재시도는 잡지 않는다(그때는 어차피 읽으면서 버린다).
        guard let next = miniGamePendingSubmits
            .compactMap({ entry -> Date? in
                guard let at = entry.nextRetryAt, at > now, at < entry.deadline(ttl: ttl) else { return nil }
                return at
            })
            .min() else { return }
        let delay = next.timeIntervalSince(now)
        miniGamePendingRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.miniGamePendingRetryTask = nil
            self.retryMiniGamePendingSubmitIfAny()
        }
    }

    /// 인편 하나를 지우고 영속본을 맞춘다.
    func removeMiniGamePendingSubmit(id: UUID) {
        guard miniGamePendingSubmits.contains(where: { $0.id == id }) else { return }
        miniGamePendingSubmits.removeAll { $0.id == id }
        persistMiniGamePendingSubmits()
    }

    /// TTL 을 넘긴 인편을 버린다(토큰이 죽었다). 창이 열려 있으면 그 사실을 말한다 — 재시작 직후(창 없음)엔 로그만 남는다.
    func dropExpiredMiniGamePendingSubmits() {
        let now = Date()
        let ttl = Self.miniGamePendingSubmitTTL
        let expired = miniGamePendingSubmits.filter { $0.isExpired(at: now, ttl: ttl) }
        guard !expired.isEmpty else { return }
        for entry in expired {
            Self.miniGameLogger.notice(
                "pending submit expired game=\(entry.kind.rawValue, privacy: .public) score=\(entry.score, privacy: .public)")
        }
        let gone = Set(expired.map(\.id))
        miniGamePendingSubmits.removeAll { gone.contains($0.id) }
        persistMiniGamePendingSubmits()
        // 창이 열려 있으면 그 자리에서 말한다. 닫혀 있으면 **표식을 남겨 다음에 창을 열 때 말한다** — 안 그러면
        // 로그에만 남아 사용자는 그 판이 사라진 것을 영영 모른다(2026-09-27 검토에서 남은 마지막 구멍이었다).
        if isMiniGamePanelVisible {
            miniGameSubmitNotice = MiniGameSubmitCopy.expired
        } else if let owner = miniGamePendingSubmitsOwner {
            defaults.set(true, forKey: Self.miniGameLostNoticeKey(userID: owner))
        }
    }

    /// 메모리의 인편이 지금 계정 것이 아니면(처음 · 계정 전환 · 재로그인) 그 계정의 키에서 읽는다. TTL 을 넘긴 것은 여기서 버린다.
    func loadMiniGamePendingSubmitsIfNeeded() {
        let owner = session?.userID
        guard miniGamePendingSubmitsOwner != owner else { return }
        miniGamePendingSubmitsOwner = owner
        guard let owner else {
            miniGamePendingSubmits = []
            return
        }
        guard let data = defaults.data(forKey: Self.miniGamePendingKey(userID: owner)),
              let restored = try? JSONDecoder().decode([MiniGamePendingSubmit].self, from: data) else {
            miniGamePendingSubmits = []
            return
        }
        miniGamePendingSubmits = restored
        dropExpiredMiniGamePendingSubmits()
        if !miniGamePendingSubmits.isEmpty {
            Self.miniGameLogger.notice("pending submits restored count=\(self.miniGamePendingSubmits.count, privacy: .public)")
        }
    }

    /// 영속본을 메모리와 맞춘다. 비었으면 키를 지운다. 주인이 없으면(로그아웃 상태) 쓰지 않는다.
    func persistMiniGamePendingSubmits() {
        guard let owner = miniGamePendingSubmitsOwner else { return }
        let key = Self.miniGamePendingKey(userID: owner)
        if miniGamePendingSubmits.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(miniGamePendingSubmits) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: 오늘 순위 · 어제 1등

    /// 오늘 순위를 로드한다(Task 발사). 패널을 여는 순간·팝오버 재오픈·종류 전환·제출 성공에서 호출한다.
    func loadMiniGameBoard() {
        Task { @MainActor in await performLoadMiniGameBoard() }
    }

    /// minigame_board(오늘) + minigame_yesterday_winner 를 받아 반영한다. 두 조회는 **독립 실패**다 — 어제 1등을 못 받아도
    /// 오늘 순위는 그린다. 응답이 오는 사이 게임 종류를 바꿨으면 낡은 게임의 응답이라 버린다(월 이동 스냅백과 같은 규약).
    func performLoadMiniGameBoard() async {
        guard session != nil else { return }
        let kind = miniGameKind
        let generation = sessionGeneration
        if !miniGameBoardLoading { miniGameBoardLoading = true }
        if miniGameBoardFailed { miniGameBoardFailed = false }
        defer { if kind == miniGameKind, miniGameBoardLoading { miniGameBoardLoading = false } }
        do {
            let entries = try await withSessionRetry { activeSession in
                try await service.fetchMiniGameBoard(accessToken: activeSession.accessToken, kind: kind, day: nil)
            }
            guard generation == sessionGeneration, kind == miniGameKind else { return }
            let sorted = entries.sortedForMiniGameBoard()
            if miniGameBoard != sorted { miniGameBoard = sorted }
            if !miniGameBoardLoaded { miniGameBoardLoaded = true }
            if miniGameBoardFailed { miniGameBoardFailed = false }
            // 내 행이 로컬 최고보다 크면(다른 맥에서 세운 기록) 로컬 캐시를 올린다 — "최고 N"이 맥마다 다르게 보이지 않게.
            if let me = session?.userID, let mine = sorted.first(where: { $0.userID == me }) {
                raiseMiniGameBest(kind, to: mine.bestScore)
            }
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration, kind == miniGameKind else { return }
            if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                // 마이그레이션 전 창(브루 배포가 db push 보다 앞선 경우): 실패가 아니라 '아직 표가 없다'. 빈 목록으로 조용히 접는다 —
                // 실패 문구와 [다시 시도] 는 사용자가 고칠 수 있는 일에만 쓴다.
                if !miniGameBoardLoaded { miniGameBoardLoaded = true }
            } else {
                if !miniGameBoardFailed { miniGameBoardFailed = true }
            }
            return
        }
        // 어제 1등(상품 표시). 실패해도 위 순위는 이미 반영됐다.
        let winner = try? await withSessionRetry { activeSession in
            try await service.fetchMiniGameYesterdayWinner(accessToken: activeSession.accessToken, kind: kind)
        }
        guard generation == sessionGeneration, kind == miniGameKind else { return }
        if let winner, miniGameYesterdayWinner != winner { miniGameYesterdayWinner = winner }
        if winner == nil, miniGameYesterdayWinner != nil { miniGameYesterdayWinner = nil }
    }

    // MARK: 역대 순위 (v0.3.67)
    //
    // 사용자 결정(2026-10-27): "미니게임 멀티 아닌 3종 에서 역대 최고 점수 랭킹 볼 수 있는 창도 만들어줘."
    // 순위 열 머리의 [오늘 | 역대] 가 이 절을 부른다. 받는 때는 넷뿐이다 — ① [역대] 로 넘어갈 때(그 게임 표가 최신이 아닐 때만)
    // ② [역대] 를 보는 중에 게임을 바꿀 때 ③ [역대] 를 보는 중에 판이 기록됐을 때 ④ [역대] 를 보던 채로 창을 다시 열 때.
    // 30초 루프에 얹지 않는다(오늘 순위와 같은 이유).

    /// 순위 열의 [오늘 | 역대] 전환. 같은 쪽을 다시 누르면 아무 일도 없다.
    /// [역대] 로 넘어갈 때 그 게임의 최신 표를 들고 있으면 **다시 받지 않는다**(오가며 누를 때마다 요청이 나가지 않게).
    /// 실패한 채였으면 넘어갈 때 한 번 더 받는다 — 사용자가 다시 보러 온 것이 곧 재시도 의사다.
    func selectMiniGameBoardScope(_ scope: MiniGameBoardScope) {
        guard scope != miniGameBoardScope else { return }
        miniGameBoardScope = scope
        guard scope == .allTime else { return }
        guard miniGameAllTimeFreshKind != miniGameKind || miniGameAllTimeFailed else { return }
        // 첫 프레임부터 빈 자리에 "불러오는 중…"이 뜨게 한다(오늘 순위와 같은 규약 — 본문 자리에 엉뚱한 문구 금지).
        if !miniGameAllTimeLoaded { miniGameAllTimeLoading = true }
        loadMiniGameAllTimeBoard()
    }

    /// 역대 순위를 받는다(Task 발사). 위 네 방아쇠와 [다시 시도] 가 부른다.
    func loadMiniGameAllTimeBoard() {
        Task { @MainActor in await performLoadMiniGameAllTimeBoard() }
    }

    /// `minigame_alltime_board` 를 받아 반영한다. 응답이 오는 사이 게임을 바꿨거나 계정이 바뀌었으면 버린다(오늘 순위와 같은 가드).
    ///
    /// 실패는 셋으로 가른다.
    ///  · 서버에 함수가 아직 없다(PGRST202 · 본문 없는 404) → **준비 중**(빈 표 + `miniGameAllTimeUnavailable`). 실패 문구도
    ///    [다시 시도] 도 없다 — 앱이 db push 보다 먼저 나간 창이고, 두드려 봐야 같은 답이다(오류 고리를 만들지 않는다).
    ///  · 그 밖(네트워크 · 5xx · 배열이 아닌 본문) → 실패. 이미 그린 표가 있으면 그대로 두고, 없을 때만 실패 문구 + [다시 시도].
    ///  · 취소 → 아무것도 안 바꾼다.
    func performLoadMiniGameAllTimeBoard() async {
        guard session != nil else { return }
        let kind = miniGameKind
        let generation = sessionGeneration
        // 떠날 때의 낡음 표시 횟수와 일련번호(v0.3.67 — `miniGameAllTimeInvalidation` 주석).
        let invalidation = miniGameAllTimeInvalidation
        miniGameAllTimeFetchSerial &+= 1
        let serial = miniGameAllTimeFetchSerial
        if !miniGameAllTimeLoading { miniGameAllTimeLoading = true }
        if miniGameAllTimeFailed { miniGameAllTimeFailed = false }
        defer { if kind == miniGameKind, miniGameAllTimeLoading { miniGameAllTimeLoading = false } }
        do {
            let entries = try await withSessionRetry { activeSession in
                try await service.fetchMiniGameAllTimeBoard(accessToken: activeSession.accessToken, kind: kind)
            }
            guard generation == sessionGeneration, kind == miniGameKind else { return }
            // 뒤에 떠난 받기가 이미 반영됐으면 이 (옛) 응답은 버린다 — 새 표를 옛 표로 덮지 않는다.
            guard serial > miniGameAllTimeAppliedSerial else { return }
            miniGameAllTimeAppliedSerial = serial
            let sorted = entries.sortedForMiniGameAllTimeBoard()
            if miniGameAllTimeBoard != sorted { miniGameAllTimeBoard = sorted }
            if !miniGameAllTimeLoaded { miniGameAllTimeLoaded = true }
            if miniGameAllTimeFailed { miniGameAllTimeFailed = false }
            if miniGameAllTimeUnavailable { miniGameAllTimeUnavailable = false }
            // 떠난 뒤에 낡음 표시가 있었으면(그 사이 판이 기록됐다) **최신으로 표시하지 않는다** — 다음에 [역대] 로 넘어가면 다시 받는다.
            if invalidation == miniGameAllTimeInvalidation { miniGameAllTimeFreshKind = kind }
            // 내 역대 행은 이 계정의 **진짜** 전체 기간 최고다 — 로컬 캐시("최고 N")가 그보다 작으면(다른 맥 · 재설치) 올린다.
            if let me = session?.userID, let mine = sorted.first(where: { $0.userID == me }) {
                raiseMiniGameBest(kind, to: mine.bestScore)
            }
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration, kind == miniGameKind else { return }
            if let serviceError = error as? SupabaseWorkServiceError, BlockReportRules.isMissingFunction(serviceError) {
                if !miniGameAllTimeBoard.isEmpty { miniGameAllTimeBoard = [] }
                if !miniGameAllTimeUnavailable { miniGameAllTimeUnavailable = true }
                if !miniGameAllTimeLoaded { miniGameAllTimeLoaded = true }
                // 같은 게임으로 오가며 누를 때마다 404 를 다시 두드리지 않는다(판 기록 · 게임 전환 · 창 열기가 다시 묻는다).
                miniGameAllTimeFreshKind = kind
            } else {
                Self.miniGameLogger.notice("alltime board fetch failed game=\(kind.rawValue, privacy: .public)")
                if !miniGameAllTimeFailed { miniGameAllTimeFailed = true }
            }
        }
    }

    // MARK: 공개 설정

    /// 미니게임 순위 공개 토글(낙관 반영 → PATCH, 실패 시 원복). 토큰 공개 토글과 같은 규약이다.
    func setMiniGamePublic(_ isPublic: Bool) {
        guard miniGamePublic != isPublic else { return }
        let previous = miniGamePublic
        miniGamePublic = isPublic
        // 사용자가 명시적으로 정한 값이므로 로드 완료로 간주한다(폴링 첫 tick 이 이 선택을 덮지 않게).
        miniGamePublicLoaded = true
        guard session != nil else { return }
        let generation = sessionGeneration
        Task { @MainActor in
            do {
                try await withSessionRetry { activeSession in
                    try await service.updateMiniGamePublic(
                        accessToken: activeSession.accessToken, userID: activeSession.userID, isPublic: isPublic)
                }
            } catch {
                if case .cancelled = classifyAuthError(error) { return }
                guard generation == sessionGeneration else { return }
                miniGamePublic = previous
            }
        }
    }
}

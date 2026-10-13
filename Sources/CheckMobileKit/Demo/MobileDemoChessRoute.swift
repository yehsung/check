#if DEBUG
/// 데모 스크린샷 라우트 `games/chess/…` 한 건을 **값으로 푼 것**(DEBUG 전용).
///
/// ── 왜 `Demo/` 안이고 파일 통째가 `#if DEBUG` 인가 ──
/// Release 바이너리에서 **이름이 사라져야** 한다. 1.0.6(build 16) 아카이브에서 이 타입이 구성 분기 없이
/// 선언돼 있어 Swift 가 타입 이름(nominal type descriptor)을 Release 바이너리에 넣었고, 출시 게이트
/// `ios/scripts/check-release-app.sh` 의 금지 문자열 `MobileDemo` 가 그것을 물어 아카이브가 막혔다
/// ("0 이 아니면 올리지 않는다" — SPEC-ios §0-2 '컴파일에서 사라졌다는 증거'). 데모 기계는 전부 이 폴더
/// 안 `#if DEBUG` 이라는 것이 저장소 관례이고(`MobileDemo` · `MobileDemoGomokuAI` · `MobileStubURLProtocol`,
/// Package.swift 의 리소스 주석도 "읽는 코드(Demo/*.swift)는 #if DEBUG" 라고 적어 뒀다), 이 값만 그
/// 관례 밖(`App/MobileAppModel.swift`)에 있었다 — 통합 레인이 늦게 넣은 값 타입이다.
///
/// **동작은 한 글자도 바뀌지 않았다**: `environment.demoRoute` 를 세우는 글자(`AingCheckDemo`)가 Release
/// 바이너리에 0건이라 그 구성에서는 `demoChessRoute` 가 **원래부터 영원히 nil** 이었다(실측). 고친 것은
/// 동작이 아니라 **"컴파일에서 사라졌다"는 증거**다. 되돌리면 `GamesChessDemoRouteTests` 의
/// §4(`theDemoTailIsDebugOnly`)가 `swift test` 에서 빨개진다 — 아카이브까지 가지 않는다.
///
/// ── 여전히 `#if os(iOS)` 는 금지다 ──
/// 플랫폼 분기와 구성 분기는 다른 것이다. 체스 화면은 전부 `#if os(iOS)` 안이라 맥 스위트가 한 줄도 못 보므로
/// (저장소 메모 '폰 뷰는 맥 스위트가 못 본다') 라우트 → 화면 판정은 **플랫폼 분기 없는 값**인 여기 있어야
/// `swift test` 가 라우트마다 다른 결과를 잴 수 있다(결함 D6 — 꼬리를 버리자 일곱 중 여섯 장이 바이트 동일).
/// `#if DEBUG` 는 그 근거를 깨지 않는다: 테스트는 Debug 로 도니까 맥 스위트는 이 타입을 그대로 본다.
/// 그래서 이 타입에 **`#if os(iOS)` 를 더하면 안 된다** — 더하는 순간 그 그물이 통째로 사라진다.
///
/// ## 꼬리가 정하는 것 셋
/// | 라우트                          | focusMatchID      | watchMatchID    | section |
/// | ------------------------------- | ----------------- | --------------- | ------- |
/// | `games/chess`                   | nil               | nil             | top     |
/// | `games/chess/lobby`             | nil               | nil             | top     |
/// | `games/chess/lobby/invites`     | nil               | nil             | top     |
/// | `games/chess/match`             | nil (장면이 세운다) | nil             | top     |
/// | `games/chess/match/<id>`        | `<id>`            | nil             | top     |
/// | `games/chess/ranking[/unlisted]`| nil               | nil             | bottom  |
/// | `games/chess/watch/<id>`        | nil               | `<id>`          | bottom  |
///
/// `games/chess/match` 의 `focusMatchID` 가 **nil 인 것이 맞다**: 그 라우트는 장면 폴더
/// `_games-chess-match` 가 있고 그 로비 픽스처의 `me.active_match_id` 가 판을 가리킨다(코어가 그 값으로 판을 연다).
/// 꼬리가 붙은 `match/<id>` 는 장면 폴더가 없어 **바깥 층 로비**(진행 판 없음)로 떨어지므로 — 그 하나가
/// 이 값이 필요한 까닭이다 — 꼬리의 id 를 코어 문에 직접 흘려 넣는다.
package struct MobileDemoChessRoute: Hashable, Sendable {
    /// 로비 스크롤이 시작할 자리. 순위·관전은 **별도 화면이 아니라 로비 안 절**이라(화면 머리말 —
    /// 자식 화면을 push 하면 `onDisappear` 로 폴링이 죽는다) 옮기는 것은 화면이 아니라 **닻**이다.
    package enum Section: String, Hashable, Sendable {
        /// 머리부터(전적·루비 → 신청 → 상대 목록).
        case top
        /// 맨 아래 절(지금 대결 중·관전 판 → 순위).
        case bottom
    }

    /// 열 **내 판**(`games/chess/match/<id>`). 코어 문 `ChessStore.openWindow(focusMatchID:)` 로 간다.
    package var focusMatchID: String?
    /// 걸 **관전**(`games/chess/watch/<id>`). `ChessStore.startWatching(matchID:)` 로 간다 —
    /// 데모에는 합성 탭이 없어 [관전] 칩을 누를 길이 없다(작업 규칙 §0-1).
    package var watchMatchID: String?
    /// 로비 스크롤 시작 자리.
    package var section: Section

    package init(focusMatchID: String? = nil, watchMatchID: String? = nil, section: Section = .top) {
        self.focusMatchID = focusMatchID
        self.watchMatchID = watchMatchID
        self.section = section
    }

    /// `games/chess` 뒤의 토막들로 세운다. 모르는 꼬리는 **로비 머리**로 접는다(라우트를 조용히 버리지 않는다).
    package init(tail: [String]) {
        switch (tail.first, tail.count) {
        case ("match", 2):
            self.init(focusMatchID: tail[1].lowercased())
        case ("watch", 2):
            // 관전 절은 로비 **아래**에 있다 — 관전을 걸어 놓고 머리에서 시작하면 화면에 안 보인다.
            self.init(watchMatchID: tail[1].lowercased(), section: .bottom)
        case ("watch", 1), ("ranking", _):
            self.init(section: .bottom)
        default:
            self.init()
        }
    }
}
#endif
